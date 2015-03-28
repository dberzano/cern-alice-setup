#
# alice-env.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Prepares the environment for running the ALICE Framework, in particular:
#
#   AliEn
#   ROOT
#   Geant 3
#   AliRoot
#   AliPhysics
#
# It optionally supports:
#
#   FastJet
#   FastJet Contrib
#
# This script is tested to work under Ubuntu, OS X and Fedora. For more information on compatibility
# and build instructions, please consult:
#
#   https://dberzano.github.io/alice/install-aliroot/
#

####################################################################################################
#                                                                                                  #
#                                * * * DON'T TOUCH THIS FILE! * * *                                #
#                                                                                                  #
# Configuration variables are found in a separate file, in the same directory of this script:      #
#                                                                                                  #
#   alice-env.conf                                                                                 #
#                                                                                                  #
# Or if you prefer, you can create a hidden file in your home:                                     #
#                                                                                                  #
#   ~/.alice-env.conf                                                                              #
#                                                                                                  #
# If none of the configuration files is found, a default alice-env.conf is created in the same     #
# directory where this script is stored.                                                           #
#                                                                                                  #
# This script gets updated automatically, so any change you make will be lost.                     #
#                                                                                                  #
####################################################################################################

# colors
Cm="\033[35m"
Cy="\033[33m"
Cc="\033[36m"
Cb="\033[34m"
Cg="\033[32m"
Cr="\033[31m"
Cw="\033[37m"
Cz="\033[m"
Br="\033[41m"
By="\033[43m"

#
# Functions
#

