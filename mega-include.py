#!/usr/bin/env python

import re
import sys
import os
import getopt

# Main function
def scan(source, include_paths, output_file, exclude_regexp, max_depth):

  print 'I-scanning file: %s' % source
  print 'I-using include paths (in order): %s' % ', '.join(include_paths)

  dep_graph = scan_recursive(
    source=source,
    include_paths=include_paths,
    exclude_regexp=exclude_regexp,
    max_depth=max_depth
  )

  output_dot(dep_graph, output_file)


# Output dot file
def output_dot(dep_graph, out_file):

  with open(out_file, 'w') as fp:

    fp.write('digraph g {\n')

    for node,deps in dep_graph.iteritems():
      if node.startswith('T'):
        color = 'darkolivegreen2'
      elif node.startswith('Ali'):
        color = 'firebrick2'
      elif node[0].isupper():
        color = 'green3'
      else:
        color = 'gold1'

      fp.write('  "%s" [style=filled, color=%s]\n' % (node, color))

    for node,deps in dep_graph.iteritems():
      for d in deps:
        fp.write( '  "%s" -> "%s" ;\n' % (node, d) )
    fp.write('}\n')

  print 'I-dot file %s written' % out_file


# Scans recursively. Prevents loops.
def scan_recursive(source, include_paths, dep_graph={}, depth=0, exclude_regexp=None, max_depth=-1):

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
  re_include = r'^\s*#include\s+("|<)(.*?)(\.[A-Za-z0-9]+)?("|>)\s*$'

  # Indent for messages
  indent = ' ' * depth

  # Scan
  with open(new_source, 'r') as fp:

    for line in fp:
      line = line.rstrip('\n')
      m_include = re.search(re_include, line)
      if m_include:
        dependency = m_include.group(2)

        if exclude_regexp is not None and re.search(exclude_regexp, dependency):
          print 'D-found dependency (excluding): %s -> %s' % (source, dependency)

        else:
          print 'I-found dependency: %s -> %s' % (source, dependency)

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
              max_depth=max_depth
            )
          # else:
          #   print 'D-scan skipped: %s' % dependency

  return dep_graph


# Entry point
if __name__ == '__main__':

  include_paths = []
  exclude_re = None
  output_file = 'default.dot'
  max_depth = -1

  opts, args = getopt.getopt(sys.argv[1:], 'I:o:',
    [ 'include=', 'output-dot=', 'exclude-regex=', 'max-depth=' ])
  for o, a in opts:
    if o == '-I' or o == '--include':
      include_paths.append(a)
    elif o == '-o' or o == '--output-dot':
      output_file = a
    elif o == '--exclude-regex':
      exclude_re = re.compile(a)
    elif o == '--max-depth':
      max_depth = int(a)
    else:
      raise getopt.GetoptError('unknown parameter: %s (%s)' % (o,a))

  if len(args) == 0:
    raise getopt.GetoptError('specify at least one filename to scan')

  r = scan(
    source=args[0],
    include_paths=include_paths,
    output_file=output_file,
    exclude_regexp=exclude_re,
    max_depth=max_depth
  )
  sys.exit(r)
