#!/usr/bin/env python

import re
import sys
import os
import getopt
import subprocess


# Main function
def scan(source, include_paths, library_paths, output_file, exclude_regexp, max_depth, fwd_decl,
  find_libs, libs_only):

  print 'I-scanning file: %s' % source
  print 'I-using include paths (in order): %s' % ', '.join(include_paths)

  dep_graph = scan_recursive(
    source=source,
    include_paths=include_paths,
    exclude_regexp=exclude_regexp,
    max_depth=max_depth,
    fwd_decl=fwd_decl
  )

  if find_libs:
    class_libs = guess_libs(
      names=dep_graph.keys(),
      library_paths=library_paths,
      upcase_only=True
    )
  else:
    class_libs = None

  output_dot(dep_graph, output_file, class_libs, libs_only)


# Display class name with lib, or lib only, or class only
def cname_lib(cname, class_libs, libs_only):

  if class_libs is not None:
    try:
      if libs_only:
        # only show library
        cname_lib = class_libs[cname]
      else:
        # show class and library
        cname_lib = '%s(%s)' % (cname, class_libs[cname])
    except KeyError:
      # if library is not found, always show class name
      cname_lib = '%s(<lib?>)' % cname
  else:
    cname_lib = cname

  return cname_lib


# Output dot file
def output_dot(dep_graph, out_file, class_libs, libs_only, suppress_unknown_libs):

  map_color = {}
  map_deps = {}

  for node,deps in dep_graph.iteritems():
    if node.startswith('T'):
      color = 'darkolivegreen2'
    elif node.startswith('Ali'):
      color = 'firebrick2'
    elif node[0].isupper():
      color = 'green3'
    else:
      color = 'gold1'

    node_lib = cname_lib(node, class_libs, libs_only)
    if node_lib not in map_color:
      map_color[node_lib] = color

  for node,deps in dep_graph.iteritems():
    node_lib = cname_lib(node, class_libs, libs_only)
    for d in deps:
      d_lib = cname_lib(d, class_libs, libs_only)
      if d_lib != node_lib:
        if node_lib not in map_deps:
          map_deps[node_lib] = [ d_lib ]
        elif d_lib not in map_deps[node_lib]:
          map_deps[node_lib].append( d_lib )

  with open(out_file, 'w') as fp:

    fp.write('digraph g {\n')
    for node,color in map_color.iteritems():
      fp.write('  "%s" [style=filled, color=%s]\n' % (node, color))
    fp.write('\n')
    for node,deps in map_deps.iteritems():
      for dep in deps:
        fp.write( '  "%s" -> "%s" ;\n' % (node, dep) )
    fp.write('}\n')

  print 'I-dot file %s written' % out_file


# Finds symbols in libraries. Returns a dictionary: class => lib (no ext).
def guess_libs(names, library_paths, upcase_only):

  class_lib = {}

  for n in names:
    found = False

    if not upcase_only or n[0].isupper():

      # search string
      search_defsym = ' T _ZN%d%s' % (len(n), n)  # TODO: name mangling varies across platforms

      for lib_path in library_paths:
        if os.path.isdir(lib_path):

          for lib in next(os.walk(lib_path))[2]:

            if lib.endswith('.so') or lib.endswith('.dylib') or lib.endswith('.dll'):
              #print 'D-looking for %s into %s/%s' % (n, lib_path, lib)
              with open(os.devnull, 'w') as dev_null:
                cmd = 'nm %s | grep -q "%s"' % (lib, search_defsym)  # TODO: unsafe and terrible hack
                sp = subprocess.Popen(cmd, stderr=dev_null, stdout=dev_null,
                  shell=True, cwd=lib_path)
                rc = sp.wait()
                if rc == 0:
                  found = True
                  break

          if found:
            # do not look in other libpaths
            break

    if found:
      lib = lib[0:lib.rindex('.')]
      class_lib[n] = lib
      print 'I-%s found in %s' % (n, lib)
    else:
      print 'W-%s not found in any lib' % n

  return class_lib