# interactively pick the ALICE software tuple: returns nothing, result is a number stored in the
# nAliTuple variable
function AliMenu() {

  local raw idx

  # header
  echo
  echo -e "${Cm}Select an ALICE software tuple from below.${Cz}"
  echo
  echo -e "${Cm}Note: ${Cc}you might as well source this script with \"-n <n_tuple>\" for a"
  echo -e "      non-interactive selection or with \"-c\" to clean the envrionment.${Cz}"
  echo

  # list of tuples
  for (( idx=1 ; idx<=${#AliTuple[@]} ; idx++ )) ; do
    printf " ${Cc}% 2d.${Cz}" $idx
    for sec in root geant3 aliroot aliphysics fastjet fjcontrib ; do
      raw=$( AliTupleSection "${AliTuple[$idx]}" $sec )
      if [[ $? == 0 ]] ; then
        AliParseVerDir "$raw" d v
        if [[ $v == $raw ]] ; then
          # single entry
          echo -ne " ${sec}:${Cm}${raw}${Cz}"
        else
          # version != subdir
          echo -ne " ${sec}:${Cm}${d}${Cz}(${Cc}${v}${Cz})"
        fi
        unset v d
      fi
    done
    echo
  done

  # option to clean
  echo
  echo -e " ${Cc} 0.${Cz} Clean environment"

  # prompt
  while [[ 1 ]] ; do
    echo
    echo -ne 'Your choice (type a number and press ENTER): '
    read nAliTuple
    if [[ ! $nAliTuple =~ ^[[:digit:]]+$ ]] ; then
      echo -e "${Cr}Not a number${Cz}"
    elif [[ $nAliTuple -gt ${#AliTuple[@]} ]] ; then
      echo -e "${Cr}Out of range${Cz}"
    else
      break
    fi
  done

  # "return" variable
  export nAliTuple
  return 0

}

# extracts the specified section from the given tuple
function AliTupleSection() (
  local tuple="$1"
  local secname="$2"
  if [[ $tuple =~ (^|[[:blank:]]+)${secname}=([^[:blank:]]+) ]] ; then
    echo "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
)

# finds tuple index by name
function AliTupleNumberByQuery() (
  local query="$1"
  local preferred_ver rawtuple sec tup tuple_matches count_tuple

  count_tuple=0
  for tup in "${AliTuple[@]}" ; do

    count_tuple=$(( count_tuple + 1 ))
    tuple_matches=0

    for sec in alien root geant3 aliroot aliphysics fastjet fjcontrib ; do

      preferred_ver=$( AliTupleSection "$query" "$sec" )

      if [[ $preferred_ver != '' ]] ; then

        rawtuple=$( AliTupleSection "$tup" "$sec" )
        if [[ $rawtuple != '' ]] ; then
          AliParseVerDir "$rawtuple" swdir swver
          #echo "tuple has sw=[$sec] dir=[$swdir] ver=[$swver]" >&2

          if [[ $preferred_ver == $swdir ]] ; then
            tuple_matches=1
          else
            tuple_matches=0
          fi

          unset swdir swver
        fi

      fi

    done

    if [[ $tuple_matches == 1 ]] ; then
      # matching tuple found
      echo $count_tuple
      return 0
    fi

  done

  # no matching tuple found: echo nothing
  return 1
)

# removes from a $PATH-like variable all the paths containing at least one of the specified files:
# variable name is the first argument, and file names are the remaining arguments
function AliRemovePaths() {

  local RetainPaths="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin:$HOME/bin"
  local VARNAME=$1
  shift
  local DIRS=`eval echo \\$$VARNAME`
  local NEWDIRS=""
  local OIFS="$IFS"
  local D F KEEPDIR
  local RemovePathsDebug=0
  local DebugPrompt="${Cc}RemovePaths>${Cz} "
  IFS=:

  [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}${Cm}variable:${Cz} $VARNAME"

  for D in $DIRS ; do

    [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}  directory $D"

    KEEPDIR=1
    D=$( cd "$D" 2> /dev/null && pwd || echo "$D" )
    if [[ -d "$D" ]] ; then

      # condemn directory if one of the given files is there
      for F in $@ ; do
        if [[ -e "$D/$F" ]] ; then
          [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}    remove it: found one of the given files"
          KEEPDIR=0
          break
        elif [ -e "${D}"/tgt_*/"${F}" ] ; then
          [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}    remove it: a tgt_ subdirectory contains one of the given files"
          KEEPDIR=0
          break
        fi
      done

      # retain directory if it is in RetainPaths (may revert)
      for K in $RetainPaths ; do
        if [[ "$D" == "$( cd "$K" 2> /dev/null ; pwd )" ]] ; then
          [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}    kept: is a system path"
          KEEPDIR=1
          break
        fi
      done

    else
      [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}    remove it: cannot access it"
      KEEPDIR=0
    fi
    if [[ $KEEPDIR == 1 ]] ; then
      [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}    ${Cg}final decision: keeping${Cz}"
      [[ "$NEWDIRS" == "" ]] && NEWDIRS="$D" || NEWDIRS="${NEWDIRS}:${D}"
    else
      [[ $RemovePathsDebug == 1 ]] && echo -e "${DebugPrompt}    ${Cr}final decision: discarding${Cz}"
    fi

  done

  IFS="$OIFS"

  eval export $VARNAME="$NEWDIRS"
  AliCleanPathList $VARNAME

}

# cleans leading, trailing and double colons from the variable whose name is passed as the only arg
function AliCleanPathList() {
  local VARNAME="$1"
  local STR=`eval echo \\$$VARNAME`
  local PREV_STR
  while [[ "$PREV_STR" != "$STR" ]] ; do
    PREV_STR="$STR"
    STR=`echo "$STR" | sed s/::/:/g`
  done
  STR=${STR#:}
  STR=${STR%:}
  if [[ $STR == '' ]] ; then
    unset $VARNAME
  else
    eval export $VARNAME=\"$STR\"
  fi
}

# cleans up the environment from previously set (DY)LD_LIBRARY_PATH and PATH variables
function AliCleanEnv() {

  if [[ $1 == '--extra' ]] ; then

    unset ALI_nAliTuple ALI_EnvScript ALI_Conf \
      ALICE_PREFIX \
      ROOT_VER ROOT_SUBDIR \
      G3_VER G3_SUBDIR \
      ALICE_VER ALICE_SUBDIR \
      ALIPHYSICS_VER ALIPHYSICS_SUBDIR \
      FASTJET_VER FASTJET_SUBDIR FJCONTRIB_VER \
      alien_API_USER AliPrompt \
      ALICE_ENV_DONT_CHANGE_PS1

  elif [[ $1 == '--final' ]] ; then

    # clean color definitions
    unset Cm Cy Cc Cb Cg Cr Cw Cz Br By

    # clean tuples
    unset AliTuple nAliTuple

    # cleanup of functions (also cleans up self!)
    unset AliCleanEnv AliCleanPathList AliExportVars AliMain AliMenu AliPrintVars \
      AliRemovePaths AliSetParallelMake AliConf AliUpdate AliTupleSection AliParseVerDir

  else

    # standard cleanup
    AliRemovePaths PATH alien_cp aliroot runTrain root fastjet-config
    AliRemovePaths LD_LIBRARY_PATH libCint.so libSTEER.so libXrdSec.so libgeant321.so \
       libgapiUI.so libfastjet.so libfastjet.dylib libTender.so libTender.dylib
    AliRemovePaths DYLD_LIBRARY_PATH libCint.so libSTEER.so libXrdSec.so libgeant321.so \
       libgapiUI.so libfastjet.so libfastjet.dylib libTender.so libTender.dylib
    AliRemovePaths PYTHONPATH ROOT.py

    # restore prompt
    [[ "$ALIPS1" != '' ]] && export PS1="$ALIPS1"
    unset ALIPS1

    # unset other environment variables and aliases
    unset MJ ALIEN_DIR GSHELL_ROOT ROOTSYS ALICE_ROOT ALICE_PHYSICS ALICE_SOURCE ALICE_BUILD \
      ROOT_ARCH ALICE_INSTALL GEANT3DIR X509_CERT_DIR FASTJET ALICE_ENV_UPDATE_URL \
      ALICE_ENV_DONT_UPDATE

  fi
}

# sets the number of parallel workers for make to the number of cores plus one to variable MJ
function AliSetParallelMake() {
  MJ=`grep -c bogomips /proc/cpuinfo 2> /dev/null`
  [[ "$?" != 0 ]] && MJ=`sysctl hw.ncpu | cut -b10 2> /dev/null`
  # if MJ is NaN, "let" treats it as "0", i.e.: always fallback to 1 core
  let MJ++
  export MJ
}

# remove environment overrides from gclient_env
function AliAliEnPatchGclientEnv() (
  local envFile="/tmp/gclient_env_$UID"
  local sedMatch='GSHELL_ROOT\|LD_LIBRARY_PATH\|DYLD_LIBRARY_PATH\|X509_CERT_DIR\|PATH'
  local line
  if [[ -e $envFile ]] ; then

    # completely remove those nasty variables
    while read line ; do

      if [[ $line =~ ^export[[:blank:]]+([A-Za-z0-9_]+)= ]] ; then
        case "${BASH_REMATCH[1]}" in
          GSHELL_ROOT|LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|PATH|X509_CERT_DIR) line='' ;;
        esac
      fi

      [[ $line != '' ]] && echo "$line"

    done < <( cat "$envFile" ) > "${envFile}.0"
    \mv -f "${envFile}.0" "$envFile"

  fi
)

# set environment according to the provided tuple (only argument)
function AliExportVars() {

  local tuple="$1"
  local sec vsubdir vver skip

  for sec in alien root geant3 aliroot aliphysics fastjet fjcontrib ; do
    skip=0
    case $sec in
      alien) skip=1 ;;
      root)       vsubdir='ROOT_SUBDIR'       ; vver='ROOT_VER'       ;;
      geant3)     vsubdir='G3_SUBDIR'         ; vver='G3_VER'         ;;
      aliroot)    vsubdir='ALICE_SUBDIR'      ; vver='ALICE_VER'      ;;
      aliphysics) vsubdir='ALIPHYSICS_SUBDIR' ; vver='ALIPHYSICS_VER' ;;
      fastjet)    vsubdir='FASTJET_SUBDIR'    ; vver='FASTJET_VER'    ;;
      fjcontrib)  vsubdir='FJCONTRIB_SUBDIR'  ; vver='FJCONTRIB_VER'  ;;
    esac

    raw=$( AliTupleSection "$tuple" $sec )
    if [[ $? == 0 && $skip != 1 ]] ; then
      AliParseVerDir "$raw" $vsubdir $vver
      export $vsubdir
      export $vver
      unset vsubdir vver
    fi

    case $sec in

      alien)
        export ALIEN_DIR="${ALICE_PREFIX}/alien"
        export X509_CERT_DIR="${ALIEN_DIR}/globus/share/certificates"

        # AliEn source installation uses a different destination directory
        [[ -d "$X509_CERT_DIR" ]] || X509_CERT_DIR="$ALIEN_DIR/api/share/certificates"

        export GSHELL_ROOT="${ALIEN_DIR}/api"
        export PATH="${GSHELL_ROOT}/bin:${PATH}"
        export LD_LIBRARY_PATH="${GSHELL_ROOT}/lib:${LD_LIBRARY_PATH}"
        export DYLD_LIBRARY_PATH="${GSHELL_ROOT}/lib:${DYLD_LIBRARY_PATH}"

        # remove overridden variables from gclient_env_$UID
        AliAliEnPatchGclientEnv
      ;;

      root)
        if [[ $ROOT_VER != '' ]] ; then
          export ROOTSYS="${ALICE_PREFIX}/root/${ROOT_SUBDIR}/inst"
          export PATH="${ROOTSYS}/bin:${PATH}"
          export LD_LIBRARY_PATH="${ROOTSYS}/lib:${LD_LIBRARY_PATH}"
          export ROOT_VER
          if [[ -e "${ROOTSYS}/lib/ROOT.py" ]] ; then
            # PyROOT support
            export PYTHONPATH="${ROOTSYS}/lib:${PYTHONPATH}"
          fi
          export ROOT_ARCH=`root-config --arch 2> /dev/null`
        else
          unset ROOT_VER ROOT_SUBDIR
        fi
      ;;

      geant3)
        if [[ $G3_VER != '' ]] ; then
          export GEANT3DIR="${ALICE_PREFIX}/geant3/${G3_SUBDIR}/inst"
          export LD_LIBRARY_PATH="${GEANT3DIR}/lib:${LD_LIBRARY_PATH}"
        else
          unset G3_VER G3_SUBDIR
        fi
      ;;

      aliroot)
        if [[ $ALICE_VER != '' ]] ; then
          export ALICE_VER

          # this is the only variable truly needed: it is set to the installation directory
          export ALICE_ROOT="${ALICE_PREFIX}/aliroot/${ALICE_SUBDIR}/inst"

          # set for compatibility and it will stay like this unless overridden by aliphysics
          export ALICE_PHYSICS="$ALICE_ROOT"

          # export paths both for legacy and modern CMake
          export PATH="${ALICE_ROOT}/bin:${ALICE_ROOT}/bin/tgt_${ROOT_ARCH}:${PATH}"
          export LD_LIBRARY_PATH="${ALICE_ROOT}/lib:${ALICE_ROOT}/lib/tgt_${ROOT_ARCH}:${LD_LIBRARY_PATH}"
          export DYLD_LIBRARY_PATH="${ALICE_ROOT}/lib:${ALICE_ROOT}/lib/tgt_${ROOT_ARCH}:${DYLD_LIBRARY_PATH}"
        else
          unset ALICE_VER ALICE_SUBDIR
        fi
      ;;

      aliphysics)
        if [[ $ALIPHYSICS_VER != '' ]] ; then
          export ALIPHYSICS_VER
          export ALICE_PHYSICS="${ALICE_PREFIX}/aliphysics/${ALIPHYSICS_SUBDIR}/inst"
          export PATH="${ALICE_PHYSICS}/bin:${PATH}"
          export LD_LIBRARY_PATH="${ALICE_PHYSICS}/lib:${LD_LIBRARY_PATH}"
          export DYLD_LIBRARY_PATH="${ALICE_PHYSICS}/lib:${DYLD_LIBRARY_PATH}"
        else
          unset ALIPHYSICS_VER ALIPHYSICS_SUBDIR
        fi
      ;;

      fastjet)
        if [[ $FASTJET_VER != '' ]] ; then
          export FASTJET="${ALICE_PREFIX}/fastjet/${FASTJET_SUBDIR}"
          export FASTJET_VER
          if [[ -d "${FASTJET}/bin" && -d "${FASTJET}/lib" ]] ; then
            export PATH="${FASTJET}/bin:${PATH}"
            export LD_LIBRARY_PATH="${FASTJET}/lib:${LD_LIBRARY_PATH}"
          fi
        else
          unset FASTJET_VER FASTJET_SUBDIR
        fi
      ;;

      fjcontrib)
        [[ $FASTJET_VER == '' || $FJCONTRIB_VER == '' ]] && unset FJCONTRIB_VER
        unset FJCONTRIB_SUBDIR
      ;;

    esac
  done

  # optional git prompt
  if [[ "$ALICE_ENV_DONT_CHANGE_PS1" != 1 ]] ; then
    export ALIPS1="$PS1"
    export PS1='`AliPrompt`'"$PS1"
  fi

  # exported for the automatic installer
  export ALI_nAliTuple="$nAliTuple"
  export ALI_EnvScript
  export ALI_Conf

}

