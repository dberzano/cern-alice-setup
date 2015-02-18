#!/usr/bin/env python

import re
import sys
import os
import getopt

# Main function
def scan(source, include_paths, output_file):

  print 'I-scanning file: %s' % source
  print 'I-using include paths (in order): %s' % ', '.join(include_paths)

  dep_graph = scan_recursive(source, include_paths)

  output_dot(dep_graph, output_file)


# Output dot file
def output_dot(dep_graph, out_file):

  with open(out_file, 'w') as fp:

    fp.write('digraph g {\n')

    for node,deps in dep_graph.iteritems():
      if node.startswith('T'):
        color = 'darkolivegreen2'
      elif node.startswith('R'):
        color = 'green3'
      elif node.startswith('Ali'):
        color = 'firebrick2'
      else:
        color = 'gold1'

      fp.write('  "%s" [style=filled, color=%s]\n' % (node, color))

    for node,deps in dep_graph.iteritems():
      for d in deps:
        fp.write( '  "%s" -> "%s" ;\n' % (node, d) )
    fp.write('}\n')

  print 'I-dot file %s written' % out_file


# Scans recursively. Prevents loops.
def scan_recursive(source, include_paths, dep_graph={}, depth=0):

  # Init
  dep_graph[source] = []

  # Look for file
  if not os.path.isfile(source):
    found = False
    for d in include_paths:
      new_source = d+'/'+source
      if os.path.isfile(new_source):
        source_full = new_source
        found = True
        break

    if not found:
      print 'W-not found in curdir or any of the include paths: %s' % source
      return dep_graph

  else:
    source_full = './'+source

  # Regexp
  re_include = r'^\s*#include\s+("|<)(.*?)("|>)\s*$'

  # Indent for messages
  indent = ' '*depth

  # Scan
  with open(source_full, 'r') as fp:

    for line in fp:
      line = line.rstrip('\n')
      m_include = re.search(re_include, line)
      if m_include:
        dependency = m_include.group(2)
        print 'I-found dependency: %s -> %s' % (source, dependency)

        # Do not add duplicates
        if not dependency in dep_graph[source]:
          dep_graph[source].append(dependency)

        if not dependency in dep_graph:
          dep_graph = scan_recursive(
            source=dependency,
            include_paths=include_paths,
            dep_graph=dep_graph,
            depth=depth+1
          )
        # else:
        #   print 'D-scan skipped: %s' % dependency

  return dep_graph


# Entry point
if __name__ == '__main__':

  include_paths = []
  exclude_re = []
  output_file = 'default.dot'

  opts, args = getopt.getopt( sys.argv[1:], 'I:o:', [ 'include=', 'output-dot=' ] )
  for o, a in opts:
    if o == '-I' or o == '--include':
      include_paths.append(a)
    elif o == '-o' or o == '--output-dot':
      output_file = a
    else:
      raise getopt.GetoptError('unknown parameter: %s (%s)' % (o,a))

  if len(args) == 0:
    raise getopt.GetoptError('specify at least one filename to scan')

  r = scan(
    source=args[0],
    include_paths=include_paths,
    output_file=output_file
  )
  sys.exit(r)
