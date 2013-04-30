#!/bin/bash

#
# obfus.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Obfuscates an input script using base64 encoding and creates a self-unpacking
# output script.
#

export Prog=`basename "$0"`

# Prints help screen
function Help() {
  cat <<_EoF_
$Prog -- by Dario Berzano <dario.berzano@cern.ch>
Obfuscates an input script using base64 encoding and creates a self-unpacking
output script.

Usage: $Prog [inputscript]
_EoF_

    # -s SHELL                         script interpreter (default: bash)
    # -h, --help                       this help screen
}

# Main function
function Main() {
  local Input="$1"

  if [ ! -r "$Input" ] ; then
    Help
    exit 1
  fi

  # Which syntax for encoding with base64?
  Base64Enc='base64 -b 76'  # BSD (OS X)
  if ! echo test|$Base64Enc >/dev/null 2>&1 ; then
    Base64Enc='base64'  # GNU
  fi

  # Create a self-unpacking script
  cat <<_EoF_
#!/bin/bash
# `basename "$Input"` (obfuscated)
B64='base64 -d'
[ "\`echo -n dGVzdA== | \$B64 2>/dev/null\`" == test ] || B64='base64 -D'
exec bash <((cat|\$B64|gunzip) <<=ESH=
`cat "$Input" | gzip -9 | $Base64Enc`
=ESH=) "\$@"
_EoF_

}

#
# Entry point
#

Main "$@"
