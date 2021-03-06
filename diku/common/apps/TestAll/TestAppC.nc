
/*
 * Copyright (c) 2007 University of Copenhagen
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of University of Copenhagen nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE UNIVERSITY
 * OF COPENHAGEN OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 *
 * @author Martin Leopold <leopold@diku.dk>
 * @author Marcus Chang <marcus@diku.dk>
 */


configuration TestAppC {

}
implementation {
    components MainC, TestAppP;

    MainC.SoftwareInit -> TestAppP.Init;
    MainC.Boot <- TestAppP;

    components LedsC;
    TestAppP.Leds -> LedsC;

    components StdOutC;
    TestAppP.StdOut -> StdOutC;

    /* *** */   
    components SimpleMacC;
    TestAppP.SimpleMacControl -> SimpleMacC.StdControl;
    TestAppP.SimpleMac -> SimpleMacC.SimpleMac;

    /* *** */   
    components HalFlashC;
    TestAppP.HalFlash -> HalFlashC;

    /* *** */   
#ifdef __cc2430em__  
    components new AdcC();
    TestAppP.Read -> AdcC;
    TestAppP.AdcControl -> AdcC;
#elif __micro4__
    components new Msp430InternalTemperatureC();
    TestAppP.Read -> Msp430InternalTemperatureC;
#endif

}

