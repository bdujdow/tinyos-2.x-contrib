#!/usr/bin/python

import imaplib;
import pickle;
import sys;
search = '(UNSEEN)'

#command-line arguments to change search criteria
try:
	if sys.argv[1] == 'new':
		search = '(UNSEEN)'
		print 'using: \'(UNSEEN)\''
	elif sys.argv[1] == 'old':
		search = '(SEEN)'
		print 'using: \'(SEEN)\''
	elif sys.argv[1] == 'all':
		search = '(ALL)'
		print 'using: ALL'
except:
	print 'using default: UNSEEN'





		tempTime = conn.fetch(num, '(BODY[HEADER.FIELDS (DATE)])')
		baseID = conn.fetch(num, '(BODY[HEADER.FIELDS (SUBJECT)])')
		conn.store(num,'+FLAGS','\\SEEN')#Marks the message as read
	

try:
