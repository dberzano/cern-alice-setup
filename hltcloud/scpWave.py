#!/usr/bin/env python
'''
scpWave.py - binary tree distribution of files to hosts on a cluster using
             scp utility.

===============
The MIT License

Copyright (c) 2010 Clemson University

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
'''

# SUMMARY
#  Transfer a file to multiple hosts via scp utility
#
#  The script begins by using the current machine to transfer a file to a host.
#  Once this transfer is done, both the current machine and the host which
#  received the file are used to send the same file to the next target hosts in
#  the target queue. This continues to spread, adding more seeders until all
#  targets have received the file (and thus become seeders themselves).
#
#
# USAGE
# ./scpWave.py <file> <file destination>
#
#   Required Options - must specify a target host
#     -l '<host1> <host2> <host3> ...'  # list the target hosts, quote multiples
#     and/or
#     -f <host file>                    # specify '\n' separated host file
#     and/or
#     -r '<basehost[a-b,c-d,...]>'      # eg. host[1-2,4-4] -> host1, host2, host4
#
#    So, you can list hosts on the command line with -l or put them in a file
#    separated by '\n' characters. You can also specify a range of hosts with -r.
#    All three options: -l, -r, and -f may be used together. It is important to
#    note that for the -l option, multiple hosts must be quoted.
#
#    Other options
#     -s Writes transfer statistics to a log file
#     -u Specify a username to use for the transfers
#     -v Enable verbose output
#
# LOGGING
#  After each run, the results are written to "transfers.log" as comma separated
#   values. This is the format:
#   time, active seeds, transfers
#   where time is the elapsed time to transfer "transfers" files.
#   Use -s switch to turn on logging
#
# COMMAND - the command this script will use to transfer files
#  For better performance, try '-c blowfish'
#  Fill CMD_TEMPLATE with the seeder and target host data from seedq and targetq.
#    CMD_TEMPLATE = "ssh -o StrictHostKeyChecking=no user@host1 scp -o\
#    StrictHostKeyChecking=no/file user@host2:/file"
#
#    CMD_TEMPLATE = "ssh -o StrictHostKeyChecking=no seeder[0] scp -o\
#    StrictHostKeyChecking=no seeder[1] target[0]:target[1]"
#
# ISSUES
#  1. ctrl-c behavior. 
#     A thread will continue to try transferring after ctrl-c
#     setting max_transfer_attempts to 1 seems to work
#
# TODO
#  1. try 'ssh <host> exit' if transfer fails to see if host is up   
#  2. 'received by: n hosts' doesn't print right at end
#

import Queue
import sys
import os
import threading
import time
import thread
import getopt
import re
from socket import gethostname
from subprocess import Popen, PIPE, call

### Global data ########################

# turn transfer logging on or off using -s switch
LOGGING_ENABLED = False
LOG_FILE = "scpWave.log"

# maximum number of concurrent transfers
THREAD_MAX = 250

# maximum attempts to try and transfer the file to a host
MAX_TRANSFER_ATTEMPTS = 3

# if enabled, will print result of each transfer. enable with -v switch
VERBOSE_OUTPUT_ENABLED = False

# each seeder thread will fill this in with the proper host data
CMD_TEMPLATE = "ssh -o StrictHostKeyChecking=no %s scp -o\
StrictHostKeyChecking=no %s %s:%s"

### End global data ########################

def _usage():
    print '''\
usage: scpWave.py <file> <filedest> [-f <hostfile>] \
[-l '<host1> <host2> ...'] [-r 'basehost[0-1,4-6,...]']'''


# mimics python2.5+ Queue
class TargetQueue(Queue.Queue):
    def __init__(self):
        Queue.Queue.__init__(self)
        self.count = 0
        self.lock = threading.Lock()
        self.done = threading.Event()

    def join(self):
        self.done.wait()
        
    def put(self, obj):
        self.lock.acquire()
        self.count += 1
        Queue.Queue.put(self, obj)
        self.lock.release()

    def task_done(self):
        self.lock.acquire()
        self.count -= 1
        if self.count <= 0:
            self.done.set()
        self.lock.release()


class TimeQueue(Queue.Queue):
    ''' contains timing data. Holds entrees of the form:
    elapsed time, active seeds, transfers complete '''

    def __init__(self, starttime):
        Queue.Queue.__init__(self)
        self.starttime = starttime
        self.count = 0
        self.lock = threading.Lock()

    def put(self, activeSeeds):
        self.lock.acquire()
        self.count += 1
        etime = time.time() - self.starttime
        # format: elapsed time, active seeders, files transferred
        Queue.Queue.put(self, "%2.2f, %2d, %2d" %\
                        (etime, activeSeeds, self.count))
        self.lock.release()


class Seeder(threading.Thread):
    ''' sends file to a single host '''

    def __init__(self, target, targetq, seeder, seedq, seeder_threads, sema,\
                 timeq, maxTransferAttempts=MAX_TRANSFER_ATTEMPTS, 
                 cmd_template=CMD_TEMPLATE):
        threading.Thread.__init__(self)
        self.seeder = seeder
        self.seedq = seedq
        self.target = target
        self.targetq = targetq
        self.seeder_threads = seeder_threads
        self.sema = sema
        self.timeq = timeq
        self.maxTransferAttempts = maxTransferAttempts        
        self.cmd_template = cmd_template

    def run(self):
        '''
        instead of maxTransferAttempts, try to ssh to target and seed, see
        which is the problem.
        '''
        for attempts in range(self.maxTransferAttempts):
            self.command = self.cmd_template % (self.seeder[0], self.seeder[1],
                                                self.target[0], self.target[1])
            ret = self.sendFile()
            self.seedq.put(self.seeder) # reuse seeder

            if ret:
                break # success, or halt request (ctrl-c)
            elif attempts < self.maxTransferAttempts:
                self.seeder = self.seedq.get(block=True) # try a different seed

        self.seeder_threads.remove(self) # remove from active threads
        self.targetq.task_done() # transfer still may not have succeeded
        self.sema.release()
            
    def sendFile(self):
        ''' return True on success, False on failure.'''
        info = "%s:%s -> %s:%s... " %\
               (self.seeder[0], self.seeder[1], self.target[0], self.target[1])
        stderr = None
        try:
            proc = Popen(self.command, shell=True, stdout=PIPE,\
                         stdin=PIPE, stderr=PIPE)
            stdout, stderr = proc.communicate()
            ret = proc.wait()

            if ret == 0:
                # success
                print info + 'success'
                self.seedq.put(self.target) # use target as a seeder
                self.timeq.put(len(self.seeder_threads))
                return True
            else:
                # same as below, dont raise
                print info + ' failed'
                print stderr
                return False
        except Exception:
            # put back on queue to try again.
            print 'Popen error'
            print info + ' failed'
            if stderr: print stderr
            return False


def isAlive(host, cmd='ssh -o StrictHostKeyChecking=no %s exit'):
    ''' check if host is accepting ssh connections '''
    p = Popen(cmd % host, shell=True)
    ret = p.wait()
    return not ret


def startTransfers(seedq, targetq, timeq, filepath, filedest, username):
    ''' called from main(), creates threads to do the file transfers.
    seedq takes a tuple of ([user@]host, filepath)
    add first machine to seedq '''
    if username:
        seedq.put(("%s@%s" % (username, gethostname()), filepath))
    else:
        seedq.put((gethostname(), filepath))
        
    # initialize thread list
    seeder_threads = []

    # limits number of threads to THREAD_MAX
    sema = threading.BoundedSemaphore(THREAD_MAX)

    # dispatch work while targets remain on the queue
    while True:
        try:
            target = targetq.get_nowait()
        except Exception:
            break # final transfers in progress

        # don't start thread until a seed is available
        sema.acquire()
        seeder = seedq.get(block=True)
        try:
            seederThread = Seeder(target, targetq, seeder, seedq, seeder_threads,\
                                  sema, timeq)
            seeder_threads.append(seederThread)
            seederThread.start()
        except Exception:
            print "ERROR: Thread creation failed. Trying again in 5s\n",\
                  sys.exc_info()[1]
            sema.release()
            targetq.put(target)
            seedq.put(seeder)
            time.sleep(5.0)
            
    # wait for all targets to receive the file
    while seeder_threads != []:
        time.sleep(0.5)