# Scans recursively. Prevents infinite loops
def scan_recursive(source, include_paths, dep_graph={}, depth=0, exclude_regexp=None, max_depth=-1,
  fwd_decl=False):

  # Init
  dep_graph[source] = []

  # Maximum depth reached?
  if max_depth != -1 and depth >= max_depth:
    print 'D-not inspecting %s: depth limit' % source
    return dep_graph

  # Look for file, with some possible extensions
  found = False
  for new_source in [ source, source+'.h', source+'.hh', source+'.cxx', source+'.cc' ]:

    #print 'D-%s: attempting %s (curdir)' % (source, new_source)

    if os.path.isfile(new_source):
      # Found in current dir
      new_source = './' + new_source
      found = True

    else:
      # Not found: look in include paths
      for d in include_paths:
        new_source_with_dir = d+'/'+new_source
        #print 'D-%s: attempting %s (incdir)' % (source, new_source_with_dir)
        if os.path.isfile(new_source_with_dir):
          new_source = new_source_with_dir
          found = True
          break

    if found:
      break

  if not found:
    print 'W-not found in curdir or any of the include paths: %s' % source
    return dep_graph

  # Regexp
  re_include = r'^\s*(#include\s+("|<)(.*?)(\.[A-Za-z0-9]+)?("|>)|class\s*(.*?)\;)\s*$'

  # Indent for messages
  indent = ' ' * depth

  # Scan
  with open(new_source, 'r') as fp:

    for line in fp:
      line = line.rstrip('\n')
      m_include = re.search(re_include, line)
      dependency = None
      from_fwd_decl = False
      if m_include:
        dependency = m_include.group(3)  # from #include
        if dependency is None and fwd_decl:
          from_fwd_decl = True
          dependency = m_include.group(6)  # from class (fwd decl)

      if dependency is not None:

        if exclude_regexp is not None and re.search(exclude_regexp, dependency):
          print 'D-found dependency (excluding): %s -> %s' % (source, dependency)

        else:
          if from_fwd_decl:
            dep_source = 'forward decl'
          else:
            dep_source = 'include'
          print 'I-found dependency: %s -> %s (from %s)' % (source, dependency, dep_source)

          # Do not add duplicates
          if not dependency in dep_graph[source]:
            dep_graph[source].append(dependency)

          if not dependency in dep_graph:
            dep_graph = scan_recursive(
              source=dependency,
              include_paths=include_paths,
              dep_graph=dep_graph,
              depth=depth+1,
              exclude_regexp=exclude_regexp,
              max_depth=max_depth,
              fwd_decl=fwd_decl
            )
          # else:
          #   print 'D-scan skipped: %s' % dependency

  return dep_graph


# Entry point
if __name__ == '__main__':

  include_paths = []
  library_paths = []
  exclude_re = None
  output_file = 'default.dot'
  max_depth = -1
  fwd_decl = False
  find_libs = False
  libs_only = False

  opts, args = getopt.getopt(sys.argv[1:], 'I:L:o:',
    [ 'include=', 'libpath=', 'output-dot=', 'exclude-regex=', 'max-depth=', 'fwd-decl',
    'find-libs', 'libs-only' ])
  for o, a in opts:
    if o == '-I' or o == '--include':
      include_paths.append(a)
    elif o == '-L' or o == '--libpath':
      library_paths.append(a)
    elif o == '-o' or o == '--output-dot':
      output_file = a
    elif o == '--exclude-regex':
      exclude_re = re.compile(a)
    elif o == '--max-depth':
      max_depth = int(a)
    elif o == '--fwd-decl':
      fwd_decl = True
    elif o == '--find-libs':
      find_libs = True
    elif o == '--libs-only':
      find_libs = True
      libs_only = True
    else:
      raise getopt.GetoptError('unknown parameter: %s (%s)' % (o,a))

  if len(args) == 0:
    raise getopt.GetoptError('specify at least one filename to scan')

  r = scan(
    source=args[0],
    include_paths=include_paths,
    library_paths=library_paths,
    output_file=output_file,
    exclude_regexp=exclude_re,
    max_depth=max_depth,
    fwd_decl=fwd_decl,
    find_libs=find_libs,
    libs_only=libs_only
  )
  sys.exit(r)