# prompt with current Git revision
function AliPrompt() {
  local REF=`git rev-parse --abbrev-ref HEAD 2> /dev/null`
  local COL_GIT="${Cm}git:${Cz}"
  if [ "$REF" == 'HEAD' ] ; then
    echo -e "\n${COL_GIT} ${Cy}you are not currently on any branch${Cz}"
  elif [ "$REF" != '' ] ; then
    echo -e "\n${COL_GIT} ${Cy}you are currently on branch ${Cc}${REF}${Cz}"
  fi
  echo '[AliEnv] '
}

# prints out ALICE paths
function AliPrintVars() {

  local WHERE_IS_G3 WHERE_IS_ALIROOT WHERE_IS_ROOT WHERE_IS_ALIEN \
    WHERE_IS_ALISRC WHERE_IS_ALIINST WHERE_IS_FASTJET ALIREV MSG LEN I
  local NOTFOUND="${Cr}<not found>${Cz}"

  # check if Globus certificate is expiring soon
  local CERT="$HOME/.globus/usercert.pem"
  which openssl > /dev/null 2>&1
  if [[ $? == 0 ]] ; then
    if [[ -r "$CERT" ]] ; then
      openssl x509 -in "$CERT" -noout -checkend 0 > /dev/null 2>&1
      if [[ $? == 1 ]] ; then
        MSG='Your certificate has expired'
      else
        openssl x509 -in "$CERT" -noout -checkend 604800 > /dev/null 2>&1
        if [[ $? == 1 ]] ; then
          MSG='Your certificate is going to expire in less than one week'
        fi
      fi
    else
      MSG="Cannot find certificate file $CERT"
    fi
  fi
  if [[ "$MSG" != "" ]] ; then
    echo
    echo -e "${Br}${Cw}!!! ${MSG} !!!${Cz}"
  fi

  # detect Geant3 installation path
  if [[ -f "$ALICE_PREFIX/geant3/$G3_SUBDIR/inst/lib/libgeant321.so" ]] ; then
    WHERE_IS_G3="$ALICE_PREFIX/geant3/$G3_SUBDIR"
  else
    WHERE_IS_G3="$NOTFOUND"
  fi

  # detect ROOT location
  WHERE_IS_ROOT="$NOTFOUND"
  [[ -x "$ROOTSYS/bin/root.exe" ]] && WHERE_IS_ROOT="$ROOTSYS"

  # detect AliEn location
  WHERE_IS_ALIEN="$NOTFOUND"
  [[ -x "$GSHELL_ROOT/bin/aliensh" ]] && WHERE_IS_ALIEN="$GSHELL_ROOT"

  # detect FastJet location
  if [[ -e "$FASTJET/lib/libfastjet.so" || -e "$FASTJET/lib/libfastjet.dylib" ]] ; then
    WHERE_IS_FASTJET="$FASTJET"
  else
    WHERE_IS_FASTJET="$NOTFOUND"
  fi

  # detect AliRoot Core location
  if [[ -x "${ALICE_ROOT}/bin/aliroot" || -x "${ALICE_ROOT}/bin/tgt_${ROOT_ARCH}/aliroot"  ]] ; then
    WHERE_IS_ALIROOT=$( cd "${ALICE_ROOT}/.." && pwd || dirname "$ALICE_ROOT" )
  else
    WHERE_IS_ALIROOT="$NOTFOUND"
  fi

  # detect AliPhysics location
  if [[ $( ls -1 "${ALICE_PHYSICS}/lib/"*.{so,dylib} 2>/dev/null | wc -l ) -gt 10 ]] ; then
    WHERE_IS_ALIPHYSICS=$( cd "${ALICE_PHYSICS}/.." && pwd || dirname "$ALICE_PHYSICS" )
  else
    WHERE_IS_ALIPHYSICS="$NOTFOUND"
  fi

  echo
  echo -e "  ${Cc}AliEn${Cz}          $WHERE_IS_ALIEN"
  echo -e "  ${Cc}ROOT${Cz}           $WHERE_IS_ROOT"
  if [[ "$G3_VER" != '' ]] ; then
    echo -e "  ${Cc}Geant3${Cz}         $WHERE_IS_G3"
  fi
  if [[ "$FASTJET" != '' ]] ; then
    echo -e "  ${Cc}FastJet${Cz}        $WHERE_IS_FASTJET"
  fi
  echo -e "  ${Cc}AliRoot Core${Cz}   $WHERE_IS_ALIROOT"
  if [[ "$ALIPHYSICS_VER" != '' ]] ; then
    echo -e "  ${Cc}AliPhysics${Cz}     $WHERE_IS_ALIPHYSICS"
  fi
  echo

}

