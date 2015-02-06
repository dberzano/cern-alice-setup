#!/usr/bin/env python

import sys, os
import getopt
import subprocess
import logging, logging.handlers

class AutoDoc(object):

  ## Constructor.
  #
  #  @param git_clone Full path to the Git clone to consider
  #  @param output_path Directory containing one subdirectory per documentation version
  def __init__(self, git_clone, output_path):
    self._git_clone = git_clone
    self._output_path = output_path
    self._log = None

    self._init_log()

  ## Initializes the logging facility.
  def _init_log(self):

    self._log = logging.getLogger('AutoDoc')
    log_formatter = logging.Formatter('AutoDoc[%d]: %%(levelname)s: %%(message)s' % os.getpid())

    stderr_handler = logging.StreamHandler(stream=sys.stderr)
    stderr_handler.setFormatter(log_formatter)
    self._log.addHandler(stderr_handler)

    syslog_handler = self._get_syslog_handler()
    syslog_handler.setFormatter(log_formatter)
    self._log.addHandler(syslog_handler)

    self._log.setLevel(logging.DEBUG)


  ## Gets an appropriate syslog handler for the current operating system.
  #
  #  @return A SysLogHandler, or None on error
  def _get_syslog_handler(self):
    syslog_address = None
    for a in [ '/var/run/syslog', '/dev/log' ]:
      if os.path.exists(a):
        syslog_address = a
        break

    if syslog_address:
      syslog_handler = logging.handlers.SysLogHandler(address=syslog_address)
      return syslog_handler

    return None


  ## Entry point of all operations.
  def run(self):
    self._log.info('Welcome to ALICE')
    return 0


# Entry point
if __name__ == '__main__':

  params = {
    'git-clone': None,
    'output-path': None
  }

  opts, args = getopt.getopt(sys.argv[1:], '', [ 'git-clone=', 'output-path=' ])
  for o, a in opts:
    if o == '--git-clone':
      params['git-clone'] = a
    elif o == '--output-path':
      params['output-path'] = a
    else:
      raise getopt.GetoptError('unknown parameter: %s' % o)

  for p in params:
    if params[p] is None:
     raise getopt.GetoptError('mandatory parameter missing: %s' % p)

  autodoc = AutoDoc(
    git_clone=params['git-clone'],
    output_path=params['output-path']
  )
  r = autodoc.run()
  sys.exit(r)
