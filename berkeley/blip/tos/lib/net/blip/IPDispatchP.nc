/*
 * "Copyright (c) 2008 The Regents of the University  of California.
 * All rights reserved."
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 */

/*
 * This file has the potential to be rather confusing, here are a few
 * notes about what is happening.  There are several state machines in
 * this file.  Together, they take care of packet forwarding and
 * sending (which is accomplished by injecting new packets into the
 * outgoing queue.)
 *
 * Messages enter from two places: either from the bottom (from the
 * radio), or from the top (from the application).  Messages also
 * leave from two places: either out over the radio, or up to an
 * application.
 *
 *
 *    IP.send          ---- - --->   IP.recvfrom
 *                         \ /
 *                          X
 *                         / \
 *    IEEE154.receive  ---- - --->   IEEE154.send
 *
 *
 *  All of the queueing is done on the output; when each message
 *  arrives, it is dispatched all the way to an output queue.
 *
 *  There are four paths through the system, so here they are:
 *
 *  IP.send -> IP.recvfrom       :  local delivery: not implemented
 *  IP.send -> IEEE154.send      :  enqueue fragments on radio queue
 *  IEEE154.receive -> IP.recv   :  deliver to this mote : reassemble and deliver
 *  IEEE154.receive -> IEEE154.send : forwarding : enqueue fragments
 *
 *  the IP receive queue
 *   data structures:  
 *      recon_cache: holds state about packets which are to be consumed 
 *               by this mote, and have fragments pending.
 *
 *  radio send queue
 *   data structures:
 *      send_info_t: packet metadata for a single packet flow through 
 *                   the mote (could either come from a forwarded stream 
 *                   or a local send.    
 *      send_entry_t: the actual queue items, pointing to a fragment  
 *                   and the packet metadata (send_info_t)
 *
 *  extra forwarding structures:
 *    forward_cache: used to match up incoming fragments with their flow metadata,
 *               stored in a send_info_t.
 *    fragment pool: 
 */
#include <6lowpan.h>
#include <lib6lowpan.h>
#include <ip.h>
#include <in_cksum.h>
#include <ip_malloc.h>
#include "IPDispatch.h"
#include "table.h"
#include "PrintfUART.h"
#ifdef PRINTF_LIBRARY
#include "printf.h"
#endif

/*
 * Provides IP layer reception to applications on motes.
 *
 * @author Stephen Dawson-Haggerty <stevedh@cs.berkeley.edu>
 */