# separates version from directory, if tuple component is expressed in the form directory(version);
# if no (version) is provided, dir and version are set to the same value
function AliParseVerDir() {
  local verAndDir="$1"
  local dirVar="$2"
  local verVar="$3"
  local cmd=''
  if [[ $verAndDir =~ ^([^\(]+)\((.+)\)$ ]] ; then
    cmd="$dirVar='${BASH_REMATCH[1]}' ; $verVar='${BASH_REMATCH[2]}'"
  else
    cmd="$dirVar='$verAndDir' ; $verVar='$verAndDir'"
  fi
  eval "$cmd"
}

# tries to source the first configuration file found: returns nonzero on error
function AliConf() {

  local OPT_QUIET="$1"
  local ALI_ConfFound ALI_ConfFiles
  local nAliTuple_Before="$nAliTuple"

  # normalize path to this script
  ALI_EnvScript="${BASH_SOURCE}"
  if [[ ${ALI_EnvScript:0:1} != '/' ]] ; then
    ALI_EnvScript="${PWD}/${BASH_SOURCE}"
  fi
  ALI_EnvScript=$( cd "${ALI_EnvScript%/*}" ; pwd )"/${ALI_EnvScript##*/}"

  # configuration file path: the first file found is loaded
  ALI_ConfFiles=( "${ALI_EnvScript%.*}.conf" "$HOME/.alice-env.conf" )
  for ALI_Conf in "${ALI_ConfFiles[@]}" ; do
    if [[ -r "$ALI_Conf" ]] ; then
      source "$ALI_Conf" > /dev/null 2>&1
      ALI_ConfFound=1
      break
    fi
  done

  if [[ $ALI_ConfFound != 1 ]] ; then
    # no configuration file found: create a default one
    echo -e "${Cy}No configuration file found.${Cz}"
    echo

    ALI_Conf="${ALI_ConfFiles[0]}"
    cat > "$ALI_Conf" <<_EoF_
#!/bin/bash

# Automatically created by alice-env.sh on $( LANG=C date )

#
# Software tuples: they start from 1 (not 0) and must be consecutive.
#
# Format (you can also type it on a single long line):
#   AliTuple[n]='root=<rootver> geant3=<geant3ver> aliroot=<alirootver> \\
#                aliphysics=<aliphysicsver> fastjet=<fjver> fjcontrib=<fjcontribver>'
#
# Note: FastJet and FJContrib are optional.
#

# No FastJet
AliTuple[1]='root=v5-34-18 geant3=v1-15a aliroot=master aliphysics=master'

# FastJet 3
#AliTuple[2]='root=v5-34-18 geant3=v1-15a aliroot=master aliphysics=master \\
#             fastjet=3.0.6 fjcontrib=1.012'

# You can add more tuples
#AliTuple[3]='...'

# Default software tuple (selected when running "source alice-env.sh -n")
export nAliTuple=1
_EoF_

    if [[ $? != 0 ]] ; then
      echo -e "${Cr}Unable to create default configuration:${Cz}"
      echo -e "  ${Cc}${ALI_Conf}${Cz}" ; echo
      echo -e "${Cr}Check your permissions.${Cz}"
      return 2
    else
      echo "A default one has been created. Find it at:"
      echo -e "  ${Cc}${ALI_Conf}${Cz}" ; echo
      echo "Edit it according to your needs, then source the environment again."
      return 1
    fi
  fi

  if [[ ${#AliTuple[@]} == 0 ]] ; then
    if [[ ${#TRIAD[@]} != 0 ]] ; then
      # configuration is in the old format: migrate it to the new one
      AliConfMigrate
      if [[ $? == 0 ]] ; then
        return 1  # migration successful
      else
        return 3 # migration unsuccessful
      fi
    else
      echo -e "${Cy}No ALICE software tuples found in config file $ALI_Conf, aborting.${Cz}"
      return 2
    fi
  fi

  # if a tuple was set before loading env, restore it
  [[ "$nAliTuple_Before" != '' ]] && export nAliTuple="$nAliTuple_Before"

  # auto-detect the ALICE_PREFIX
  export ALICE_PREFIX="${ALI_EnvScript%/*}"
  if [[ "$OPT_QUIET" != 1 ]] ; then
    echo -e "\nUsing config file ${Cc}${ALI_Conf}${Cz}"
    echo -e "ALICE software directory is ${Cc}${ALICE_PREFIX}${Cz}"
  fi

  return 0
}

# migrates old "triads" file to the new format: one day we will remove this function!
function AliConfMigrate() {
  local raw
  local oldIfs="$IFS"
  IFS=''
  local pat_comment='^[[:blank:]]*#'
  local pat_triad='([[:blank:]]*)TRIAD(\[[0-9]+\])=(.*)'
  local ptriad ptuple pt pcount pfail pfj pfc
  local ALI_ConfOld=${ALI_Conf}.old_triads
  local ALI_ConfNew=${ALI_Conf}.new_tuples
  while read raw ; do
    if [[ $raw =~ $pat_comment ]] ; then
      # comments untouched
      echo "${raw}"
    elif [[ $raw =~ $pat_triad ]] ; then
      ptuple="${BASH_REMATCH[1]}AliTuple${BASH_REMATCH[2]}='"
      eval "ptriad=${BASH_REMATCH[3]}"
      if [[ $? != 0 ]] ; then
        pfail=1
        break
      fi
      IFS="$oldIfs"
      ptriad=$( echo $ptriad )
      pcount=0
      for pt in $ptriad ; do
        let pcount++
        case $pcount in
          1)
            # ROOT
            ptuple="${ptuple}root=${pt} "
          ;;
          2)
            # Geant3
            ptuple="${ptuple}geant3=${pt} "
          ;;
          3)
            # AliRoot -> AliRoot + AliPhysics
            ptuple="${ptuple}aliroot=${pt} aliphysics=${pt} "
          ;;
          4)
            # FastJet
            pfj=${pt%%_*}
            pfc=${pt#*_}
            if [[ $pfj == $pt ]] ; then
              # no FJContrib
              ptuple="${ptuple}fastjet=${pt}"
            else
              # FastJet + FJContrib
              ptuple="${ptuple}fastjet=${pfj} fjcontrib=${pfc}"
            fi
          ;;
        esac
      done
      IFS=''
      ptuple="${ptuple}'"
      echo "${ptuple}"
    else
      echo "${raw}"
    fi
  done < <( cat "$ALI_Conf" | sed -e 's/^\([^#]*\)N_TRIAD=/\1nAliTuple=/g' ) > "${ALI_ConfNew}"
  IFS="$oldIfs"

  if [[ $pfail != 1 && -s "$ALI_Conf" && -s "$ALI_ConfNew" && ! -e "$ALI_ConfOld" ]] ; then
    \mv -f "${ALI_Conf}" "${ALI_ConfOld}"
    \mv -f "${ALI_ConfNew}" "${ALI_Conf}"
    echo -e "${Cg}Configuration file format has changed!${Cz}"
    echo -e "${Cg}We have updated ${Cc}${ALI_Conf}${Cg} to the new format automatically.${Cz}"
    echo
    echo -e "${Cg}Old file has been kept in ${Cc}${ALI_ConfOld}${Cg}.${Cz}"
    echo
    echo -e "${By}${Cb}!!! Important: environment has not been loaded this time !!!${Cz}"
    echo -e "  ${Cb}-${Cy} open ${Cb}${ALI_Conf}${Cy} and check if everything is OK${Cz}"
    echo -e "  ${Cb}-${Cy} refer to the ${Cb}installation manual${Cy} to read about the update${Cz}"
    echo -e "  ${Cb}-${Cy} if something is wrong, restore the backup ${Cb}${ALI_ConfOld}${Cy}" \
            "and edit it manually${Cz}"
    echo -e "  ${Cb}-${Cy} re-source ${Cb}${ALI_EnvScript}${Cy} to load the environment${Cz}"
    return 0
  fi

  \rm -f "${ALI_ConfNew}"
  echo -e "${Cr}Configuration file format has changed.${Cz}"
  echo -e "${Cr}However, we could not update ${Cb}${ALI_Conf}${Cr} automatically.${Cz}"
  echo -e "${Cr}Please refer to the ${Cb}installation manual${Cr} and update it manually.${Cz}"

  return 1
}

# updates this very file, if necessary; return codes:
#   0: nothing done
#   42: updated and changed, must re-source
#   1-9: no update, not an error
#   10-20: no update, an error occurred
# if you want to force-update:
#   AliUpdate 2
function AliUpdate() {

  local DefUpdUrl='https://raw.githubusercontent.com/dberzano/cern-alice-setup/master/alice-env.sh'
  local UpdUrl=${ALICE_ENV_UPDATE_URL:-${DefUpdUrl}}
  local UpdStatus="${ALICE_PREFIX}/.alice-env.updated"
  local UpdTmp="${ALICE_PREFIX}/.alice-env.sh.new"
  local UpdBackup="${ALICE_PREFIX}/.alice-env.sh.old"
  local UpdLastUtc=$( cat "$UpdStatus" 2> /dev/null )
  UpdLastUtc=$( expr "$UpdLastUtc" + 0 2> /dev/null || echo 0 )
  local UpdNowUtc=$( date -u +%s )
  local UpdDelta=$(( UpdNowUtc - UpdLastUtc ))
  local UpdDeltaThreshold=5400  # update every 1.5 hours

  touch "$UpdTmp" 2> /dev/null || return 15  # cannot write

  if [ $UpdDelta -ge $UpdDeltaThreshold ] || [ "$1" == 2 ] ; then
    \rm -f "$UpdTmp" || return 11
    curl -sL --max-time 5 "$UpdUrl" -o "$UpdTmp"
    if [ $? == 0 ] ; then
      echo $UpdNowUtc > "$UpdStatus"
      if ! cmp -s "$ALI_EnvScript" "$UpdTmp" ; then
        \cp -f "$ALI_EnvScript" "$UpdBackup" || return 12
        \mv "$UpdTmp" "$ALI_EnvScript" || return 13
        return 42  # updated ok, must resource
      else
        return 1  # no change
      fi
    else
      return 14  # dl failed
    fi
  fi

  return 0  # noop
}

# main function: takes parameters from the command line
function AliMain() {

  local C T R
  local OPT_QUIET=0
  local OPT_NONINTERACTIVE=0
  local OPT_CLEANENV=0
  local OPT_DONTUPDATE=0
  local OPT_FORCEUPDATE=0
  local ARGS=("$@")
  local queryAliTuple

  # parse command line options
  while [[ $# -gt 0 ]] ; do
    case "$1" in
      -q) OPT_QUIET=1 ;;
      -v) OPT_QUIET=0 ;;
      -n)
        OPT_NONINTERACTIVE=1
        if [[ $2 =~ ^[0-9]+$ ]] ; then
          nAliTuple=$(( $2 ))
          [[ $nAliTuple == 0 ]] && unset nAliTuple
          shift
        fi
      ;;
      -m)
        OPT_NONINTERACTIVE=1
        queryAliTuple="$2"
        shift
      ;;
      -i) OPT_NONINTERACTIVE=0 ;;
      -c) OPT_CLEANENV=1; ;;
      -k) OPT_DONTUPDATE=1 ;;
      -u) OPT_FORCEUPDATE=1 ;;
    esac
    shift
  done

  # always non-interactive and do not update when cleaning environment
  if [[ "$OPT_CLEANENV" == 1 ]] ; then
    OPT_NONINTERACTIVE=1
    OPT_DONTUPDATE=1
    nAliTuple=0
  fi

  # attempt to load configuration
  AliConf "$OPT_QUIET"
  R=$?
  if [[ $R != 0 ]] ; then
    AliCleanEnv
    return $R
  fi

  # update
  local DoUpdate
  if [[ "$OPT_DONTUPDATE" == 1 ]] ; then
    DoUpdate=0  # -k
  elif [[ "$OPT_FORCEUPDATE" == 1 ]] ; then
    DoUpdate=2  # -u
  elif [[ "$ALICE_ENV_DONT_UPDATE" == 1 ]] ; then
    DoUpdate=0
  else
    DoUpdate=1
  fi

  if [[ $DoUpdate -gt 0 ]] ; then
    AliUpdate $DoUpdate
    ALI_rv=$?
    if [[ $ALI_rv == 42 ]] ; then
      # script changed: re-source
      if [[ "$OPT_QUIET" != 1 ]] ; then
        echo -e "\n${Cg}Environment script has been updated to the latest version: reloading${Cz}"
      fi
      source "$ALI_EnvScript" "${ARGS[@]}" -k
      return $?
    elif [[ $ALI_rv -ge 10 ]] ; then
      [[ "$OPT_QUIET" != 1 ]] && echo -e "${Cy}Warning:${Cz} automatic updater returned $ALI_rv"
    fi
  fi

  # print menu if non-interactive
  [[ "$OPT_NONINTERACTIVE" != 1 ]] && AliMenu

  unset ROOT_VER G3_VER ALICE_VER ALIPHYSICS_VER FASTJET_VER FJCONTRIB_VER

  # selection by query (-m <query>) has priority over by number (-n <ntuple>)
  [[ $queryAliTuple != '' ]] && nAliTuple=$( AliTupleNumberByQuery "$queryAliTuple" )

  if [[ ! $nAliTuple =~ ^[[:digit:]]+$ || $nAliTuple -gt ${#AliTuple[@]} ]] ; then
    echo
    if [[ $queryAliTuple != '' ]] ; then
      # selection by query
      echo -e "${Cr}No tuple matches the given query: ${Cb}${queryAliTuple}${Cz}"
    else
      # selection by number
      echo -e "${Cr}Invalid tuple: ${Cb}${nAliTuple}${Cz}"
      echo -e "${Cr}Check the value of ${Cb}nAliTuple${Cr} in ${Cb}${ALI_Conf}${Cr}," \
        "or provide a correct value with \"-n <n_tuple>\"${Cz}"
    fi
    OPT_CLEANENV=1
  elif [[ $nAliTuple == 0 ]] ; then
    # same as above but with no output
    OPT_CLEANENV=1
  fi

  # cleans up the environment from previous varaiables
  AliCleanEnv

  if [[ "$OPT_CLEANENV" != 1 ]] ; then

    # number of parallel workers (on variable MJ)
    AliSetParallelMake

    # export all the needed variables
    AliExportVars "${AliTuple[$nAliTuple]}"

    # prints out settings, if requested
    [[ "$OPT_QUIET" != 1 ]] && AliPrintVars

  else
    # Those variables are not cleaned by AliCleanEnv
    AliCleanEnv --extra
    if [[ "$OPT_QUIET" != 1 ]] ; then
      echo -e "${Cy}ALICE environment variables purged${Cz}"
    fi
  fi

  # Cleans up artifacts in paths
  AliCleanPathList LD_LIBRARY_PATH
  AliCleanPathList DYLD_LIBRARY_PATH
  AliCleanPathList PATH
  AliCleanPathList PYTHONPATH

}

#
# Entry point
#

AliMain "$@"
ALI_rv=$?
# function already purged if arriving from an auto-updated script: silencing harmless errors
AliCleanEnv --final 2> /dev/null
return $ALI_rv