def main(logfile=LOG_FILE, logging_enabled=LOGGING_ENABLED, username=None):
    global VERBOSE_OUTPUT_ENABLED
    # seedq holds addresses of machines containing the file
    # Each element is a tuple of the form ([user@]host, file)
    seedq = Queue.Queue()

    # targetq holds addresses of machines that need the file
    # Each element is a tuple of the form ([user@]host, filedest)
    targetq = TargetQueue()

    # You can use -u to specify a username
    try:
        optlist, args = getopt.gnu_getopt(sys.argv[1:], "u:f:r:l:sv")
    except:
        print "ERROR: ", sys.exc_info()[1]
        sys.exit(1)

    if len(args) < 2:
        print "ERROR: Must specify a file and a file destination"
        _usage()
        sys.exit(1)

    # get name of file to transfer
    try:
        filename = args[0]
        filepath = os.path.realpath(filename)
        filedest = args[1]
    except:
        _usage()
        sys.exit(1)

    if not os.path.isfile(filepath):
        print "ERROR: '%s' not found" % filepath
        sys.exit(1)

    # 3 ways to populate the targetq
    targetList = [] # temporarily holds target hosts
    for opt, arg in optlist:
        if opt == '-f': # file
            # read '\n' separated hosts from file
            try:
                FILE = open(arg, "r")
            except:
                print "ERROR: Failed to open hosts file:", arg
                sys.exit(0)
            for host in FILE.readlines():
                targetList.append((host.split("\n")[0].strip(), filedest))
            FILE.close()
        elif opt == '-r': # range. modify to work with letters and not just ints
            try:
                # format: -r <base_hostname><[0-1,3-3,5-11...]>
                # eg. -r host[1-2,4-6] generates host1, host2, host4, host5, host6
                basehost = arg.split("[")[0]
                # get 3 part ranges eg: ["1-3","5-5"]
                ranges = arg.split("[")[1].strip("[]").split(",")
                splitRanges = []
                for rng in ranges:
                    first = rng.split("-")[0]
                    last = rng.split("-")[1]
                    splitRanges.append((first, last))
            
                for first, last in splitRanges:
                    for num in range(int(first), int(last)+1):
                        leadingZeros = len(first) - len(str(num))
                        host = basehost + "0"*leadingZeros + str(num)
                        targetList.append((host, filedest))
            except:
                print "ERROR: Invalid argument for -r:", arg
                print sys.exc_info()[1]
                sys.exit(1)
        elif opt == '-l': # list
            # quote multiple hosts
            # read list of hosts from stdin
            hostlist = arg.split()
            for host in hostlist:
                targetList.append((host.strip(), filedest))
        elif opt == '-u': # username
            username = arg
        elif opt == '-s': # log transfer statistics
            logging_enabled = True
        elif opt == '-v': # verbose output
            VERBOSE_OUTPUT_ENABLED = True

    # remove duplicate targets and add them to targetq
    targetList = set(targetList)
    for target in targetList:
        if username: # add username to scp call
            target = (username + '@' + target[0], target[1])
        targetq.put(target)
        
    # ensure there are target hosts in the queue
    if targetq.qsize() < 1:
        print "There are no targets in the queue"
        _usage()
        sys.exit(1)
        
    # ready to start the transfers
    print "transferring %s to %d host(s)..." % (filename, targetq.qsize())
    start_time = time.time()

    # see TimeQueue definition above for more info
    timeq = TimeQueue(start_time)

    # returns when all transfers are complete or exception
    startTransfers(seedq, targetq, timeq, filepath, filedest, username)

    # transfers are complete, print out the stats
    elapsed_time = time.time() - start_time
    file_size = os.path.getsize(filepath) / (10**6) # file size in MB

    # received by is not accurate ...
    #print 'received by: %d hosts' % (seedq.qsize()-1)
    print 'file size: %dMB' % file_size
    print 'elapsed time: %.2fs' % elapsed_time

    # create log file
    # use -s switch to turn on or off
    if logging_enabled:
        header = time.ctime() + "\n"
        if not os.path.exists(logfile):
            header = "Columns: [Elapsed Time(s)] [Active Seeds] " +\
            "[Files Transferred]\n\n" + header
        logfile = open(logfile, "a")
        logfile.write(header)
        while timeq.qsize() > 0:
            string = timeq.get()
            logfile.write(string+"\n")
        logfile.write("\n\n")
        logfile.close()

if __name__ == "__main__":
    main()
