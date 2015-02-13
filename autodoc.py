#!/usr/bin/env python

import sys, os, time
import getopt
import subprocess
import tempfile
import shutil
import logging, logging.handlers
from smtplib import SMTP
from socket import getfqdn

## @class AutoDoc
#  @brief Generates documentation for new tags in a Git repository
#
#  @todo Actually generate Doxygen documentation
#  @todo Move documentation in place
class AutoDoc(object):

  ## Module version
  __version__ = '0.1.1'

  ## Constructor.
  #
  #  @param git_clone Full path to the Git clone to consider
  #  @param output_path Directory containing one subdirectory per documentation version
  #  @param debug True enables debug output, False suppresses it
  #  @param new_tags If True, generate doc for new tags; if False, see branch
  #  @param branch If new_tags is False, generates doc for this branch's head
  #  @param build_path Uses the given path as CMake and Doxygen cache, instead of a disposable one
  #  @param syslog_only If True, log on syslog only and be quiet on stderr and stdout
  #  @param always_purge If True, always delete temp directory, even when doc generation fails
  #  @param smtp_server Address of SMTP server: if provided, it is used to send emails
  #  @param smtp_port Port of SMTP server
  #  @param mail_to List of email addresses to send notifications to
  def __init__(self, git_clone, output_path, debug, new_tags, branch, build_path, \
    syslog_only, always_purge, smtp_server, smtp_port, mail_to):

    ## Full path to the Git clone
    self._git_clone = git_clone
    ## Full path to the prefix of the output directory (doc will be put in a subdir of it)
    self._output_path = output_path
    ## Logging facility (use it with `self._log.info()`, etc.)
    self._log = None
    ## Generate for new tags (True, or False)
    self._new_tags = new_tags
    ## If not generating for new tags, branch name to consider
    self._branch = branch
    ## Instead of generating a temporary build directory use this one (*i.e.* for caching)
    self._build_path = build_path
    ## Show output of external commands
    self._show_cmd_output = debug
    if syslog_only:
      self._show_cmd_output = False
    ## Delete temp directory also when doc generation fails
    self._always_purge = always_purge
    ## SMTP server for notifications
    self._smtp_server = smtp_server
    ## SMTP server port
    self._smtp_port = smtp_port
    ## List of email addresses to send notifications to
    self._mail_to = mail_to

    self._init_log(debug, syslog_only)


  ## Initializes the logging facility.
  #
  #  @param debug True enables debug output, False suppresses it
  #  @param syslog_only If True, log on syslog only and be quiet on stderr
  def _init_log(self, debug, syslog_only):

    self._log = logging.getLogger('AutoDoc')

    msg_fmt_syslog = 'AutoDoc[%d]: %%(levelname)s: %%(message)s' % os.getpid()
    msg_fmt_stderr = '%(asctime)s ' + msg_fmt_syslog
    datetime_fmt = '%Y-%m-%d %H:%M:%S'

    if syslog_only == False:
      stderr_handler = logging.StreamHandler(stream=sys.stderr)
      # Date/time only on stderr (syslog already has it)
      stderr_handler.setFormatter( logging.Formatter(msg_fmt_stderr, datetime_fmt) )
      self._log.addHandler(stderr_handler)

    syslog_handler = self._get_syslog_handler()
    syslog_handler.setFormatter( logging.Formatter(msg_fmt_syslog) )
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
      if not self._show_cmd_output:
        redirect = dev_null
      else:
        redirect = None
      sp = subprocess.Popen(cmd, stderr=redirect, stdout=subprocess.PIPE, shell=False, \
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
      if not self._show_cmd_output:
        redirect = dev_null
      else:
        redirect = None
      sp = subprocess.Popen(cmd, stderr=redirect, stdout=redirect, shell=False, cwd=self._git_clone)

    rc = sp.wait()

    if rc == 0:
      self._log.debug('Success updating repository')
      return True

    self._log.error('Error updating repository, returned %d' % rc)
    return False


  ## Updates current working directory from the specified remote branch.
  #
  #  Note that the branch must be properly checked out otherwise. Tags are not
  #  fetched by this command.
  #
  #  @param remote Name of the remote to use (*i.e.* **origin**)
  #  @param branch Remote branch
  #
  #  @return True on success, False on error
  def update_branch(self, remote, branch):

    self._log.info('Getting updates for %s/%s' % (remote, branch))

    cmd = [ 'git', 'pull', remote, branch, '--no-tags' ]

    with open(os.devnull, 'w') as dev_null:
      if not self._show_cmd_output:
        redirect = dev_null
      else:
        redirect = None
      sp = subprocess.Popen(cmd, shell=False, stderr=redirect, stdout=redirect, cwd=self._git_clone)

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

    with open(os.devnull, 'w') as dev_null:

      if not self._show_cmd_output:
        redirect = dev_null
      else:
        redirect = None

      self._log.debug('Resetting current working directory')
      cmd = [ 'git', 'reset', '--hard', 'HEAD' ]
      sp = subprocess.Popen(cmd, stderr=redirect, stdout=redirect, shell=False, cwd=self._git_clone)
      rc = sp.wait()
      if rc == 0:
        self._log.debug('Success resetting current working directory')
      else:
        self._log.error('Error resetting current working directory, returned %d' % rc)
        return False

      self._log.debug('Cleaning up working directory')
      cmd = [ 'git', 'clean', '-f', '-d' ]
      sp = subprocess.Popen(cmd, stderr=redirect, stdout=redirect, shell=False, cwd=self._git_clone)
      rc = sp.wait()
      if rc == 0:
        self._log.debug('Success cleaning up working directory')
      else:
        self._log.error('Error cleaning up working directory, returned %d' % rc)
        return False

      self._log.debug('Checking out reference %s' % ref)
      cmd = [ 'git', 'checkout', ref ]
      sp = subprocess.Popen(cmd, stderr=redirect, stdout=redirect, shell=False, cwd=self._git_clone)
      rc = sp.wait()
      if rc == 0:
        self._log.debug('Success checking out reference %s' % ref)
      else:
        self._log.error('Error checking out reference %s, returned %d' % (ref, rc))
        return False

    return True


  ## Deletes a list of local tags.
  #
  #  @param tags A single tag name, or a list of tags
  #
  #  @return Number of errors: 0 means all green
  def delete_tags(self, tags):

    # List or single element?
    if not hasattr(tags, '__iter__'):
      tags = [ tags ]

    count_errs = 0

    for tag in tags:

      self._log.info('Deleting tag %s' % tag)

      cmd = [ 'git', 'tag', '-d', tag ]

      with open(os.devnull, 'w') as dev_null:
        if not self._show_cmd_output:
          redirect = dev_null
        else:
          redirect = None
        sp = subprocess.Popen(cmd, shell=False, stderr=redirect, stdout=redirect, cwd=self._git_clone)

      rc = sp.wait()

      if rc == 0:
        self._log.debug('Tag %s deleted' % tag)
      else:
        self._log.error('Error deleting tag %s' % tag)
        count_errs = count_errs + 1

    return count_errs


  ## Creates Doxygen documentation for the current working directory of Git.
  #
  #  @param output_path_subdir Subdir of output path where to store the generated documentation
  #
  #  @return True on success, False on error
  def gen_doc(self, output_path_subdir):

    build_path = self._build_path

    if build_path is None:
      self._log.debug('Creating a temporary build directory')
      build_path = tempfile.mkdtemp()
      build_path_is_temp = True
    else:
      build_path_is_temp = False
      if not os.path.isdir(build_path):
        os.makedirs(build_path)

    all_ok = True

    self._log.debug('Build directory: %s' % build_path)

    try:

      with open(os.devnull, 'w') as dev_null:

        if not self._show_cmd_output:
          redirect = dev_null
        else:
          redirect = None

        self._log.debug('Preparing build with CMake')
        cmd = [ 'cmake', self._git_clone, '-DDOXYGEN_ONLY=ON' ]
        sp = subprocess.Popen(cmd, stderr=redirect, stdout=redirect, shell=False, cwd=build_path)
        rc = sp.wait()
        if rc == 0:
          self._log.debug('Success preparing build with CMake')
        else:
          self._log.error('Error preparing build with CMake, returned %d' % rc)
          raise Exception

        self._log.debug('Generating documentation (will take a while)')
        cmd = [ 'make', 'doxygen' ]
        sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null, shell=False, cwd=build_path)
        rc = sp.wait()
        if rc == 0:
          self._log.debug('Success generating documentation')
        else:
          self._log.error('Error generating documentation, returned %d' % rc)
          raise Exception

        # Let it except freely on error
        self._log.debug('Creating output directory')
        if not os.path.isdir(self._output_path):
          os.makedirs(self._output_path)

        self._log.debug('Publishing documentation to %s' % self._output_path)
        cmd = [ 'rsync', '-a', '--delete',
          '%s/doxygen/html/' % build_path,
          '%s/%s/' % (self._output_path, output_path_subdir) ]
        sp = subprocess.Popen(cmd, stderr=redirect, stdout=redirect, shell=False, cwd=build_path)
        rc = sp.wait()
        if rc == 0:
          self._log.debug('Success publishing documentation to %s' % self._output_path)
        else:
          self._log.error('Error publishing documentation to %s, returned %d' % (self._output_path, rc))
          raise Exception

    except Exception:
      all_ok = False

    finally:

      # Clean up working directory
      if build_path_is_temp and ( all_ok or self._always_purge ):
        self._log.debug('Cleaning up working directory %s' % build_path)
        shutil.rmtree(build_path)

    # All went right
    if all_ok:
      self._log.info('Documentation successfully generated in %s/%s' % \
        (self._output_path, output_path_subdir))
      return True
    else:
      return False


  ## Generate documentation for new tags found.
  #
  #  @return False on failure, True on success
  #
  #  @todo Remove debug code
  def gen_doc_new_tags(self):

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

    # Generate doc
    tags_failed = []
    for tag in tags_new:
      if not self.checkout_ref(tag):
        self._log.fatal('Cannot switch to tag %s: aborting' % tag)
        return False

      if not self.gen_doc(output_path_subdir=tag):
        self._log.error('Cannot generate documentation for tag %s' % tag)
        tags_failed.append(tag)
      else:
        self._log.info('Generated documentation for tag %s' % tag)

    # Removing failed tags
    if len(tags_failed) > 0:
      self.delete_tags(tags_failed)
      self._log.error('Errors were encountered for some tags: %s' % ' '.join(tags_failed))
      return False

    # No errors
    return True


  ## Generate documentation for a branch's head, which is updated first.
  #
  #  @return False on failure, True on success
  def gen_doc_head(self):

    self._log.info('Generating documentation for %s' % self._branch)

    if not self.checkout_ref(self._branch):
      return False

    # This operation needs to be repeated several times in case of failures
    update_success = False
    failure_count = 0
    failure_threshold = 3
    retry_pause_s = 3
    while True:
      update_success = self.update_branch('origin', self._branch)
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

    return self.gen_doc(output_path_subdir=self._branch)


  ## Sends a notification email.
  #
  # @param subject Email subject
  # @param message_body Email body
  # @param subject_prefix Prepend this string to the subject, e.g. "[MailingListName] "
  # @param sender Emails appear as sent by this address
  #
  # @return True on success, False on failure
  def send_mail(self, subject, message_body,
    subject_prefix='[AliAutoDoc] ', sender='ALICE AutoDoc <noreply@cern.ch>'):

    self._log.info('Sending notification email to: %s' % ', '.join(self._mail_to))
    message_body = '''From: %s
To: %s
Subject: %s%s

%s
--
ALICE AutoDoc Server @ %s
Local time on the Server: %s
''' % (sender, ', '.join(self._mail_to), subject_prefix, subject, \
       message_body, getfqdn(), time.strftime('%b %-d, %Y %H:%M:%S %Z'))

    try:
      mailer = SMTP(self._smtp_server, self._smtp_port)
      mailer.sendmail(sender, self._mail_to, message_body)
    except Exception as e:
      self._log.error('Error sending notification email: %s' % e)
      return False

    self._log.debug('Notification email sent')
    return True


  ## Entry point for all operations.
  #
  #  @return 0 on success, nonzero on error
  def run(self):

    self._log.info('This is AutoDoc v%s' % self.__version__)

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
    'build-path': None,
    'syslog-only': False,
    'always-purge': False,
    'smtp-server': False,
    'smtp-port': False,
    'mail-to': []
  }

  opts, args = getopt.getopt(sys.argv[1:], '',
    [ 'git-clone=', 'output-path=', 'debug', 'branch=', 'new-tags', 'build-path=',
      'syslog-only', 'always-purge', 'smtp-server=', 'mail-to=' ])
  for o, a in opts:
    if o == '--git-clone':
      params['git-clone'] = a
    elif o == '--output-path':
      params['output-path'] = a
    elif o == '--debug':
      params['debug'] = True
    elif o == '--branch':
      params['branch'] = a
    elif o == '--new-tags':
      params['new-tags'] = True
    elif o == '--build-path':
      params['build-path'] = a
    elif o == '--syslog-only':
      params['syslog-only'] = True
    elif o == '--always-purge':
      params['always-purge'] = True
    elif o == '--smtp-server':
      tok = a.split(':', 2)
      params['smtp-server'] = tok[0]
      if len(tok) == 1:
        params['smtp-port'] = 25
      else:
        params['smtp-port'] = int( tok[1] )
    elif o == '--mail-to':
      params['mail-to'] = a.split(',')
    else:
      raise getopt.GetoptError('unknown parameter: %s' % o)

  if params['new-tags'] == True:

    if params['branch'] is not None:
      raise getopt.GetoptError('use either --new-tags or --branch')
    elif params['build-path'] is not None:
      raise getopt.GetoptError('cannot use --build-path with --new-tags')
    else:
      # Silence errors of required params
      params['build-path'] = False
      params['branch'] = False

  elif params['branch'] is not None:
    params['new-tags'] = False

  else:
    raise getopt.GetoptError('one of --new-tags or --branch is mandatory')

  for p in params:
    if params[p] is None:
     raise getopt.GetoptError('mandatory parameter missing: %s' % p)

  if params['build-path'] == False:
    params['build-path'] = None

  autodoc = AutoDoc(
    git_clone=params['git-clone'],
    output_path=params['output-path'],
    debug=params['debug'],
    new_tags=params['new-tags'],
    branch=params['branch'],
    build_path=params['build-path'],
    syslog_only=params['syslog-only'],
    always_purge=params['always-purge'],
    smtp_server=params['smtp-server'],
    smtp_port=params['smtp-port'],
    mail_to=params['mail-to']
  )
  r = autodoc.run()
  sys.exit(r)