module IPDispatchP {
  provides {
    interface SplitControl;
    // interface for protocols not requiring special hand-holding
    interface IP[uint8_t nxt_hdr];
    interface Statistics<ip_statistics_t>;
  }
  uses {
    interface Boot;
    interface SplitControl as RadioControl;

    interface CC2420Packet;
    interface Packet;

#ifndef SIM
    interface Ieee154Send;
    interface Ieee154Packet;
#else
    interface AMSend as Ieee154Send;
    interface AMPacket as Ieee154Packet;
#endif
    interface Receive as Ieee154Receive;

    interface PacketLink;

    // outgoing fragments
    interface Pool<message_t> as FragPool;
    interface Pool<send_info_t> as SendInfoPool;
    interface Pool<send_entry_t> as SendEntryPool;
    interface Queue<send_entry_t *> as SendQueue;

    interface Timer<TMilli> as ExpireTimer;

    interface IPRouting;
    interface ICMP;

    interface LowPowerListening;

    interface Leds;
    
    interface IPAddress;

#ifdef DBG_TRACK_FLOWS
    command flow_id_t *getFlowID(message_t *);
#endif

  }
} implementation {
  
#include "table.c"

  enum {
    S_RUNNING,
    S_STOPPED,
    S_STOPPING,
  };
  uint8_t state = S_STOPPED;
  bool radioBusy;
  ip_statistics_t stats;

  // this in theory could be arbitrarily large; however, it needs to
  // be large enough to hold all active reconstructions, and any tags
  // which we are dropping.  It's important to keep dropped tags
  // around for a while, or else there are pathological situations
  // where you continually allocate buffers for packets which will
  // never complete.

  ////////////////////////////////////////
  //
  //

  table_t recon_cache, forward_cache;


  // table of packets we are currently receiving fragments from, that
  // are destined to us
  reconstruct_t recon_data[N_RECONSTRUCTIONS];

  // table of fragmented flows who are going through us, so we must
  // remember the next hop.
  forward_entry_t forward_data[N_FORWARD_ENT];

  //
  //
  ////////////////////////////////////////

#ifdef DBG_TRACK_FLOWS
  uint16_t dbg_flowid = 0;
#endif

#ifndef SIM
#define CHECK_NODE_ID if (0) return
#else
#define CHECK_NODE_ID if (TOS_NODE_ID == BASESTATION_ID) return 
#endif

  task void sendTask();

  void reconstruct_clear(void *ent) {
    reconstruct_t *recon = (reconstruct_t *)ent;
    ip_memclr((uint8_t *)&recon->metadata, sizeof(struct ip_metadata));
    recon->timeout = T_UNUSED;
    recon->buf = NULL;
  }

  void forward_clear(void *ent) {
    forward_entry_t *fwd = (forward_entry_t *)ent;
    fwd->timeout = T_UNUSED;
  }

  int forward_unused(void *ent) {
    forward_entry_t *fwd = (forward_entry_t *)ent;
    if (fwd->timeout == T_UNUSED) 
      return 1;
    return 0;
  }

  uint16_t forward_lookup_tag;
  uint16_t forward_lookup_src;
  int forward_lookup(void *ent) {
    forward_entry_t *fwd = (forward_entry_t *)ent;
    if (fwd->timeout > T_UNUSED && 
        fwd->l2_src == forward_lookup_src &&
        fwd->old_tag == forward_lookup_tag) {
      fwd->timeout = T_ACTIVE;
      return 1;
    }
    return 0;
  }
  

  send_info_t *getSendInfo() {
    send_info_t *ret = call SendInfoPool.get();
    if (ret == NULL) return ret;
    ret->refcount = 1;
    ret->failed = FALSE;
    ret->frags_sent = 0;
    return ret;
  }
#define SENDINFO_INCR(X) ((X)->refcount)++
#define SENDINFO_DECR(X) if (--((X)->refcount) == 0) call SendInfoPool.put(X)

  command error_t SplitControl.start() {
    CHECK_NODE_ID FAIL;
    return call RadioControl.start();
  }

  command error_t SplitControl.stop() {
    if (!radioBusy) {
      state = S_STOPPED;
      return call RadioControl.stop();
    } else {
      // if there's a packet in the radio, wait for it to exit before
      // stopping
      state = S_STOPPING;
      return SUCCESS;
    }
  }

  event void RadioControl.startDone(error_t error) {
#ifdef LPL_SLEEP_INTERVAL
    call LowPowerListening.setLocalSleepInterval(LPL_SLEEP_INTERVAL);
#endif
    if (error == SUCCESS) {
      call ICMP.sendSolicitations();
      state = S_RUNNING;
    }
    signal SplitControl.startDone(error);
  }

  event void RadioControl.stopDone(error_t error) {
    signal SplitControl.stopDone(error);
  }

  event void Boot.booted() {
    CHECK_NODE_ID;
    call Statistics.clear();

    ip_malloc_init();

    table_init(&recon_cache, recon_data, sizeof(reconstruct_t), N_RECONSTRUCTIONS);
    table_init(&forward_cache, forward_data, sizeof(forward_entry_t), N_FORWARD_ENT);

    table_map(&recon_cache, reconstruct_clear);
    table_map(&forward_cache, forward_clear);

    radioBusy = FALSE;

    call ExpireTimer.startPeriodic(FRAG_EXPIRE_TIME);

    call SplitControl.start();
    return;
  }

  /*
   *  Receive-side code.
   */ 

  /*
   * Logic which must process every received IP datagram.
   *
   *  Each IP packet may be consumed and/or forwarded.
   */
  void signalDone(reconstruct_t *recon) {
    struct ip6_hdr *iph = (struct ip6_hdr *)recon->buf;
    signal IP.recv[recon->nxt_hdr](iph, recon->transport_hdr, &recon->metadata);
    ip_free(recon->buf);
    recon->timeout = T_UNUSED;
    recon->buf = NULL;
  }

  /*
   * Bulletproof recovery logic is very important to make sure we
   * don't get wedged with no free buffers.
   * 
   * The table is managed as follows:
   *  - unused entries are marked T_UNUSED
   *  - entries which 
   *     o have a buffer allocated
   *     o have had a fragment reception before we fired
   *     are marked T_ACTIVE
   *  - entries which have not had a fragment reception during the last timer period
   *     and were active are marked T_ZOMBIE
   *  - zombie receptions are deleted: their buffer is freed and table entry marked unused.
   *  - when a fragment is dropped, it is entered into the table as T_FAILED1.
   *     no buffer is allocated
   *  - when the timer fires, T_FAILED1 entries are aged to T_FAILED2.
   * - T_FAILED2 entries are deleted.  Incomming fragments with tags
   *     that are marked either FAILED1 or FAILED2 are dropped; this
   *     prevents us from allocating a buffer for a packet which we
   *     have already dropped fragments from.
   *
   */ 
  void reconstruct_age(void *elt) {
    reconstruct_t *recon = (reconstruct_t *)elt;
    switch (recon->timeout) {
    case T_ACTIVE:
      recon->timeout = T_ZOMBIE; break; // age existing receptions
    case T_FAILED1:
      recon->timeout = T_FAILED2; break; // age existing receptions
    case T_ZOMBIE:
    case T_FAILED2:
      // deallocate the space for reconstruction
      if (recon->buf != NULL) {
        ip_free(recon->buf);
      }
      recon->timeout = T_UNUSED;
      recon->buf = NULL;
      break;
    }
  }

  void forward_age(void *elt) {
    forward_entry_t *fwd = (forward_entry_t *)elt;
    switch (fwd->timeout) {
    case T_ACTIVE:
      fwd->timeout = T_ZOMBIE; break; // age existing receptions
    case T_FAILED1:
      fwd->timeout = T_FAILED2; break; // age existing receptions
    case T_ZOMBIE:
    case T_FAILED2:
      fwd->s_info->failed = TRUE;
      SENDINFO_DECR(fwd->s_info);
      fwd->timeout = T_UNUSED;
      break;
    }
  }

  void ip_print_heap() {
#ifdef PRINTFUART_ENABLED
    bndrt_t *cur = (bndrt_t *)heap;
    while (((uint8_t *)cur)  - heap < IP_MALLOC_HEAP_SIZE) {
      //printfUART ("heap region start: 0x%x length: %i used: %i\n", 
                  //cur, (*cur & IP_MALLOC_LEN), (*cur & IP_MALLOC_INUSE) >> 15);
      cur = (bndrt_t *)(((uint8_t *)cur) + ((*cur) & IP_MALLOC_LEN));
    }
#endif
  }

  event void ExpireTimer.fired() {
    CHECK_NODE_ID;
    table_map(&recon_cache, reconstruct_age);
    table_map(&forward_cache, forward_age);

    /*
    printfUART("Frag pool size: %i\n", call FragPool.size());
    printfUART("SendInfo pool size: %i\n", call SendInfoPool.size());
    printfUART("SendEntry pool size: %i\n", call SendEntryPool.size());
    printfUART("Forward queue length: %i\n", call SendQueue.size());
    */
    ip_print_heap();
  }

  /*
   * allocate a structure for recording information about incomming fragments.
   */

  reconstruct_t *get_reconstruct(ieee154_saddr_t src, uint16_t tag) {
    reconstruct_t *ret = NULL;
    int i;
    for (i = 0; i < N_RECONSTRUCTIONS; i++) {
      reconstruct_t *recon = (reconstruct_t *)&recon_data[i];
      dbg("IPDispatch", " 0x%x 0x%x 0x%x\n",  recon->timeout, recon->metadata.sender, recon->tag);

      if (recon->tag == tag &&
          recon->metadata.sender == src) {

        if (recon->timeout > T_UNUSED) {
          
          recon->timeout = T_ACTIVE;
          return recon;

        } else if (recon->timeout < T_UNUSED) {
          // if we have already tried and failed to get a buffer, we
          // need to drop remaining fragments.
          return NULL;
        }
      }
      if (recon->timeout == T_UNUSED) 
        ret = recon;
    }
    return ret;
  }
  
  /*
   * This is called before a receive on packets with a source routing header.
   *
   * it updates the path stored in the header to remove our address
   * and include our predicessor.
   *
   * However, if this is not a source record path and we are not in the current
   *  spot, this means we are along the default path and so should invalidate this
   *  source header.
   */
  void updateSourceRoute(ieee154_saddr_t prev_hop, struct source_header *sh) {
    uint16_t my_address = call IPAddress.getShortAddr();
    if ((sh->dispatch & IP_EXT_SOURCE_INVAL) == IP_EXT_SOURCE_INVAL) return;
    if (((sh->dispatch & IP_EXT_SOURCE_RECORD) != IP_EXT_SOURCE_RECORD) && 
        (ntohs(sh->hops[sh->current]) != my_address)) {
      sh->dispatch |= IP_EXT_SOURCE_INVAL;
      dbg("IPDispatch", "Invalidating source route!\n");
      return;
    } 
    if (sh->current == SH_NENTRIES(sh)) return;
    sh->hops[sh->current] = htons(prev_hop);
    sh->current++;
  }

#ifdef CENTRALIZED_ROUTING
  void print_rinstall(struct rinstall_header *rih) {
    uint8_t i;
    dbg("Install", "rinstall header:\n");
    dbg_clear("Install", "\tnxt_header\t0x%x\n", rih->ext.nxt_hdr);
    dbg_clear("Install", "\tlen\t0x%x\n", rih->ext.len);
    dbg_clear("Install", "\tflags\t0x%x\n", rih->flags);
    dbg_clear("Install", "\tmatch_src\t0x%x\n", ntohs(rih->match.src));
    dbg_clear("Install", "\tmatch_prev\t0x%x\n", ntohs(rih->match.prev_hop));
    dbg_clear("Install", "\tmatch_dest\t0x%x\n", ntohs(rih->match.dest));
    dbg_clear("Install", "\tpath_len\t0x%x\n", rih->path_len);
    dbg_clear("Install", "\tcurrent\t0x%x\n", rih->current);
    for(i = 0; i < rih->path_len; i++)
      dbg_clear("Install", "\thop[%u]\t0x%x\n", i, ntohs(rih->path[i]));
  }

  /*
   * Handles route install headers
   *
   * NOTE: We increment the current position BEFORE sending the message on
   *  which differs from the way we handle source routing headers, only to
   *  keep it clean for now.  This can be changed later.
   */
  error_t handleRouteInstall(struct rinstall_header *rih, bool isForMe) {
    struct split_ip_msg *ipmsg;
    struct rinstall_header *rih_new;
    struct generic_header *g_rih;
    struct source_header *sh;
    struct generic_header *g_sh;
    error_t result;
    uint8_t i;

    if (rih == NULL)
      return FAIL;

    // This is just put in here because we were getting weird fixes.
    //  Only a HACK, a better solution is need.
    //  XXX : SDH : this is probably because u_info->rih wasn't be
    //  initialized in unpackHeaders()
    if (rih->ext.len == 0) {
      dbg("Install", "install: Dropping 0 length rinstall packet!\n");
      return FAIL;
    }

    if (!isForMe && (rih->current == 0)) // Packet hasn't reached route install source yet
      return FAIL;

    dbg("Install", "handleRouteInstall being executed\n");
    print_rinstall(rih);

    // If these conditions aren't true, that means we're the origin
    //  of this route install, so we don't change current, which
    //  should point to our location along the path
    //if ((isForMe && (rih->current != 0)) || ((!(isForMe)) && (rih->current != 0)))
      //rih->current++;
   

 
    if ((call IPRouting.installFlowEntry(rih, isForMe)) != SUCCESS)
      return FAIL;

    rih->current++;
    
    //  If any of these conditions hold true, we need to take this
    //  rinstall header and forward it along the path it is for
    if ((isForMe && (rih->current == 1)) && 
        (IS_FULL_DST_INSTALL(rih) || IS_HOP_INSTALL(rih) || 
         IS_FULL_DST_UNINSTALL(rih) || IS_HOP_UNINSTALL(rih))) { 
      // Start of route install forwarding
      ipmsg = (struct split_ip_msg *)ip_malloc(sizeof(struct split_ip_msg) + 
                                               sizeof(struct rinstall_header) + 
                                               rih->path_len * sizeof(uint16_t) + 
                                               sizeof(struct generic_header) + 
                                               sizeof(struct source_header) + 
                                               (rih->path_len - 1) * sizeof(uint16_t)+ 
                                               sizeof(struct generic_header));
      
      dbg("Install", "handleRouteInstall needs to be forwarded!\n");

      if (ipmsg == NULL) return ERETRY;
      rih_new = (struct rinstall_header *)(ipmsg + 1);
      g_rih = (struct generic_header *)(((uint8_t *)(rih_new + 1)) + rih->path_len * sizeof(uint16_t));
      sh = (struct source_header *)(g_rih + 1);
      g_sh = (struct generic_header *)(((uint8_t *)(sh + 1)) + (rih->path_len - 1) * sizeof(uint16_t));

      ip_memclr((uint8_t *)&ipmsg->hdr, sizeof(struct ip6_hdr));
      ip_memclr((uint8_t *)rih_new, (sizeof(struct rinstall_header) + rih->path_len * sizeof(uint16_t)));
      ip_memclr((uint8_t *)sh, (sizeof(struct source_header) + (rih->path_len - 1) * sizeof(uint16_t)));
      
      call IPAddress.getIPAddr(&ipmsg->hdr.ip6_src);
      ip_memclr(ipmsg->hdr.ip6_dst.s6_addr, 16);
      memcpy(ipmsg->hdr.ip6_dst.s6_addr, ipmsg->hdr.ip6_src.s6_addr, 8);
      ipmsg->hdr.ip6_dst.s6_addr16[7] = rih->path[rih->path_len - 1];
       
      sh->len = sizeof(struct source_header) + (rih->path_len - 1) * sizeof(uint16_t);
      sh->current = 0;
      sh->dispatch = IP_EXT_SOURCE_DISPATCH;
      sh->nxt_hdr = NXTHDR_INSTALL;
      ipmsg->hdr.nxt_hdr = NXTHDR_SOURCE;
      g_sh->hdr.ext = (struct ip6_ext *)sh;
      g_sh->len = sh->len;
      g_sh->next = g_rih;
      ipmsg->headers = g_sh;

      for (i = 0; i < (rih->path_len - 1); i++) {
        ip_memcpy(&(sh->hops[i]), &(rih->path[i+1]), 2);
      }

      ip_memcpy(rih_new, rih, (sizeof(struct rinstall_header) + rih->path_len * sizeof(uint16_t)));

      g_rih->len = sizeof(struct rinstall_header) + rih->path_len * sizeof(uint16_t);
      g_rih->hdr.ext = (struct ip6_ext *)rih_new;
      g_rih->next = NULL;
      
      ipmsg->data_len = 0;
      ipmsg->data = (uint8_t *)(g_sh + 1);

      result = call IP.send[NXTHDR_SOURCE](ipmsg);
      ip_free(ipmsg);
      return result;
    }
    return SUCCESS;
  }
#endif 

  message_t *handle1stFrag(message_t *msg, packed_lowmsg_t *lowmsg) {
    uint8_t *unpack_buf;
    struct ip6_hdr *ip;

    uint16_t real_payload_length;// , real_offset = sizeof(struct ip6_hdr);

    unpack_info_t u_info;

    unpack_buf = ip_malloc(LIB6LOWPAN_MAX_LEN + LOWPAN_LINK_MTU);
    if (unpack_buf == NULL) return msg;

    // unpack all the compressed headers.  this means the IP headers,
    // and possibly also the UDP ones if there are no hop-by-hop
    // options.
    ip_memclr(unpack_buf, LIB6LOWPAN_MAX_LEN + LOWPAN_LINK_MTU);
    if (unpackHeaders(lowmsg, &u_info,
                      unpack_buf, LIB6LOWPAN_MAX_LEN) == NULL) {
      ip_free(unpack_buf);
      return msg;
    }
    
    ip = (struct ip6_hdr *)unpack_buf;

    // if rih is null (which should be the case if there is no
    // rinstall_header in the packet), this just returns
#ifdef CENTRALIZED_ROUTING
    handleRouteInstall(u_info.rih, call IPRouting.isForMe(ip));
#endif
    
    // first check if we forward or consume it
    if (call IPRouting.isForMe(ip)) {
      struct ip_metadata metadata;
      dbg("IPDispatch", "is for me!\n");
      // consume it:
      //   - get a buffer
      //   - if fragmented, wait for remaining fragments
      //   - if not, dispatch from here.

      metadata.sender = call Ieee154Packet.source(msg);
      metadata.lqi = call CC2420Packet.getLqi(msg);

      real_payload_length = ntohs(ip->plen);
      ip->plen = htons(ntohs(ip->plen) - u_info.payload_offset);
      switch (u_info.nxt_hdr) {
      case IANA_UDP:
        ip->plen = htons(ntohs(ip->plen) + sizeof(struct udp_hdr));
      }

      if (!hasFrag1Header(lowmsg)) {
        uint16_t amount_here = lowmsg->len - (u_info.payload_start - lowmsg->data);

        // we can fill in the data and deliver the packet from here.
        // this is the easy case...
        // we malloc'ed a bit extra in this case so we don't have to
        //  copy the IP header; we can just add the payload after the unpacked
        //  buffers.
        // if (rcv_buf == NULL) goto done;
        ip_memcpy(u_info.header_end, u_info.payload_start, amount_here);
        signal IP.recv[u_info.nxt_hdr](ip, u_info.transport_ptr, &metadata);
      } else {
        // in this case, we need to set up a reconstruction
        // structure so when the next packets come in, they can be
        // filled in.
        reconstruct_t *recon;
        uint16_t tag, amount_here = lowmsg->len - (u_info.payload_start - lowmsg->data);
        void *rcv_buf;

        if (getFragDgramTag(lowmsg, &tag)) goto fail;
        
        dbg("IPDispatch", "looking up frag tag: 0x%x\n", tag);
        recon = get_reconstruct(lowmsg->src, tag);
        
        // allocate a new struct for doing reassembly.
        if (recon == NULL) {
          goto fail;
        }
        
        // the total size of the IP packet
        rcv_buf = ip_malloc(real_payload_length + sizeof(struct ip6_hdr));

        recon->metadata.sender = lowmsg->src;
        recon->tag = tag;
        recon->size = real_payload_length + sizeof(struct ip6_hdr);
        recon->buf = rcv_buf;
        recon->nxt_hdr = u_info.nxt_hdr;
        recon->transport_hdr = ((uint8_t *)rcv_buf) + (u_info.transport_ptr - unpack_buf);
        recon->bytes_rcvd = u_info.payload_offset + amount_here + sizeof(struct ip6_hdr);
        recon->timeout = T_ACTIVE;

        if (rcv_buf == NULL) {
          // if we didn't get a buffer better not memcopy anything
          recon->timeout = T_FAILED1;
          recon->size = 0;
          goto fail;
        }
        if (amount_here > recon->size - sizeof(struct ip6_hdr)) {
          call Leds.led1Toggle();
          recon->timeout = T_FAILED1;
          recon->size = 0;
          ip_free(rcv_buf);
          recon->buf = NULL;
          goto fail;
        }

        ip_memcpy(rcv_buf, unpack_buf, u_info.payload_offset + sizeof(struct ip6_hdr));
        ip_memcpy(rcv_buf + u_info.payload_offset + sizeof(struct ip6_hdr), 
                  u_info.payload_start, amount_here);
        ip_memcpy(&recon->metadata, &metadata, sizeof(struct ip_metadata));

        goto done;
        // that's it, we just filled in the first piece of the fragment
      } 
    } else {
      // otherwise set up forwarding information for the next
      // fragments and enqueue this message_t on its merry way.
      send_info_t *s_info;
      send_entry_t *s_entry;
      forward_entry_t *fwd;
      message_t *msg_replacement;
      
      *u_info.hlim = *u_info.hlim - 1;
      if (*u_info.hlim == 0) {
        uint16_t amount_here = lowmsg->len - (u_info.payload_start - lowmsg->data);
        call ICMP.sendTimeExceeded(ip, &u_info, amount_here);
        // by bailing here and not setting up an entry in the
        // forwarding cache, following fragments will be dropped like
        // they should be.  we don't strictly follow the RFC that says
        // we should return at least 64 bytes of payload.
        ip_free(unpack_buf);
        return msg;
      }
      s_info = getSendInfo();
      s_entry = call SendEntryPool.get();
      msg_replacement = call FragPool.get();
      if (s_info == NULL || s_entry == NULL || msg_replacement == NULL) {
        if (s_info != NULL) 
          SENDINFO_DECR(s_info);
        if (s_entry != NULL)
          call SendEntryPool.put(s_entry);
        if (msg_replacement != NULL) 
          call FragPool.put(msg_replacement);
        goto fail;
      }

      if (ip->nxt_hdr == NXTHDR_SOURCE) {
        // this updates the source route in the message_t, if it
        // exists...
        updateSourceRoute(call Ieee154Packet.source(msg),
                          u_info.sh);
      }

      if (call IPRouting.getNextHop(ip, u_info.sh, lowmsg->src, &s_info->policy) != SUCCESS)
        goto fwd_fail;

      dbg("IPDispatch", "next hop is: 0x%x\n", s_info->policy.dest[0]);

      if (hasFrag1Header(lowmsg)) {
        fwd = table_search(&forward_cache, forward_unused);
        if (fwd == NULL) {
          goto fwd_fail;
        }

        fwd->timeout = T_ACTIVE;
        fwd->l2_src = call Ieee154Packet.source(msg);
        getFragDgramTag(lowmsg, &fwd->old_tag);
        fwd->new_tag = ++lib6lowpan_frag_tag;
        // forward table gets a reference
        SENDINFO_INCR(s_info);
        fwd->s_info = s_info;
        setFragDgramTag(lowmsg, lib6lowpan_frag_tag);
      } 

      // give a reference to the send_entry
      SENDINFO_INCR(s_info);
      s_entry->msg = msg;
      s_entry->info = s_info;

      if (call SendQueue.enqueue(s_entry) != SUCCESS)
        stats.encfail++;
      post sendTask();

      // s_info leaves lexical scope;
      SENDINFO_DECR(s_info);
      ip_free(unpack_buf);
      return msg_replacement;

    fwd_fail:
      call FragPool.put(msg_replacement);
      call SendInfoPool.put(s_info);
      call SendEntryPool.put(s_entry);
    }
    
   

  fail:
  done:
    ip_free(unpack_buf);
    return msg;
  }

  event message_t *Ieee154Receive.receive(message_t *msg, void *msg_payload, uint8_t len) {
    packed_lowmsg_t lowmsg;
    CHECK_NODE_ID msg;

    // set up the ip message structaddFragment
    lowmsg.data = msg_payload;
    lowmsg.len  = len;
    lowmsg.src  = call Ieee154Packet.source(msg);
    lowmsg.dst  = call Ieee154Packet.destination(msg);

    stats.rx_total++;

    call IPRouting.reportReception(call Ieee154Packet.source(msg),
                                   call CC2420Packet.getLqi(msg));

    lowmsg.headers = getHeaderBitmap(&lowmsg);
    if (lowmsg.headers == LOWPAN_NALP_PATTERN) {
      goto fail;
    }

    // consume it
    if (!hasFragNHeader(&(lowmsg))) {
      // in this case, we need to unpack the addressing information
      // and either dispatch the packet locally or forward it.
      msg = handle1stFrag(msg, &lowmsg);
      goto done;
    } else {
      // otherwise, it's a fragN packet, and we just need to copy it
      // into a buffer or forward it.
      forward_entry_t *fwd;
      reconstruct_t *recon;
      uint8_t offset_cmpr;
      uint16_t offset, amount_here, tag;
      uint8_t *payload;

      if (getFragDgramTag(&lowmsg, &tag)) goto fail;
      if (getFragDgramOffset(&lowmsg, &offset_cmpr)) goto fail;

      forward_lookup_tag = tag;
      forward_lookup_src = call Ieee154Packet.source(msg);

      fwd = table_search(&forward_cache, forward_lookup);
      payload = getLowpanPayload(&lowmsg);
      
      recon = get_reconstruct(lowmsg.src, tag);
      if (recon != NULL && recon->timeout > T_UNUSED && recon->buf != NULL) {
        // for packets we are reconstructing.
        
        offset =  (offset_cmpr * 8); 
        amount_here = lowmsg.len - (payload - lowmsg.data);
        
        if (offset + amount_here > recon->size) goto fail;
        ip_memcpy(recon->buf + offset, payload, amount_here);
        
        recon->bytes_rcvd += amount_here;
        
        if (recon->size == recon->bytes_rcvd) { 
          // signal and free the recon.
          signalDone(recon);
        }
      } else if (fwd != NULL && fwd->timeout > T_UNUSED) {
        // this only catches if we've forwarded all the past framents
        // successfully.
        message_t *replacement = call FragPool.get();
        send_entry_t *s_entry = call SendEntryPool.get();
        uint16_t lowpan_size;
        uint8_t lowpan_offset;

        if (replacement == NULL || s_entry == NULL) {
          // we have to drop the rest of the framents if we don't have
          // a buffer...
          if (replacement != NULL)
            call FragPool.put(replacement);
          if (s_entry != NULL)
            call SendEntryPool.put(s_entry);

          stats.fw_drop++;
          fwd->timeout = T_FAILED1;
          goto fail;
        }
        // keep a reference for ourself, and pass it off to the
        // send_entry_t
        SENDINFO_INCR(fwd->s_info);

        getFragDgramOffset(&lowmsg, &lowpan_offset);
        getFragDgramSize(&lowmsg, &lowpan_size);
        if ((lowpan_offset * 8) + (lowmsg.len - (payload - lowmsg.data)) == lowpan_size) {
          // this is the last fragment. since delivery is in-order,
          // we want to free up that forwarding table entry.
          // take back the reference the table had.
          SENDINFO_DECR(fwd->s_info);
          fwd->timeout = T_UNUSED;
        }

        setFragDgramTag(&lowmsg, fwd->new_tag);

        s_entry->msg = msg;
        s_entry->info = fwd->s_info;

        dbg("IPDispatch", "forwarding: dest: 0x%x\n", 
            fwd->s_info->policy.dest[s_entry->info->policy.current]);

        if (call SendQueue.enqueue(s_entry) != SUCCESS) {
          stats.encfail++;
          dbg("Drops", "drops: receive enqueue failed\n");
        }
        post sendTask();
        return replacement;

      } else goto fail;
      goto done;
    }

  fail:
    dbg("Drops", "drops: receive()\n");;
    stats.rx_drop++;
  done:
    return msg;
  }


  /*
   * Send-side functionality
   */

  task void sendTask() {
    send_entry_t *s_entry;
    if (radioBusy || state != S_RUNNING) return;
    if (call SendQueue.empty()) return;
    // this does not dequeue
    s_entry = call SendQueue.head();


    call Ieee154Packet.setDestination(s_entry->msg, 
                                      s_entry->info->policy.dest[s_entry->info->policy.current]);
    call PacketLink.setRetries(s_entry->msg, s_entry->info->policy.retries);
    call PacketLink.setRetryDelay(s_entry->msg, s_entry->info->policy.delay);
#ifdef LPL_SLEEP_INTERVAL
    call LowPowerListening.setRxSleepInterval(s_entry->msg, LPL_SLEEP_INTERVAL);
#endif

    dbg("IPDispatch", "sendTask dest: 0x%x len: 0x%x \n", call Ieee154Packet.destination(s_entry->msg),
        call Packet.payloadLength(s_entry->msg));
    
    if (s_entry->info->failed) {
      dbg("Drops", "drops: sendTask: dropping failed fragment\n");
      goto fail;
    }
          
    if ((call Ieee154Send.send(call Ieee154Packet.destination(s_entry->msg),
                               s_entry->msg,
                               call Packet.payloadLength(s_entry->msg))) != SUCCESS) {
      dbg("Drops", "drops: sendTask: send failed\n");
      goto fail;
    }
    radioBusy = TRUE;
    if (call SendQueue.empty()) return;
    // this does not dequeue
    s_entry = call SendQueue.head();

    return;
  fail:
    post sendTask();
    stats.tx_drop++;

    // deallocate the memory associated with this request.
    // other fragments associated with this packet will get dropped.
    s_entry->info->failed = TRUE;
    SENDINFO_DECR(s_entry->info);
    call FragPool.put(s_entry->msg);
    call SendEntryPool.put(s_entry);
    call SendQueue.dequeue();
  }
  

  /*
   * this interface is only for grownups; it is also only called for
   * local sends.
   *
   *  it will pack the message into the fragment pool and enqueue
   *  those fragments for sending
   *
   * it will set
   *  - payload length
   *  - version, traffic class and flow label
   *
   * the source and destination IP addresses must be set by higher
   * layers.
   */
  command error_t IP.send[uint8_t prot](struct split_ip_msg *msg) {
    uint16_t payload_length;

    if (state != S_RUNNING) {
      return EOFF;
    }

    if (msg->hdr.hlim != 0xff)
      msg->hdr.hlim = call IPRouting.getHopLimit();

    msg->hdr.nxt_hdr = prot;
    ip_memclr(msg->hdr.vlfc, 4);
    msg->hdr.vlfc[0] = IPV6_VERSION << 4;

    call IPRouting.insertRoutingHeaders(msg);
                             
    payload_length = msg->data_len;

    {
      struct generic_header *cur = msg->headers;
      while (cur != NULL) {
        payload_length += cur->len;
        cur = cur->next;
      }
    }

    msg->hdr.plen = htons(payload_length);
    
    // okay, so we ought to have a fully setup chain of headers here,
    // so we ought to be able to compress everything into fragments.
    //

    {
      send_info_t  *s_info;
      send_entry_t *s_entry;
      uint8_t frag_len = 1;
      message_t *outgoing;
      fragment_t progress;
      struct source_header *sh;
      progress.offset = 0;

      s_info = getSendInfo();
      if (s_info == NULL) return ERETRY;

      // fill in destination information on outgoing fragments.
      sh = (msg->headers != NULL) ? (struct source_header *)msg->headers->hdr.ext : NULL;
      if (call IPRouting.getNextHop(&msg->hdr, sh, 0x0,
                                    &s_info->policy) != SUCCESS) {
        dbg("Drops", "drops: IP send: getNextHop failed\n");
        goto done;
      }

#ifdef DBG_TRACK_FLOWS
      dbg_flowid++;
#endif

      //goto done;
      while (frag_len > 0) {
        s_entry  = call SendEntryPool.get();
        outgoing = call FragPool.get();

        if (s_entry == NULL || outgoing == NULL) {
          if (s_entry != NULL)
            call SendEntryPool.put(s_entry);
          if (outgoing != NULL)
            call FragPool.put(outgoing);
          // this will cause any fragments we have already enqueued to
          // be dropped by the send task.
          s_info->failed = TRUE;
          dbg("Drops", "drops: IP send: no fragments\n");
          goto done;
        }

#ifdef DBG_TRACK_FLOWS
        (call getFlowID(outgoing))->src = TOS_NODE_ID;
        (call getFlowID(outgoing))->dst = msg->hdr.ip6_dst.s6_addr16[7];
        (call getFlowID(outgoing))->id = dbg_flowid;
        (call getFlowID(outgoing))->seq = 0;
        (call getFlowID(outgoing))->nxt_hdr = prot;
#endif

        frag_len = getNextFrag(msg, &progress, 
                               call Packet.getPayload(outgoing, call Packet.maxPayloadLength()),
                               call Packet.maxPayloadLength());
        if (frag_len == 0) {
          call FragPool.put(outgoing);
          call SendEntryPool.put(s_entry);
          goto done;
        }
        call Packet.setPayloadLength(outgoing, frag_len);

        s_entry->msg = outgoing;
        s_entry->info = s_info;

        if (call SendQueue.enqueue(s_entry) != SUCCESS) {
          stats.encfail++;
          dbg("Drops", "drops: IP send: enqueue failed\n");
          goto done;
        }

        SENDINFO_INCR(s_info);
        printfUART("enqueue len 0x%x dest: 0x%x retries: 0x%x delay: 0x%x\n",frag_len,
                   s_info->policy.dest, s_info->policy.retries, s_info->policy.delay);
      }
    done:
      SENDINFO_DECR(s_info);
      post sendTask();
      return SUCCESS;
      
    }
  }

  event void Ieee154Send.sendDone(message_t *msg, error_t error) {
    send_entry_t *s_entry = call SendQueue.head();
    CHECK_NODE_ID;

    radioBusy = FALSE;

    if (state == S_STOPPING) {
      call RadioControl.stop();
      state = S_STOPPED;
      goto fail;
    }


    if (!call PacketLink.wasDelivered(msg)) {

      // if we haven't sent out any fragments yet, we can try rerouting
      if (s_entry->info->frags_sent == 0) {
        // SDH : TODO : if sending a fragment fails, abandon the rest of
        // the fragments
        s_entry->info->policy.current++;
        if (s_entry->info->policy.current < s_entry->info->policy.nchoices) {
          // this is the retry case; we don't need to change anything.
          post sendTask();
          return;
        }
        // no more next hops to try, so free the buffers and move on
      }    
      // a fragment failed, and it wasn't the first.  we drop all
      // remaining fragments.
      goto fail;
    } else {
      // the fragment was successfully sent.
      s_entry->info->frags_sent++;
      goto done;
    }
    goto done;
    
  fail:
    s_entry->info->failed = TRUE;
    if (s_entry->info->policy.dest[0] != 0xffff)
      dbg("Drops", "drops: sendDone: frag was not delivered\n");

  done:
    s_entry->info->policy.actRetries = call PacketLink.getRetries(msg);
    call IPRouting.reportTransmission(&s_entry->info->policy);
    // kill off any pending fragments
    SENDINFO_DECR(s_entry->info);
    call FragPool.put(s_entry->msg);
    call SendEntryPool.put(s_entry);
    call SendQueue.dequeue();

    post sendTask();
  }



  event void ICMP.solicitationDone() {

  }

  /*
   * Statistics interface
   */
  command void Statistics.get(ip_statistics_t *statistics) {
    stats.fragpool = call FragPool.size();
    stats.sendinfo = call SendInfoPool.size();
    stats.sendentry= call SendEntryPool.size();
    stats.sndqueue = call SendQueue.size();
    stats.heapfree = ip_malloc_freespace();
    ip_memcpy(statistics, &stats, sizeof(ip_statistics_t));
  }

  command void Statistics.clear() {
    ip_memclr((uint8_t *)&stats, sizeof(ip_statistics_t));
  }

  default event void IP.recv[uint8_t nxt_hdr](struct ip6_hdr *iph,
                                              void *payload,
                                              struct ip_metadata *meta) {
  }
}