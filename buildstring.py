#!/usr/bin/env python


import re
import os, subprocess
import sys, getopt


# Regular expressions
re_sanitize = re.compile( r'[^A-Za-z0-9._]' )
re_majorminorpatches = re.compile( r'^(([0-9]+)\.([0-9]+))\.([0-9]+)$' )
re_gccver = re.compile( r'version\s+((([0-9]+)\.([0-9]+))\.([0-9]+))' )
re_llvmver = re.compile( r'LLVM\s+((([0-9]+)\.([0-9]+))([^)]*))' )
re_pyver = re.compile( r'Python\s+((([0-9]+)\.([0-9]+))\.([0-9]+))' )
re_tag = re.compile( r'%([a-z]+)(\*?)%' )


# Exception thrown if something goes wrong while getting system information
class SysInfoError(Exception):
  def __init__(self, msg):
    Exception.__init__(self, msg)


def sanitize(s):
  """Returns the sanitized version of the current string: it will be with only
  letters, numbers and the underscore. All invalid characters are replaced with
  the underscore.
  """

  # http://stackoverflow.com/questions/4260280/python-if-else-in-list-comprehension
  gen = ( '_' if re_sanitize.match(x) else x for x in s )
  #       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^
  #           conditional expr (3-way op)    ^^^^^^^^^^
  #                                           iterator

  return ''.join(gen)


def get_os():
  """Returns a string identifying the operating system. The string is guaranteed
  being all lowercase and containing only letters, numbers and the underscore.
  Raises SysInfoError in case of problems.
  """
  try:
    with open(os.devnull, 'w') as dn:
      sp = subprocess.Popen(['uname', '-s'], stdout=subprocess.PIPE, stderr=dn)
    sp.wait()
    if sp.returncode != 0:
      raise SysInfoError('Cannot get Operating System')
    out = sanitize( sp.communicate()[0].strip() ).lower()
    return out
  except OSError as e:
    raise SysInfoError('While getting Operating System: ' + str(e))


def get_arch():
  """Returns a string identifying the architecture. Raises SysInfoError in case
  of problems.
  """
  try:
    with open(os.devnull, 'w') as dn:
      sp = subprocess.Popen(['uname', '-m'], stdout=subprocess.PIPE, stderr=dn)
    sp.wait()
    if sp.returncode != 0:
      raise SysInfoError('Cannot get Architecture')
    out = sanitize( sp.communicate()[0].strip() ).lower()
    return out
  except OSError as e:
    raise SysInfoError('While getting Architecture: ' + str(e))


def get_python(command=None):
  """Returns the Python version. Raises SysInfoError in case of problems."""

  if command is None:
    name = 'python'
    command = 'python'
  else:
    name = os.path.basename(command)

  try:
    sp = subprocess.Popen([command, '--version'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sp.wait()
    if sp.returncode != 0:
      vers_raw = None
    else:
      vers_raw = sp.communicate()[0]
  except OSError as e:
    raise SysInfoError('Error getting Python version: %s' % e)

  try:
    m = re_pyver.search( vers_raw )
  except TypeError:
    m = None

  if m is None:
    raise SysInfoError('Cannot get Python version')

  return {
    'vers_full': m.group(1),
    'vers_short': m.group(2),
  }


def get_compiler(command=None):
  """Returns a dictionary with the compiler's name and versions (short and
  full). Raises SysInfoError in case of problems.
  """

  if command is None:
    name = 'gcc'
    command = 'gcc'
  else:
    name = os.path.basename(command)

  vers_full = None
  vers_short = None

  try:
    with open(os.devnull, 'w') as dn:

      if name.startswith('cc') or name.startswith('gcc'):

        # First try with -dumpversion
        sp = subprocess.Popen([command, '-dumpversion'], stdout=subprocess.PIPE, stderr=dn)
        sp.wait()
        if sp.returncode != 0:
          vers_full = None
        else:
          vers_full = sp.communicate()[0].strip()

        # It might not return a properly formatted version (MAJ.MIN.PATCHES)
        try:
          m = re_majorminorpatches.match( vers_full )
        except TypeError:
          m = None

        if m is not None:
          vers_short = m.group(1)
        else:
          sp = subprocess.Popen([command, '-v'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
          sp.wait()
          for l in sp.stdout:
            m = re_gccver.search(l)
            if m:
              vers_full = m.group(1)
              vers_short = m.group(2)


        if vers_full is None:
          raise SysInfoError('Cannot get Compiler Info for GCC-like output (%s)' % name)

      elif name == 'clang':

        sp = subprocess.Popen([command, '-v'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        sp.wait()
        for l in sp.stdout:
          m = re_llvmver.search(l)
          if m:
            vers_full = m.group(1)
            vers_short = m.group(2)

        if vers_full is None:
          raise SysInfoError('Cannot get Compiler Info for clang-like output (%s)' % name)

      else:
        raise SysInfoError('While getting compiler: unsupported compiler %s' % name)

  except OSError as e:
    raise SysInfoError('While getting Compiler Info: ' + str(e))

  return {
    'name': name,
    'vers_full': vers_full,
    'vers_short': vers_short
  }


def get_build_tag(format='%os%', compiler=None, python=None):
  """Returns a formatted build tag. Format specifiers:
   - %os%: the operating system
   - %arch%: the architecture
   - %compiler%: the compiler name
   - %compilerverfull%: the compiler version (full)
   - %compilerver%: the compiler version (major and minor)
   - %pythonverfull%: Python version (full)
   - %pythonver%: Python version (major and minor)
  """

  # Cache
  os = None
  arch = None
  comp = None
  py = None

  # Find all tags
  dest = format
  for m in re_tag.finditer(format):

    tag = m.group(1)
    value = None

    if tag == 'os':
      if os is None: os = get_os()
      value = os
    elif tag == 'arch':
      if arch is None: arch = get_arch()
      value = arch
    elif tag.startswith('compiler'):
      if comp is None: comp = get_compiler(compiler)
      if tag == 'compiler':
        value = comp['name']
      elif tag == 'compilerver':
        value = comp['vers_short']
      elif tag == 'compilerverfull':
        value = comp['vers_full']
    elif tag.startswith('pyver'):
      if py is None: py = get_python(python)
      if tag == 'pyver':
        value = py['vers_short']
      elif tag == 'pyverfull':
        value = py['vers_full']

    if value == None:
      value = '<tag_%s_unknown>' % tag

    if m.group(2) == '*':
      value = value.replace('.', '')

    dest = dest.replace( m.group(0), value, 1 )


  return dest


def main(argv):
  """Tries to generate an architecture string for the current build
  environment."""

  compiler = None
  python = None
  format = "%os%-%arch%-%compiler%%compilerver*%"

  try:
    opts, args = getopt.getopt(argv, '', [ 'compiler=', 'python=', 'format=' ])
    for o, a in opts:
      if o == '--compiler':
        compiler = a
      elif o == '--python':
        python = a
      elif o == '--format':
        format = a
  except getopt.GetoptError as e:
    print "buildstring: %s" % e
    return 1

  print get_build_tag(format, compiler=compiler, python=python)

  return 0


# Entry point
if __name__ == '__main__':
  sys.exit( main(sys.argv[1:]) )
