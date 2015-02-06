#!/usr/bin/env python

import sys, os, time
import getopt
import subprocess
import logging, logging.handlers

## @class AutoDoc
#  @brief Generates documentation for new tags in a Git repository
#
#  @todo Actually generate Doxygen documentation
#  @todo Move documentation in place
class AutoDoc(object):

  ## Constructor.
  #
  #  @param git_clone Full path to the Git clone to consider
  #  @param output_path Directory containing one subdirectory per documentation version
  #  @param debug True enables debug output, False suppresses it
  def __init__(self, git_clone, output_path, debug):
    self._git_clone = git_clone
    self._output_path = output_path
    self._log = None

    self._init_log(debug)

  ## Initializes the logging facility.
  #
  #  @param debug True enables debug output, False suppresses it
  def _init_log(self, debug):

    self._log = logging.getLogger('AutoDoc')
    log_formatter = logging.Formatter('AutoDoc[%d]: %%(levelname)s: %%(message)s' % os.getpid())

    stderr_handler = logging.StreamHandler(stream=sys.stderr)
    stderr_handler.setFormatter(log_formatter)
    self._log.addHandler(stderr_handler)

    syslog_handler = self._get_syslog_handler()
    syslog_handler.setFormatter(log_formatter)
    self._log.addHandler(syslog_handler)

    if debug:
      self._log.setLevel(logging.DEBUG)
    else:
      self._log.setLevel(logging.INFO)


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


  ## Get list of tags from the current Git repository.
  #
  #  @return A list of tags, or None in case of error
  def get_tags(self):

    cmd = [ 'git', 'tag' ]

    self._log.debug('Getting list of tags')

    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=subprocess.PIPE, shell=False, \
        cwd=self._git_clone)

    tags = []
    for line in iter(sp.stdout.readline, ''):
      line = line.strip()
      tags.append(line)

    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success getting list of tags')
      return tags

    self._log.error('Error getting list of tags, returned %d' % rc)
    return None


  ## Updates remote repository
  #
  #  @return True on success, False on error
  def update_repo(self):

    self._log.debug('Updating repository')

    cmd = [ 'git', 'remote', 'update', '--prune' ]

    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)

    rc = sp.wait()

    if rc == 0:
      self._log.debug('Success updating repository')
      return True

    self._log.error('Error updating repository, returned %d' % rc)
    return False


  ## Demo mode: remove a couple of tags to see the difference
  def demo(self):
    for tag in [ 'vAN-20150118', 'vAN-20150115', 'vAN-20150117' ]:
      cmd = [ 'git', 'tag', '--delete', tag ]
      with open(os.devnull, 'w') as dev_null:
        sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)
      rc = sp.wait()
      if rc != 0:
        logging.error('Problem removing %s: %d' % (tag, rc))

  ## Entry point for all operations.
  #
  #  @return 0 on success, nonzero on error
  def run(self):

    # Just for debug: demo() will disappear
    self.demo()

    tags_before = self.get_tags()
    if tags_before is None:
      self._log.fatal('Cannot get tags before updating: check and repair your repository')
      return 1

    # This operation needs to be repeated several times in case of failures
    update_success = False
    failure_count = 0
    failure_threshold = 3
    retry_pause_s = 3
    while True:
      update_success = self.update_repo()
      if update_success == False:
        failure_count = failure_count + 1
        if failure_count == failure_threshold:
          break
        else:
          # Take a breath before trying again
          self._log.debug('Waiting %d seconds before performing update attempt %d/%d' % \
            (retry_pause_s, failure_count+1, failure_threshold))
          time.sleep(retry_pause_s)
      else:
        break

    if update_success == False:
      self._log.fatal('Cannot update after %d attempts: check Git remote and connectivity' % \
        failure_threshold)
      return 1

    tags_after = self.get_tags()
    if tags_after is None:
      self._log.fatal('Cannot get tags after updating: check and repair your repository')
      return 1

    #
    # If we are here, everything is fine
    #

    tags_new = []

    for tag in tags_after:
      if not tag in tags_before:
        tags_new.append(tag)

    if len(tags_new) == 0:
      self._log.info('No new tags')
    else:
      self._log.info('New tags found: %s' % ' '.join(tags_new))

    # Generate doc, check exitcode, move to location, notify via email

    return 0


# Entry point
if __name__ == '__main__':

  params = {
    'git-clone': None,
    'output-path': None,
    'debug': False
  }

  opts, args = getopt.getopt(sys.argv[1:], '', [ 'git-clone=', 'output-path=', 'debug' ])
  for o, a in opts:
    if o == '--git-clone':
      params['git-clone'] = a
    elif o == '--output-path':
      params['output-path'] = a
    elif o == '--debug':
      params['debug'] = True
    else:
      raise getopt.GetoptError('unknown parameter: %s' % o)

  for p in params:
    if params[p] is None:
     raise getopt.GetoptError('mandatory parameter missing: %s' % p)

  autodoc = AutoDoc(
    git_clone=params['git-clone'],
    output_path=params['output-path'],
    debug=params['debug']
  )
  r = autodoc.run()
  sys.exit(r)
