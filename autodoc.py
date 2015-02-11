#!/usr/bin/env python

import sys, os, time
import getopt
import subprocess
import tempfile
import shutil
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
  #  @param new_tags If True, generate doc for new tags; if False, see branch
  #  @param branch If new_tags is False, generates doc for this branch's head
  #  @param build_path Uses the given path as CMake and Doxygen cache, instead of a disposable one
  def __init__(self, git_clone, output_path, debug, new_tags, branch, build_path):
    self._git_clone = git_clone
    self._output_path = output_path
    self._log = None
    self._new_tags = new_tags
    self._branch = branch
    self._build_path = build_path

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


  ## Updates remote repository.
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


  ## Updates current branch from remote.
  #
  #  Note that the branch must be properly checked out otherwise.
  #
  #  @return True on success, False on error
  def update_branch(self):

    self._log.debug('Updating current branch')

    cmd = [ 'git', 'pull', '--rebase' ]

    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)

    rc = sp.wait()

    if rc == 0:
      self._log.debug('Success updating branch')
      return True

    self._log.error('Error updating branch, returned %d' % rc)
    return False


  ## Checks out a Git reference, but cleans up first.
  #
  #  @param ref A Git reference (tag, branch...) to check out
  #
  #  @return True on success, False on error
  def checkout_ref(self, ref):

    self._log.debug('Resetting current working directory')
    cmd = [ 'git', 'reset', '--hard', 'HEAD' ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)
    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success resetting current working directory')
    else:
      self._log.error('Error resetting current working directory, returned %d' % rc)
      return False

    self._log.debug('Cleaning up working directory')
    cmd = [ 'git', 'clean', '-f', '-d' ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)
    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success cleaning up working directory')
    else:
      self._log.error('Error cleaning up working directory, returned %d' % rc)
      return False

    self._log.debug('Checking out reference %s' % ref)
    cmd = [ 'git', 'checkout', ref ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)
    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success checking out reference %s' % ref)
    else:
      self._log.error('Error checking out reference %s, returned %d' % (ref, rc))
      return False

    return True


  ## Creates Doxygen documentation.
  #
  #  @return True on success, False on error
  def gen_doc(self):

    if not self.checkout_ref(self._branch):
      return False

    build_path = self._build_path

    if build_path is None:
      self._log.debug('Creating a temporary build directory')
      build_path = tempfile.mkdtemp()
      dispose_build_path = True
    else:
      dispose_build_path = False
      if not os.path.isdir(build_path):
        os.makedirs(build_path)

    self._log.debug('Build directory: %s' % build_path)

    self._log.debug('Preparing build with CMake')
    cmd = [ 'cmake', self._git_clone, '-DDOXYGEN_ONLY=ON' ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=build_path)
    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success preparing build with CMake')
    else:
      self._log.error('Error preparing build with CMake, returned %d' % rc)
      return False

    self._log.debug('Generating documentation (will take a while)')
    cmd = [ 'make', 'doxygen' ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=build_path)
    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success generating documentation')
    else:
      self._log.error('Error generating documentation, returned %d' % rc)
      return False

    # Let it except freely on error
    self._log.debug('Creating output directory')
    if not os.path.isdir(self._output_path):
      os.makedirs(self._output_path)

    self._log.debug('Publishing documentation to %s' % self._output_path)
    cmd = [ 'rsync', '-a', '--delete',
      '%s/doxygen/html/' % build_path,
      '%s/%s/' % (self._output_path, self._branch) ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=build_path)
    rc = sp.wait()
    if rc == 0:
      self._log.debug('Success publishing documentation to %s' % self._output_path)
    else:
      self._log.error('Error publishing documentation to %s, returned %d' % (self._output_path, rc))
      return False

    # Clean up working directory
    if dispose_build_path:
      self._log.debug('Cleaning up working directory %s' % build_path)
      shutil.rmtree(build_path)

    # All went right
    return True


  ## Demo mode: remove a couple of tags to see the difference, and revert the
  #  repository back to the past to see if pull works.
  def demo(self):
    for tag in [ 'vAN-20150118', 'vAN-20150115', 'vAN-20150117', 'v5-06-02', 'v5-06-03' ]:
      cmd = [ 'git', 'tag', '--delete', tag ]
      with open(os.devnull, 'w') as dev_null:
        sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)
      rc = sp.wait()
      if rc != 0:
        logging.error('Problem removing %s: %d' % (tag, rc))

    sha1 = 'a9eacf03772d8587d41641e6849632ce25e474b3'
    cmd = [ 'git', 'reset', '--hard', sha1 ]
    with open(os.devnull, 'w') as dev_null:
      sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=self._git_clone)
    rc = sp.wait()
    if rc != 0:
      logging.error('Problem resetting repo: %d' % (rc))


  ## Generate documentation for new tags found.
  #
  #  @return False on failure, True on success
  #
  #  @todo Remove debug code
  def gen_doc_new_tags(self):

    # Just for debug: demo() will disappear
    self.demo()

    tags_before = self.get_tags()
    if tags_before is None:
      self._log.fatal('Cannot get tags before updating: check and repair your repository')
      return False

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
      return False

    tags_after = self.get_tags()
    if tags_after is None:
      self._log.fatal('Cannot get tags after updating: check and repair your repository')
      return False

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

    return True


  ## Generate documentation for the current branch's head, which is updated
  #  first.
  #
  #  @return False on failure, True on success
  def gen_doc_head(self):

    # Just for debug: demo() will disappear
    self.demo()

    # This operation needs to be repeated several times in case of failures
    update_success = False
    failure_count = 0
    failure_threshold = 3
    retry_pause_s = 3
    while True:
      update_success = self.update_branch()
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
      return False

    #
    # If we are here, everything is fine
    #

    # Generate doc, check exitcode, move to location, notify via email
    self.gen_doc()

    return True


  ## Entry point for all operations.
  #
  #  @return 0 on success, nonzero on error
  def run(self):

    if self._new_tags:
      r = self.gen_doc_new_tags()
    else:
      r = self.gen_doc_head()

    if r == True:
      return 0
    return 1


# Entry point
if __name__ == '__main__':

  params = {
    'git-clone': None,
    'output-path': None,
    'debug': False,
    'branch': None,
    'new-tags': None,
    'build-path': None
  }

  opts, args = getopt.getopt(sys.argv[1:], '',
    [ 'git-clone=', 'output-path=', 'debug', 'branch=', 'new-tags', 'build-path=' ])
  for o, a in opts:
    if o == '--git-clone':
      params['git-clone'] = a
    elif o == '--output-path':
      params['output-path'] = a
    elif o == '--debug':
      params['debug'] = True
    elif o == '--branch':
      params['new-tags'] = False
      params['branch'] = a

    elif o == '--new-tags':
      if params['new-tags'] == False:
        raise getopt.GetoptError('use either --new-tags or --head')
      params['new-tags'] = True
      params['branch'] = False
      params['build-path'] = False

    elif o == '--head':
      if params['new-tags'] == True:
        raise getopt.GetoptError('use either --new-tags or --head')
      params['new-tags'] = False

    elif o == '--build-path':
      params['build-path'] = a

    else:
      raise getopt.GetoptError('unknown parameter: %s' % o)

  for p in params:
    if params[p] is None:
     raise getopt.GetoptError('mandatory parameter missing: %s' % p)

  autodoc = AutoDoc(
    git_clone=params['git-clone'],
    output_path=params['output-path'],
    debug=params['debug'],
    new_tags=params['new-tags'],
    branch=params['branch'],
    build_path=params['build-path']
  )
  r = autodoc.run()
  sys.exit(r)