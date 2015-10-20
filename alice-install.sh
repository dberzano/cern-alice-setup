#!/bin/bash

#
# alice-install.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Installs all the ALICE software on Ubuntu/Mac hopefully with the least
# possible human intervention.
#

#
# Variables
#

export NCORES=0
export BUILD_MODE='' # clang, gcc, custom-gcc
export SUPPORTED_BUILD_MODES=''
export CUSTOM_GCC_PATH='/opt/gcc'
export BUILDOPT_LDFLAGS=''
export BUILDOPT_CPATH=''
export ALIEN_INSTALL_TYPE=''
export FASTJET_PATCH_HEADERS=0
export DOWNLOAD_MODE=''
export SYSTEM_ALIEN_LIBS=
export MIN_ROOT_VER_NUM=''
export MIN_ROOT_VER_STR='all'
export LC_ALL=C
export DebugSwallow=0
export DebugDetectOs=0
export BuildType='normal'
export DontUpdateEnv=0

#
# Functions
#

# Sources environment variables
function SourceEnvVars() {
  local R UpdateFlag

  if [[ ! -r "$ALI_EnvScript" ]] ; then
    return 100
  fi

  if [[ "$1" == '-u' ]] ; then
    # Force the update now
    UpdateFlag='-u'
  else
    # By default, stop auto updating. We don't want the script to accidentally
    # self-update while installing!
    UpdateFlag='-k'
  fi

  source "$ALI_EnvScript" -n "$ALI_nAliTuple" $UpdateFlag
  R=$?
  [[ $NCORES -gt 0 ]] && MJ=$NCORES
  return $R
}

# Returns date in current timezone in a compact format
function DateTime() {
  date +%Y%m%d-%H%M%S
}

# Prints the time given in seconds in hours, minutes, seconds
function NiceTime() {
  local SS HH MM STR
  SS="$1"

  let "HH=SS / 3600"
  let "SS=SS % 3600"
  [ $HH -gt 0 ] && STR=" ${HH}h"

  let "MM=SS / 60"
  let "SS=SS % 60"
  [ $MM -gt 0 ] && STR="${STR} ${MM}m"

  [ $SS -gt 0 ] && STR="${STR} ${SS}s"
  [ "$STR" == "" ] && STR="0s"

  echo $STR

  #printf "%02dh %02dm %02ds" $HH $MM $SS
}

# Prints the command name when it is started.
#  - $1: command description
function SwallowStart() {
  local MSG OP

  OP="$1"
  shift

  MSG='*** ['"$(DateTime)"'] BEGIN OP='"$OP"' CWD='"$PWD"' CMD='"$@"' ***'
  echo -e "\n\n$MSG" >> "$OUT"
  echo -e "\n\n$MSG" >> "$ERR"

  if [[ $DebugSwallow == 1 ]] ; then
    echo
    echo -e "\033[35m CWD:>\033[34m $PWD\033[m"
    for ((i=1 ; i<=$# ; i++)) ; do
      if [[ $i == 1 ]] ; then
        echo -e "\033[35m CMD:>\033[34m ${!i}\033[m"
      else
        echo -e "\033[35m $(printf '% 3u' $((i-1))):>\033[34m   ${!i}\033[m"
      fi
    done
  fi
  echo -en "[....] $OP..."

}

# Prints command's progress with percentage and time.
#  - $1: command description
#  - $2: current percentage
#  - $3: start timestamp (seconds)
function SwallowStep() {
  local TS_START OP MSG PCT PCT_FMT MODE

  if [ "$1" == '--pattern' ] || [ "$1" == '--percentage' ] ; then
    MODE="$1"
    shift
  fi

  OP="$1"
  PCT=$2
  TS_START=${3}

  let TS_DELTA=$(date +%s)-TS_START

  # Prints progress
  echo -ne '\r                                                  \r'
  if [ "$MODE" == '--pattern' ] ; then
    #local PROG_PATTERN=( '.   ' '..  ' '... ' '....' ' ...' '  ..' '   .' '    ' )
    local PROG_PATTERN=(   \
      'o...' 'O...' 'o...' \
      '.o..' '.O..' '.o..' \
      '..o.' '..O.' '..o.' \
      '...o' '...O' '...o' \
      '..o.' '..O.' '..o.' \
      '.o..' '.O..' '.o..' \
    )
    local PROG_IDX=$(( $PCT % ${#PROG_PATTERN[@]} ))
    echo -ne "[\033[34m${PROG_PATTERN[$PROG_IDX]}\033[m] $OP \033[36m$(NiceTime $TS_DELTA)\033[m"
  else
    PCT_FMT=$( printf "%3d%%" $PCT )
    echo -ne "[\033[34m$PCT_FMT\033[m] $OP \033[36m$(NiceTime $TS_DELTA)\033[m"
  fi

}

# Prints the command with its exit status (OK or FAILED) and time taken.
#  - $1: command description
#  - $2: the exit code of command
#  - $3: start timestamp (seconds) (optional)
#  - $4: end timestamp (seconds) (optional)
#  - $@: the command (from $5 on)
function SwallowEnd() {

  local TS_END TS_START OP MSG RET

  OP="$1"
  FATAL=$2
  RET=$3
  TS_START=${4-0}  # defaults to 0
  TS_END=${5-0}

  # After this line, $@ will contain the command
  shift 5

  let TS_DELTA=TS_END-TS_START

  # Prints success (green OK) or fail (red FAIL). In case FATAL=0
  # prints a warning (yellow SKIP) instead of an error
  echo -ne '\r'
  if [ $RET == 0 ]; then
    echo -ne '[ \033[32mOK\033[m ]'
  elif [ $FATAL == 0 ]; then
    echo -ne '[\033[33mSKIP\033[m]'
  else
    echo -ne '[\033[31mFAIL\033[m]'
  fi
  echo -ne " ${OP}"

  # Prints time only if greater than 1 second
  if [ $TS_DELTA -gt 1 ]; then
    echo -e " \033[36m$(NiceTime $TS_DELTA)\033[m"
  else
    echo "   "
  fi

  # On the log files (out, err)
  MSG='*** ['"$(DateTime)"'] END OP='"$OP"' CWD='"$PWD"' ERR='"$RET"' CMD='"$@"' ***'
  echo -e "$MSG" >> "$OUT"
  echo -e "$MSG" >> "$ERR"

  return $RET
}

# Sends everything to a logfile
function Swallow() {

  local MSG ERRMSG RET TSSTART TSEND DELTAT FATAL OP

  # Options given?
  FATAL=0
  ERRMSG=''
  OKMSG=''
  while [[ "${1:0:1}" == '-' ]] ; do
    case "$1" in
      -f|--fatal)
        FATAL=1
      ;;
      --error-msg)
        ERRMSG="$2"
        shift
      ;;
      --success-msg)
        OKMSG="$2"
        shift
      ;;
    esac
    shift
  done

  OP="$1"
  shift

  SwallowStart "$OP" "$@"
  TSSTART=$(date +%s)

  "$@" >> "$OUT" 2>> "$ERR"
  RET=$?

  TSEND=$(date +%s)
  SwallowEnd "$OP" $FATAL $RET $TSSTART $TSEND "$@"

  if [[ $RET != 0 && $FATAL == 1 ]]; then
    if [[ "$ERRMSG" != '' ]] ; then
      # Produce a custom error message instead of log output
      echo
      echo -e "\033[31m${ERRMSG}\033[m"
      echo
    else
      LastLogLines -e "$OP"
    fi
    exit 1
  elif [[ $RET == 0 && "$OKMSG" != '' ]]; then
    echo
    echo -e "\033[32m${OKMSG}\033[m"
    echo
  fi

  return $RET
}

# Prints the last lines of both log files
function LastLogLines() {
  local LASTLINES=20
  local ISERROR=0

  if [ "$1" == "-e" ]; then
    echo ""
    echo -e "\033[41m\033[1;37mOperation \"$2\" ended with errors\033[m"
  fi

  echo ""
  echo -e "\033[33m=== Last $LASTLINES lines of stdout -- $SWALLOW_LOG.out ===\033[m"
  tail -n$LASTLINES "$SWALLOW_LOG".out
  echo ""
  echo -e "\033[33m=== Last $LASTLINES lines of stderr -- $SWALLOW_LOG.err ===\033[m"
  tail -n$LASTLINES "$SWALLOW_LOG".err
  echo ""
  echo -e "\033[31m=== Possible errors ===\033[m"
  cat "$SWALLOW_LOG".err | grep -B 2 'error:' --color
  echo ""

  [ "$1" == "-e" ] && ShowBugReportInfo
}

# Echoes a colored banner
function Banner() {
  echo ""
  echo -e '\033[33m'"$1"'\033[m'
}

# Prepares information for bug report
function PrepareBugReport() {

  # Source environment variables (non-fatal)
  SourceEnvVars >> $OUT 2>&1

  # Some environment variables
  (
    echo "=== BUILD ENVIRONMENT ==="
    echo "PATH=$PATH"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
    echo "PYTHONPATH=$PYTHONPATH"
    echo "uname -a: `uname -a`"
    if [[ -r /etc/lsb-release ]] ; then
      echo "*** /etc/lsb-release ***"
      cat /etc/lsb-release
    fi
    if [[ -r /etc/redhat-release ]] ; then
      echo "*** /etc/redhat-release ***"
      cat /etc/redhat-release
    fi

    echo "=== ROOT COMPILATION FLAGS ==="
    local rootconf=( --f77 --cc --cxx --ld --features --cflags --auxcflags --ldflags )
    for rc in "${rootconf[@]}" ; do
      echo "root-config ${rc}: `root-config ${rc} 2> /dev/null`"
    done

    echo "=== VERSIONS OF EXTERNAL TOOLS ==="
    local progs=( 'gcc -v' 'g++ -v' 'ld -v' 'gfortran -v' \
                  'clang -v' 'clang++ -v' \
                  'make -v' 'cmake --version' \
                  'libtool -V' 'autoconf --version' 'automake --version' \
                  'git --version' 'brew -v' 'port version' 'fink --version' )
    for pa in "${progs[@]}" ; do
      pr=${pa%% *}
      echo "*** ${pr} ***"
      w=$( which $pr 2> /dev/null )
      if [[ $? == 0 ]] ; then
        echo "Location: ${w}"
        ${pa} 2>&1
      else
        echo '<not found>'
      fi
    done

    echo "=== ALICE SOFTWARE VERSIONS ==="
    echo "ROOT: $ROOT_VER"
    echo "Geant3: $G3_VER"
    echo "AliRoot Core: $ALICE_VER"
    echo "AliPhysics: $ALICEPHYSICS_VER"
    echo "FastJet: $FASTJET_VER"
    echo "FJ Contrib: $FJCONTRIB_VER"

    echo "=== DISK SPACE ==="
    df

    echo "=== MOUNTED VOLUMES ==="
    mount

  ) >> $OUT 2>&1

}

# Shows a message reminding user to send the log files when asking for support
function ShowBugReportInfo() {
  echo ""
  echo -e "\033[41m\033[1;37mWhen asking for support, please send an email attaching the following file(s):\033[m"
  echo ""
  [ -s "$ERR" ] && echo "  $ERR"
  [ -s "$OUT" ] && echo "  $OUT"
  echo ""
  echo -e "\033[41m\033[1;37mNote:\033[m should you be concerned about private information contained"
  echo "      in the logs, you can edit them before sending."
  echo ""
}

# Module to fetch and compile ROOT
function ModuleRoot() {

  local ForceCleanSlate="$1"

  Banner 'Installing ROOT...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking that we are not using an external ROOT' [ "$ROOT_VER" != EXTERNAL ] || return

  Swallow --fatal \
    --error-msg "ROOT $ROOT_VER is not supported on your platform: use at least $MIN_ROOT_VER_STR." \
    "Ensuring ROOT $ROOT_VER is OK for your platform" \
    [ $( ConvertVersionStringToNumber "$ROOT_VER" ) -ge $MIN_ROOT_VER_NUM ]

  # ROOT variables: only ${ALICE_PREFIX} and ${ROOTSYS} needed

  local RootGit="${ALICE_PREFIX}/root/git"
  local RootBase=$( dirname "${ROOTSYS}" )
  local RootInst="$ROOTSYS"
  local RootSrc="${RootBase}/src"
  local RootTmp="${RootBase}/build"
  local RootGitUrl='https://github.com/alisw/root'
  local RootGitRemote='aliceroot'

  Swallow -f 'Creating ROOT directory' mkdir -p "$RootBase"

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'only' ]] ; then

    #
    # Downloading ROOT from Git
    #

    Swallow -f 'Creating ROOT Git local directory' mkdir -p "$RootGit"
    Swallow -f 'Moving into ROOT Git local directory' cd "$RootGit"
    if [[ ! -e "$RootGit/.git" ]] ; then
      SwallowProgress -f --pattern 'Cloning ROOT Git repository (might take some time)' \
        git clone "$RootGitUrl" .
    fi

    # Setting a public and private remote
    Swallow -f 'Setting ROOT ALICE remote URL' \
      GitForceSetRemote "$RootGitRemote" "$RootGitUrl" "$RootGitUrl"

    SwallowProgress -f 'Synchronizing Git clone' \
      GitSync "$RootGitRemote"

    # Updating from the former installation schema (no inst and build dir)
    if [[ -e "${RootBase}/LICENSE" ]] ; then
      Swallow -f 'Clean up directory from the old installation schema' rm -rf "${RootBase}"
    fi

    # Shallow copy with git-new-workdir
    if [[ ! -d "${RootSrc}/.git" ]] ; then
      rmdir "$RootSrc" > /dev/null 2>&1
      SwallowProgress -f --pattern \
        "Creating a local clone for version ${ROOT_VER}" \
        GitNewWorkdir "$RootGit" "$RootSrc" "$RootGitRemote" "$ROOT_VER"
    fi

    Swallow -f "Moving to local clone for version ${ROOT_VER}" cd "$RootSrc"
    Swallow -f "Checking out ROOT version ${ROOT_VER}" \
      GitCheckoutTrack "$ROOT_VER" "$RootGitRemote"

    if [[ $ForceCleanSlate == 1 ]] ; then
      Swallow -f "Forcing hard reset to remote ${ROOT_VER}" \
        GitResetHard "$RootGitRemote" "$ROOT_VER"
      Swallow -f 'Forcing cleanup of working directory' git clean -f -d
    elif [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      SwallowProgress -f --pattern "Updating ROOT branch ${ROOT_VER}" git pull --rebase
    fi

  fi # end download

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'no' ]] ; then

    #
    # Build ROOT
    #

    # Build type. Note that ROOT, if configured with ./configure (and not CMake), does not allow us
    # to be flexible with respect to build options. We will need to override them when running make
    # by passing the additional OPT= variable. The following options match the build options for
    # AliRoot Core and AliPhysics for consistency
    case $BuildType in
      debug)
        BuildCfgFlags='--build=debug'
        BuildMakeFlags='-O0 -g'
      ;;
      normal)
        BuildCfgFlags='--build=debug'
        BuildMakeFlags='-O2 -g'
      ;;
      optimized)
        BuildCfgFlags=''
        BuildMakeFlags='-O3'
      ;;
    esac

    # Configuration options (including installation prefixes)
    local ConfigOpts="--with-pythia6-uscore=SINGLE \
      --with-alien-incdir=${GSHELL_ROOT}/include \
      --with-alien-libdir=${GSHELL_ROOT}/lib \
      --with-monalisa-incdir="${GSHELL_ROOT}/include" \
      --with-monalisa-libdir="${GSHELL_ROOT}/lib" \
      --with-xrootd=${GSHELL_ROOT} \
      --enable-builtin-ftgl \
      --enable-minuit2 \
      --enable-roofit \
      --enable-soversion \
      --disable-bonjour \
      --disable-rfio \
      --disable-castor \
      --enable-builtin-freetype $BuildCfgFlags \
      --prefix=${RootInst} \
      --incdir=${RootInst}/include \
      --libdir=${RootInst}/lib \
      --datadir=${RootInst} \
      --etcdir=${RootInst}/etc"

    # Are --disable-fink and --enable-cocoa available (OS X only)?
    if [[ "`uname`" == 'Darwin' ]] ; then
      if [[ `./configure --help 2>/dev/null|grep -c finkdir` == 1 ]] ; then
        ConfigOpts="$ConfigOpts --disable-fink"
      fi
      if [[ `./configure --help 2>/dev/null|grep -c cocoa` == 1 ]] ; then
        ConfigOpts="$ConfigOpts --enable-cocoa"
      fi
    fi

    case "$BUILD_MODE" in

      gcc)
        ConfigOpts="--with-f77=$( which gfortran ) \
          --with-cc=$( which gcc ) \
          --with-cxx=$( which g++ ) \
          --with-ld=$( which g++ ) $ConfigOpts"
      ;;

      clang)
        ConfigOpts="--with-clang \
          --with-f77=$( which gfortran ) \
          --with-cc=$( which clang ) \
          --with-cxx=$( which clang++ ) \
          --with-ld=$( which clang++ ) $ConfigOpts"
      ;;

      custom-gcc)
        ConfigOpts="--with-f77=$CUSTOM_GCC_PATH/bin/gfortran \
          --with-cc=$CUSTOM_GCC_PATH/bin/gcc \
          --with-cxx=$CUSTOM_GCC_PATH/bin/g++ \
          --with-ld=$CUSTOM_GCC_PATH/bin/g++ $ConfigOpts"
      ;;

    esac

    # Building out-of-source with configure (no CMake)
    Swallow -f 'Creating build directory' mkdir -p "$RootTmp"
    Swallow -f 'Moving into build directory' cd "$RootTmp"
    SwallowProgress -f --pattern 'Configuring ROOT' "${RootSrc}/configure" $ConfigOpts

    # Before building ROOT, make sure we have some required features enabled
    Swallow --fatal --error-msg \
      'ROOT was configured with no OpenGL support: check you have the OpenGL libraries installed.' \
      'Ensuring ROOT will be built with OpenGL support' \
      RootConfiguredWithFeature opengl
    Swallow --fatal --error-msg \
      'ROOT did not find AliEn: make sure it is installed before compiling ROOT.' \
      'Ensuring ROOT will be built with AliEn support' \
      RootConfiguredWithFeature alien

    local AppendLDFLAGS AppendCPATH
    [[ "$BUILDOPT_LDFLAGS" != '' ]] && AppendLDFLAGS="LDFLAGS=$BUILDOPT_LDFLAGS"
    [[ "$BUILDOPT_CPATH" != '' ]] && AppendCPATH="CPATH=$BUILDOPT_CPATH"

    export CCACHE_BASEDIR="$RootBase"

    SwallowProgress -f --pattern 'Building ROOT' \
      make -j$MJ $AppendLDFLAGS $AppendCPATH OPT="$BuildMakeFlags"

    Swallow -f 'Cleaning ROOT installation directory' rm -rf "${RootInst}"
    SwallowProgress -f --pattern 'Installing ROOT' make -j$MJ install

    unset CCACHE_BASEDIR

  fi # end build

}

# Module to fetch and compile Geant3
function ModuleGeant3() {

  local ForceCleanSlate="$1"

  Banner 'Installing Geant3...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking if Geant3 support has been requested' [ "$G3_VER" != '' ] || return
  Swallow 'Checking that we are not using an external Geant3' [ "$G3_VER" != EXTERNAL ] || return

  # Geant3 variables: only ${ALICE_PREFIX} and ${G3_VER} needed
  local Geant3Git="${ALICE_PREFIX}/geant3/git"
  local Geant3Base="${ALICE_PREFIX}/geant3/${G3_SUBDIR}"
  local Geant3Inst="${Geant3Base}/inst"
  local Geant3Src="${Geant3Base}/src"
  local Geant3Tmp="${Geant3Base}/build"

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'only' ]] ; then

    #
    # Git clone of Geant3
    #

    Swallow -f "Creating Geant3 Git clone directory" mkdir -p "$Geant3Git"
    Swallow -f "Moving to the Geant3 Git clone directory" cd "$Geant3Git"

    if [[ ! -d "${Geant3Git}/.git" ]] ; then
      SwallowProgress -f --pattern 'Cloning Geant3 Git repository' \
        git clone http://root.cern.ch/git/geant3.git .
    fi

    SwallowProgress -f 'Synchronizing Git clone' \
      GitSync origin

    # Updating from the former installation schema (no inst and build dir)
    if [[ -e "${Geant3Base}/README" ]] ; then
      Swallow -f 'Clean up directory from the old installation schema' rm -rf "${Geant3Base}"
    fi

    # Shallow copy with git-new-workdir
    if [[ ! -d "${Geant3Src}/.git" ]] ; then
      rmdir "$Geant3Src" > /dev/null 2>&1
      SwallowProgress -f --pattern \
        "Creating a local clone for version ${G3_VER}" \
        git-new-workdir "$Geant3Git" "$Geant3Src" "$G3_VER"
    fi

    Swallow -f "Moving to local clone for version ${G3_VER}" cd "$Geant3Src"
    Swallow -f "Checking out Geant3 version ${G3_VER}" git checkout "$G3_VER"

    if [[ $ForceCleanSlate == 1 ]] ; then
      Swallow -f "Forcing hard reset to remote ${G3_VER}" GitResetHard origin "$G3_VER"
      Swallow -f 'Forcing cleanup of working directory' git clean -f -d
    elif [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      SwallowProgress -f --pattern "Updating Geant3 branch ${G3_VER}" git pull --rebase
    fi

  fi # end download

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'no' ] ; then

    #
    # Build Geant3
    #

    Swallow -f "Moving to the local Git clone for Geant3 version $G3_VER" cd "$Geant3Src"

    export CCACHE_BASEDIR="$Geant3Base"

    if [[ -e Makefile ]] ; then

      # Prior to version ~v2-0: no CMake, only make
      Swallow -f 'Preparing build directory' rsync -ca --exclude '**/.git' "$Geant3Src"/ "$Geant3Tmp"/
      Swallow -f 'Move to the temporary build directory' cd "$Geant3Tmp"
      SwallowProgress -f --pattern 'Building Geant3' make -j$MJ

      # Fake installation
      Swallow -f 'Cleaning up installation path' rm -rf "$Geant3Inst"
      Swallow -f 'Creating installation directory' mkdir -p "${Geant3Inst}/include/TGeant3/"
      Swallow -f 'Installing header files' \
        cp "${Geant3Tmp}/TGeant3/"*.h "${Geant3Inst}/include/TGeant3/"
      Swallow -f 'Installing libraries' \
        rsync -a "${Geant3Tmp}/lib/tgt_$(root-config --arch)/" "${Geant3Inst}/lib/"

    else

      # From ~v2-0: CMake
      Swallow -f 'Creating build directory' mkdir -p "$Geant3Tmp"
      Swallow -f 'Moving to the temporary build directory' cd "$Geant3Tmp"

      # Note: ROOTSYS can be also passed as -DROOT_DIR, but ROOT paths must be set in the env :-(
      SwallowProgress -f --pattern 'Bootstrapping Geant3' \
        cmake "$Geant3Src" -DCMAKE_INSTALL_PREFIX="$Geant3Inst"

      SwallowProgress -f --percentage "Building Geant3 ${G3_VER}" make -j$MJ
      Swallow -f 'Removing previous installation directory' rm -rf "$Geant3Inst"
      SwallowProgress -f --percentage "Installing Geant3 ${G3_VER}" make -j$MJ install

    fi

    unset CCACHE_BASEDIR

  fi

}

# Module to fetch and compile FastJet
function ModuleFastJet() {

  local MinFastJetVerStr='v3.0.6'
  local MinFastJetVerNum=$( ConvertVersionStringToNumber "$MinFastJetVerStr" )

  # FastJet versions will be downloaded from tarballs on the official website
  local FASTJET_URL_PATTERN='http://fastjet.fr/repo/fastjet-%s.tar.gz'
  local FASTJET_TARBALL='source.tar.gz'

  # FastJet contrib
  local FJCONTRIB_URL_PATTERN='http://fastjet.hepforge.org/contrib/downloads/fjcontrib-%s.tar.gz'
  local FJCONTRIB_TARBALL='contrib.tar.gz'

  Banner 'Installing FastJet...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking if FastJet support has been requested' [ "$FASTJET_VER" != '' ] || return

  Swallow --fatal \
    --error-msg "FastJet $FASTJET_VER is not supported: use at least $MinFastJetVerStr." \
    "Ensuring FastJet $FASTJET_VER is supported" \
    [ $( ConvertVersionStringToNumber "$FASTJET_VER" ) -ge $MinFastJetVerNum ]

  Swallow --fatal \
    --error-msg 'FastJet contrib is mandatory when installing FastJet.' \
    'Ensuring FastJet contrib is enabled' \
    [ "$FJCONTRIB_VER" != '' ]

  # FastJet variables: from $FASTJET (no build directory)
  local FastJetBase="$( dirname "$FASTJET" )"
  local FastJetInst="$FASTJET"
  local FastJetSrc="${FastJetBase}/src"

  Swallow -f 'Creating FastJet directory' mkdir -p "$FastJetSrc"

  if [[ -d "${FastJetBase}/bin" || -d "${FastJetBase}/lib" || -d "${FastJetBase}/include" ]] ; then
    Swallow -f 'Removing FastJet from old installation schema' \
      rm -rf "$FastJetBase"/{bin,lib,include}
  fi

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'only' ]] ; then

    #
    # Download, unpack and patch FastJet tarball
    #

    Swallow -f 'Moving into FastJet source directory' cd "$FastJetSrc"

    if [[ ! -e "$FASTJET_TARBALL" ]] ; then
      SwallowProgress -f --percentage "Downloading FastJet v$FASTJET_VER" \
        Dl $( printf "$FASTJET_URL_PATTERN" "$FASTJET_VER" ) "$FASTJET_TARBALL"
    fi

    if [[ ! -f fastjet-"$FASTJET_VER"/configure ]] ; then
      Swallow -f 'Removing old FastJet source directory' rm -rf fastjet-"$FJCONTRIB_VER"
      SwallowProgress -f --pattern 'Unpacking FastJet tarball' \
        tar xzvvf "$FASTJET_TARBALL"
    fi

    if [[ $FJCONTRIB_VER != '' ]] ; then

      # Optional FastJet contrib

      if [[ ! -e "$FJCONTRIB_TARBALL" ]] ; then
        SwallowProgress -f --percentage "Downloading FastJet contrib v$FJCONTRIB_VER" \
          Dl $( printf "$FJCONTRIB_URL_PATTERN" "$FJCONTRIB_VER" ) "$FJCONTRIB_TARBALL"
      fi

      if [[ ! -f fjcontrib-"$FJCONTRIB_VER"/configure ]] ; then
        Swallow -f 'Removing old FastJet contrib source directory' rm -rf fjcontrib-"$FJCONTRIB_VER"
        SwallowProgress -f --pattern 'Unpacking FastJet contrib tarball' \
          tar xzvvf "$FJCONTRIB_TARBALL"
      fi

    fi

    if [[ $FASTJET_PATCH_HEADERS == 1 ]]; then

      # Patching FastJet headers: libc++ fixup

      function FastJetPatchLibcpp() {
        find . -name '*.h' -or -name '*.hh' | \
          while read F; do
            echo '#include <cstdlib>' > "$F.0" && \
              cat "$F" | grep -v '#include <cstdlib>' >> "$F.0" && \
              \mv -f "$F.0" "$F" || return 1
          done
      }

      Swallow -f 'Patching FastJet headers: libc++ workaround' FastJetPatchLibcpp
      unset FastJetPatchLibcpp

    fi

  fi

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'no' ]] ; then

    #
    # Build FastJet
    #

    Swallow -f 'Moving into FastJet build directory' cd "${FastJetSrc}/fastjet-$FASTJET_VER"

    case "$BUILD_MODE" in
      gcc)
        export CXX=$( which g++ )
      ;;
      clang)
        export CXX=$( which clang++ )
      ;;
      custom-gcc)
        export CXX=$CUSTOM_GCC_PATH/bin/g++
      ;;
    esac

    # Build type: optimization level and debug symbols
    case $BuildType in
      debug)
        FastJetOptDbgFlags='-O0 -g'
      ;;
      normal)
        FastJetOptDbgFlags='-O2 -g'
      ;;
      optimized)
        FastJetOptDbgFlags='-O3'
      ;;
    esac

    export CCACHE_BASEDIR="$FastJetBase"

    # Exporting this variable is relevant to FastJet's configure, while FJ contrib's Makefile picks
    # it directly from the environment
    export CXXFLAGS="${BUILDOPT_LDFLAGS} ${FastJetOptDbgFlags} -lgmp"

    SwallowProgress -f --pattern 'Configuring FastJet' \
      ./configure --enable-cgal --prefix="$FastJetInst"

    SwallowProgress -f --pattern 'Building FastJet' make -j$MJ
    Swallow -f 'Removing old FastJet installation' rm -rf "$FastJetInst"
    SwallowProgress -f --pattern 'Installing FastJet' make -j$MJ install

    if [[ "$FJCONTRIB_VER" != '' ]] ; then

      #
      # Build FastJet contrib (optional)
      #

      Swallow -f 'Sourcing envvars' SourceEnvVars
      Swallow -f 'Moving into FastJet contrib build directory' \
        cd "${FastJetSrc}/fjcontrib-$FJCONTRIB_VER"

      SwallowProgress -f --pattern 'Configuring FastJet contrib' \
        ./configure CXX="$CXX" CXXFLAGS="$CXXFLAGS"

      SwallowProgress --pattern 'Building FastJet contrib' make -j$MJ
      SwallowProgress -f --pattern 'Building FastJet contrib shared library' \
        make -j$MJ fragile-shared

      # No need to clean up old installation: already done for FastJet base package

      SwallowProgress --pattern 'Installing FastJet contrib' make install
      SwallowProgress -f --pattern 'Installing FastJet contrib shared library' \
        make fragile-shared-install

    fi

    unset CXXFLAGS CXX CCACHE_BASEDIR

  fi

}

# Function to force-set a remote in a Git repository
# $1: remote name
# $2: URL
# $3 (optional): push URL (in this case, $2 is the fetch URL)
# Returns nonzero on error
function GitForceSetRemote() (
  gitFetchUrl="$2"
  if [[ $3 != '' ]] ; then
    gitPushUrl="$3"
  else
    gitPushUrl="$gitFetchUrl"
  fi
  git remote set-url "$1" "$gitFetchUrl" || git remote add "$1" "$gitFetchUrl"
  git remote set-url --push "$1" "$gitPushUrl" || git remote add --push "$1" "$gitPushUrl"
)

# Function to checkout a local branch, if it exists. If it does not, create a
# new one and track the corresponding one from the remote
# $1: branch name
# $2: remote name
# Returns nonzero on error
function GitCheckoutTrack() (
  local branch="$1"
  local remote="$2"
  git checkout "$branch" || git checkout -b "$branch" --track "${remote}/${branch}"
)

# Works around a problem with the original git-new-workdir which is unable to
# deal properly with multiple remotes
# $1: Git reference directory
# $2: destination source
# $3: remote name
# $4: branch to checkout
function GitNewWorkdir() (
  local ref="$1"
  local src="$2"
  local remote="$3"
  local branch="$4"
  git-new-workdir "$ref" "$src" "$branch"
  GitCheckoutTrack "$branch" "$remote"
)

# Synchronizes the local Git clone with the remote copy.
# $1: remote name
# Returns nonzero on error
function GitSync() (
  local remote="$1"
  git remote update "$remote" --prune && \
    git fetch "$remote" && \
    git fetch "$remote" --tags
)

# Force-reset to either a remote head or tag.
# $1: remote name
# $2: version name
# Returns nonzero on error
function GitResetHard() (
  local remote="$1"
  local vers="$2"
  git reset --hard "${remote}/${vers}" || git reset --hard "${vers}"
)

# Module to fetch, update and compile AliRoot
function ModuleAliRoot() {

  local GenerateDoc="$1"
  local ForceCleanSlate="$2"
  local Pedantic="$3"

  local CMakeCxxFlags

  Banner 'Installing AliRoot Core...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking that we are not using an external AliRoot Core' \
    [ "$ALICE_VER" != EXTERNAL ] || return

  # AliRoot variables: only ${ALICE_ROOT} needed
  # - ${ALICE_ROOT}: installation directory
  # - ${ALICE_ROOT}/../build: build directory
  # - ${ALICE_ROOT}/../src: source directory

  local AliRootBase=$( dirname "${ALICE_ROOT}" )
  local AliRootInst="$ALICE_ROOT"
  local AliRootSrc="${AliRootBase}/src"
  local AliRootTmp="${AliRootBase}/build"

  # AliRoot remote name
  local AliRootGitRemote='alicern'

  # AliRoot Git private and public URLs
  local AliRootGitUrlPub='http://git.cern.ch/pub/AliRoot'
  local AliRootGitUrlPriv='https://git.cern.ch/reps/AliRoot'

  if [[ ! -d "$AliRootTmp" ]]; then
    Swallow -f "Creating AliRoot build directory" mkdir -p "$AliRootTmp"
  fi

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'only' ]] ; then

    #
    # Download AliRoot from Git
    #

    # The directory AliRootGit contains the only Git clone pointing by default
    # to the remote Git reposiory of ALICE. All other Git clones point to this
    # directory instead
    local AliRootGit="${AliRootBase}/../git"

    Swallow -f 'Creating AliRoot Git local directory' mkdir -p "$AliRootGit"
    Swallow -f 'Moving into AliRoot Git local directory' cd "$AliRootGit"
    if [[ ! -e "$AliRootGit/.git" ]] ; then
      SwallowProgress -f --pattern \
        'Cloning AliRoot Git repository (might take some time)' \
        git clone "$AliRootGitUrlPub" .
    fi
    AliRootGit=$(cd "$AliRootGit";pwd)

    # Setting a public and private remote
    Swallow -f 'Setting ALICE Git pull/push URLs' \
      GitForceSetRemote "$AliRootGitRemote" "$AliRootGitUrlPub" "$AliRootGitUrlPriv"

    SwallowProgress -f 'Synchronizing Git clone' \
      GitSync "$AliRootGitRemote"

    # Source is ${AliRootSrc} his will be a Git directory on its own that shares
    # the object database, but with its own index. This is possible via the
    # git-new-workdir[1] script
    # [1] http://nuclearsquid.com/writings/git-new-workdir/

    # Shallow copy with git-new-workdir
    if [[ ! -d "${AliRootSrc}/.git" ]] ; then
      rmdir "$AliRootSrc" > /dev/null 2>&1  # works if dir is empty
      SwallowProgress -f --pattern \
        "Creating a shallow clone of AliRoot Core" \
        git-new-workdir "$AliRootGit" "$AliRootSrc"
    fi

    Swallow -f 'Moving into local clone' cd "$AliRootSrc"
    Swallow -f "Checking out AliRoot version ${ALICE_VER}" \
      GitCheckoutTrack "$ALICE_VER" "$AliRootGitRemote"

    if [[ $ForceCleanSlate == 1 ]] ; then
      Swallow -f "Forcing hard reset to remote ${ALICE_VER}" \
        GitResetHard "$AliRootGitRemote" "$ALICE_VER"
      Swallow -f 'Forcing cleanup of working directory' git clean -f -d
    elif [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      # if we are working on a clone made with git-new-workdir, changes in the
      # git object database will be propagated to all the sibling clones
      SwallowProgress -f --pattern \
        "Updating AliRoot $ALICE_VER from public Git" \
        git pull --rebase "$AliRootGitRemote" "$ALICE_VER"
    fi

  fi # end download

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'no' ]] ; then

    #
    # Build AliRoot
    #

    Swallow -f 'Moving into AliRoot build directory' cd "$AliRootTmp"

    # Before building AliRoot Core, make sure ROOT has AliEn and OpenGL
    Swallow --fatal --error-msg \
      'Current ROOT has no OpenGL support: install your OpenGL libraries and rebuild it!' \
      'Ensuring current ROOT has OpenGL support' \
      RootConfiguredWithFeature opengl
    Swallow --fatal --error-msg \
      'Current ROOT has no AliEn support: install AliEn then rebuild ROOT!' \
      'Ensuring current ROOT has AliEn support' \
      RootConfiguredWithFeature alien

    # Assemble cmake command
    if [[ ! -e 'Makefile' ]]; then

      # Build with C++11?
      root-config --cflags | grep -q -- '-std=c++11' && CMakeCxxFlags="${CMakeCxxFlags} -std=c++11"
      [[ "$Pedantic" == 1 ]] && CMakeCxxFlags="${CMakeCxxFlags} -Wall -Wextra"

      # Build type
      case $BuildType in
        normal)    CMakeBuildType='RELWITHDEBINFO' ;;
        optimized) CMakeBuildType='RELEASE' ;;
        debug)     CMakeBuildType='DEBUG' ;;
      esac

      SwallowProgress -f --pattern \
        "Bootstrapping AliRoot build with CMake${Pedantic:+ (WARNING: pedantic mode is on!)}" \
        cmake "$AliRootSrc" \
          -DCMAKE_C_COMPILER=`root-config --cc` \
          -DCMAKE_CXX_COMPILER=`root-config --cxx` \
          -DCMAKE_Fortran_COMPILER=`root-config --f77` \
          -DCMAKE_INSTALL_PREFIX="$AliRootInst" \
          -DALIEN="$ALIEN_DIR" \
          -DROOTSYS="$ROOTSYS" \
          -DCMAKE_BUILD_TYPE=$CMakeBuildType \
          ${BUILDOPT_LDFLAGS:+-DCMAKE_MODULE_LINKER_FLAGS="$BUILDOPT_LDFLAGS"} \
          ${BUILDOPT_LDFLAGS:+-DCMAKE_SHARED_LINKE__FLAGS="$BUILDOPT_LDFLAGS"} \
          ${BUILDOPT_LDFLAGS:+-DCMAKE_EXE_LINKER_FLAGS="$BUILDOPT_LDFLAGS"} \
          ${FASTJET:+-DFASTJET="$FASTJET"} \
          ${CMakeCxxFlags:+-DCMAKE_CXX_FLAGS="$CMakeCxxFlags"}

    fi

    export CCACHE_BASEDIR="$AliRootBase"

    SwallowProgress -f --percentage 'Building AliRoot' make -j$MJ

    if [[ -L "${AliRootSrc}/include" ]] ; then
      SwallowProgress -f --percentage \
        'Removing legacy symlink to include directory inside source' \
        rm -f "${AliRootSrc}/include"
    fi

    if [[ -d "${AliRootTmp}/version" ]] ; then
      # this dir only exists in "modern" AliRoot versions: we can trust install
      if [[ -L "${AliRootInst}" ]] ; then
        SwallowProgress -f --percentage \
          'Removing legacy symlink to the build directory' \
          rm -f "${AliRootInst}"
      fi
      SwallowProgress -f --percentage 'Installing AliRoot' make -j$MJ install
    else
      # legacy: do not trust "make install"
      Swallow -f 'Legacy: removing existing install directory' \
        rm -rf "${AliRootInst}"
      Swallow -f 'Legacy: symlinking AliRoot build directory to install' \
        ln -nfs "$(basename "$AliRootTmp")" "$AliRootInst"
    fi

    if [[ $GenerateDoc == 1 ]] ; then
      SwallowProgress -f --pattern 'Generating Doxygen documentation' make install-doxygen
    fi

    unset CCACHE_BASEDIR

    Swallow -f 'Sourcing envvars' SourceEnvVars

    if [[ "$DISPLAY" != '' ]]; then
      # Non-fatal
      SwallowProgress --pattern \
        'Test: trying to load AliRoot libraries from ROOT' \
        root -l -q "${AliRootSrc}/macros/loadlibs.C"
    fi

  fi # end build

}

# Module to fetch, update and compile AliPhysics
function ModuleAliPhysics() {

  local GenerateDoc="$1"
  local ForceCleanSlate="$2"
  local Pedantic="$3"

  local CMakeCxxFlags

  Banner 'Installing AliPhysics...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow "Checking if AliPhysics support has been requested" [ "$ALIPHYSICS_VER" != '' ] || return
  Swallow 'Checking that we are not using an external AliPhysics' \
    [ "$ALIPHYSICS_VER" != EXTERNAL ] || return

  # AliPhysics variables: only ${ALICE_PHYSICS} needed
  # - ${ALICE_PHYSICS}: installation directory
  # - ${ALICE_PHYSICS}/../build: build directory
  # - ${ALICE_PHYSICS}/../src: source directory

  local AliPhysicsBase=$( dirname "${ALICE_PHYSICS}" )
  local AliPhysicsInst="$ALICE_PHYSICS"
  local AliPhysicsSrc="${AliPhysicsBase}/src"
  local AliPhysicsTmp="${AliPhysicsBase}/build"

  # AliPhysics remote name
  local AliPhysicsGitRemote='alicern'

  # AliPhysics Git private and public URLs
  local AliPhysicsGitUrlPub='http://git.cern.ch/pub/AliPhysics'
  local AliPhysicsGitUrlPriv='https://git.cern.ch/reps/AliPhysics'

  if [[ ! -d "$AliPhysicsTmp" ]]; then
    Swallow -f "Creating AliPhysics build directory" mkdir -p "$AliPhysicsTmp"
  fi

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'only' ]] ; then

    # Download AliPhysics from Git

    local AliPhysicsGit="${AliPhysicsBase}/../git"

    Swallow -f 'Creating AliPhysics Git local directory' \
      mkdir -p "$AliPhysicsGit"
    Swallow -f 'Moving into AliRoot Git local directory' cd "$AliPhysicsGit"
    if [[ ! -e "$AliPhysicsGit/.git" ]] ; then
      SwallowProgress -f --pattern \
        'Cloning AliPhysics Git repository (might take some time)' \
        git clone "$AliPhysicsGitUrlPub" .
    fi
    AliPhysicsGit=$(cd "$AliPhysicsGit";pwd)

    # Setting a public and private remote
    Swallow -f 'Setting ALICE Git pull/push URLs' \
      GitForceSetRemote "$AliPhysicsGitRemote" "$AliPhysicsGitUrlPub" "$AliPhysicsGitUrlPriv"

    SwallowProgress -f 'Synchronizing Git clone' \
      GitSync "$AliPhysicsGitRemote"

    # Shallow copy with git-new-workdir
    if [[ ! -d "${AliPhysicsSrc}/.git" ]] ; then
      rmdir "$AliPhysicsSrc" > /dev/null 2>&1  # works if dir is empty
      SwallowProgress -f --pattern \
        "Creating a shallow clone of AliPhysics" \
        git-new-workdir "$AliPhysicsGit" "$AliPhysicsSrc"
    fi

    Swallow -f 'Moving into local clone' cd "$AliPhysicsSrc"
    Swallow -f "Checking out AliPhysics version ${ALIPHYSICS_VER}" \
      GitCheckoutTrack "$ALIPHYSICS_VER" "$AliPhysicsGitRemote"

    if [[ $ForceCleanSlate == 1 ]] ; then
      Swallow -f "Forcing hard reset to remote ${ALIPHYSICS_VER}" \
        GitResetHard "$AliPhysicsGitRemote" "$ALIPHYSICS_VER"
      Swallow -f 'Forcing cleanup of working directory' git clean -f -d
    elif [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      SwallowProgress -f --pattern \
        "Updating AliPhysics ${ALIPHYSICS_VER} from public Git" \
        git pull --rebase "$AliPhysicsGitRemote" "$ALIPHYSICS_VER"
    fi

  fi # end download

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'no' ]] ; then

    # Build AliPhysics

    # Build type
    case $BuildType in
      normal)    CMakeBuildType='RELWITHDEBINFO' ;;
      optimized) CMakeBuildType='RELEASE' ;;
      debug)     CMakeBuildType='DEBUG' ;;
    esac

    # Build with C++11?
    root-config --cflags | grep -q -- '-std=c++11' && CMakeCxxFlags="${CMakeCxxFlags} -std=c++11"
    [[ "$Pedantic" == 1 ]] && CMakeCxxFlags="${CMakeCxxFlags} -Wall -Wextra"

    Swallow -f 'Moving into AliPhysics build directory' cd "$AliPhysicsTmp"

    SwallowProgress -f --pattern \
      "Configuring AliPhysics with CMake${Pedantic:+ (WARNING: pedantic mode is on!)}" \
      cmake "$AliPhysicsSrc" \
        -DCMAKE_C_COMPILER=`root-config --cc` \
        -DCMAKE_CXX_COMPILER=`root-config --cxx` \
        -DCMAKE_Fortran_COMPILER=`root-config --f77` \
        -DCMAKE_INSTALL_PREFIX="$AliPhysicsInst" \
        -DALIEN="$ALIEN_DIR" \
        -DROOTSYS="$ROOTSYS" \
        ${FASTJET:+-DFASTJET="$FASTJET"} \
        -DALIROOT="$ALICE_ROOT" \
        -DCMAKE_BUILD_TYPE=$CMakeBuildType \
        ${CMakeCxxFlags:+-DCMAKE_CXX_FLAGS="$CMakeCxxFlags"}

    export CCACHE_BASEDIR="$AliPhysicsBase"

    SwallowProgress -f --percentage 'Building AliPhysics' make -j$MJ
    SwallowProgress -f --percentage 'Installing AliPhysics' make -j$MJ install

    unset CCACHE_BASEDIR

    if [[ $GenerateDoc == 1 ]] ; then
      SwallowProgress -f --pattern 'Generating Doxygen documentation' make install-doxygen
    fi

  fi # end build

}

# Get file size - depending on the operating system
function GetFileSizeBytes() {(
  V=$( wc -c "$1" | awk '{ print $1 }' )
  echo $V
)}

# Progress with moving dots
function SwallowProgress() {
  local BkgPid Op Fatal TsStart TsEnd Size OldSize Ret ProgressCount

  if [ "$1" == '-f' ] ; then
    Fatal=1
    shift
  else
    Fatal=0
  fi

  if [ "$1" == '--pattern' ] || [ "$1" == '--percentage' ] ; then
    Mode="$1"
    shift
  fi

  Op="$1"
  shift

  SwallowStart "$Op" "$@"
  TsStart=$( date +%s )

  "$@" >> "$OUT" 2>> "$ERR" &
  BkgPid=$!

  Size=0
  ProgressCount=-1

  while kill -0 $BkgPid > /dev/null 2>&1 ; do
    if [ "$Mode" == '--pattern' ] ; then
      # Based on output size
      OldSize="$Size"
      Size=$( GetFileSizeBytes "$OUT" )
      if [ "$OldSize" != "$Size" ] ; then
        let ProgressCount++
      fi
    else
      # Based on the percentage (default)
      ProgressCount=$( tail -n10 "$OUT" | grep -Eo '[0-9]{1,3}([,\.][0-9])?%' | tail -n1 | tr -d '%' )
      ProgressCount=${ProgressCount%%,*}
      ProgressCount=${ProgressCount%%.*}
      ProgressCount=$((ProgressCount+0))
    fi
    SwallowStep $Mode "$Op" $ProgressCount $TsStart
    sleep 1
  done

  wait $BkgPid
  Ret=$?

  TsEnd=$( date +%s )
  SwallowEnd "$Op" $Fatal $Ret $TsStart $TsEnd "$@"

  if [[ $Ret != 0 && $Fatal == 1 ]]; then
    LastLogLines -e "$Op"
    exit 1
  fi

  return $Ret
}

# Clean up AliEn
function ModuleCleanAliEn() {
  local AliEnDir
  Banner 'Cleaning AliEn...'
  Swallow -f "Sourcing envvars" SourceEnvVars

  Swallow 'Checking that we are not using an external AliEn' \
    [ "$ALIENEXT_VER" != EXTERNAL ] || return

  find "$ALICE_PREFIX" -maxdepth 1 -name 'alien.v*' -and -type d | \
  while read AliEnDir ; do
    AliEnVer=`basename "$AliEnDir"`
    AliEnVer=${AliEnVer:6}
    Swallow -f "Removing AliEn $AliEnVer" rm -rf "$AliEnDir"
  done
  Swallow -f "Removing symlink to latest AliEn ($ALIEN_DIR)" rm -f "$ALIEN_DIR"
  if [[ "$SYSTEM_ALIEN_LIBS" == 1 ]]; then
    Swallow -f "Removing AliEn libs in /usr/local/lib" \
            rm -f /usr/local/lib/libXrd* /usr/local/lib/libgapiUI*
  fi
}

# Clean up ROOT
function ModuleCleanRoot() {
  Banner 'Cleaning ROOT...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking that we are not using an external ROOT' [ "$ROOT_VER" != EXTERNAL ] || return

  local RootBase=$( dirname "${ROOTSYS}" )
  local RootInst="$ROOTSYS"
  local RootSrc="${RootBase}/src"
  local RootTmp="${RootBase}/build"

  Swallow 'Checking if ROOT is really installed (old schema)' [ -f "${RootBase}/LICENSE" ]
  if [[ $? == 0 ]] ; then
    Swallow -f "Removing ROOT ${ROOT_VER} (old schema)" rm -rf "${RootBase}"
  fi

  Swallow 'Checking if ROOT is really installed (new schema)' [ -d "${RootTmp}" ]
  if [[ $? == 0 ]] ; then
    Swallow -f "Removing ROOT ${ROOT_VER} installation directory" rm -rf "${RootInst}"
    Swallow -f "Removing ROOT ${ROOT_VER} build directory" rm -rf "${RootTmp}"
  fi

  return 0
}

# Clean up Geant3
function ModuleCleanGeant3() {
  Banner "Cleaning Geant3..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  Swallow 'Checking that we are not using an external Geant3' [ "$G3_VER" != EXTERNAL ] || return

  local Geant3Base="${ALICE_PREFIX}/geant3/${G3_SUBDIR}"
  local Geant3Inst="${Geant3Base}/inst"
  local Geant3Src="${Geant3Base}/src"
  local Geant3Tmp="${Geant3Base}/build"

  Swallow 'Checking if Geant3 is really installed (old schema)' [ -f "${Geant3Base}/README" ]
  if [[ $? == 0 ]] ; then
    Swallow -f "Removing Geant3 ${G3_VER} (old schema)" rm -rf "${Geant3Base}"
  fi

  Swallow 'Checking if Geant3 is really installed (new schema)' [ -d "${Geant3Tmp}" ]
  if [[ $? == 0 ]] ; then
    Swallow -f "Removing Geant3 ${G3_VER} installation directory" rm -rf "${Geant3Inst}"
    Swallow -f "Removing Geant3 ${G3_VER} build directory" rm -rf "${Geant3Tmp}"
  fi

  return 0
}

# Clean up Fastjet
function ModuleCleanFastJet() {
  Banner 'Cleaning FastJet...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  local FastJetBase="$( dirname "$FASTJET" )"
  local FastJetInst="$FASTJET"
  local FastJetSrc="${FastJetBase}/src"

  Swallow 'Checking if FastJet is really installed (old schema)' [ -f "${FastJetBase}/lib" ]
  if [[ $? == 0 ]] ; then
    Swallow -f "Removing FastJet $FASTJET_VER (old schema)" rm -rf "$FastJetBase"/{bin,lib,include,src}
  fi

  Swallow 'Checking if FastJet is really installed (new schema)' [ -d "${FastJetSrc}" ]
  if [[ $? == 0 ]] ; then
    Swallow -f "Removing FastJet $FASTJET_VER (new schema)" rm -rf "$FastJetSrc" "$FastJetInst"
  fi
}

# Clean up AliRoot
function ModuleCleanAliRoot() {
  Banner 'Cleaning AliRoot Core...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking that we are not using an external AliRoot Core' \
    [ "$ALICE_VER" != EXTERNAL ] || return

  local AliRootBase=$( dirname "${ALICE_ROOT}" )
  local AliRootInst="$ALICE_ROOT"
  local AliRootSrc="${AliRootBase}/src"
  local AliRootTmp="${AliRootBase}/build"

  Swallow 'Checking if AliRoot is really there' [ -d "$AliRootTmp" ] || return 0
  Swallow -f 'Removing AliRoot build directory' rm -rf "$AliRootTmp"
  Swallow -f "Removing AliRoot install directory" rm -rf "$AliRootInst"
}

# Clean up AliPhysics
function ModuleCleanAliPhysics() {
  Banner 'Cleaning AliPhysics...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  Swallow 'Checking that we are not using an external AliPhysics' \
    [ "$ALIPHYSICS_VER" != EXTERNAL ] || return

  local AliPhysicsBase=$( dirname "${ALICE_PHYSICS}" )
  local AliPhysicsInst="$ALICE_PHYSICS"
  local AliPhysicsSrc="${AliPhysicsBase}/src"
  local AliPhysicsTmp="${AliPhysicsBase}/build"

  Swallow 'Checking if AliPhysics is really there' [ -d "$AliPhysicsTmp" ] || return 0
  Swallow -f 'Removing AliPhysics build directory' rm -rf "$AliPhysicsTmp"
  Swallow -f "Removing AliPhysics install directory" rm -rf "$AliPhysicsInst"
}

# Download URL $1 to file $2 using wget or curl
function Dl() {
  # All output on stdout to allow for SwallowProgress to work
  which curl > /dev/null 2>&1
  if [ $? == 0 ]; then
    curl --progress-bar -Lo "$2" "$1" 2>&1
    return $?
  else
    wget -O "$2" "$1" 2>&1
    return $?
  fi
}

# Check prerequisites
function ModuleCheckPrereq() {

  local aliUpdateMsg
  local aliUpdateFlag

  Banner 'Checking prerequisites...'
  Swallow -f 'Checking if on a 64 bit machine' [ `uname -m` == 'x86_64' ]
  Swallow -f \
          --error-msg 'Command "git-new-workdir" cannot be found in your $PATH. Follow the instructions on the web to install it.' \
         'Checking for git-new-workdir script in $PATH' which git-new-workdir

  if [[ $(uname) == Darwin ]]; then
    local DEVTOOLS_ERR=$(cat <<\EOF
Please install Xcode and the Command Line Tools.
To do that, open Xcode, then select from the menubar:

  Xcode > Open Developer Tool > More Developer Tools...

Note: you might need to run a developer command manually afterwards (such as
"clang") to accept the Apple license agreement.
EOF)
    Swallow -f \
            --error-msg "$DEVTOOLS_ERR" \
            "Checking Xcode Developer Tools path" \
            "xcode-select" "--print-path"
    Swallow -f \
            --error-msg "$DEVTOOLS_ERR" \
            "Verifying integrity of system includes" \
            [ -r /usr/include/openssl/ssl.h ]
    Swallow -f \
            --error-msg "$DEVTOOLS_ERR" \
            "Checking Command Line Tools path" \
            [ -d /Library/Developer/CommandLineTools ]
  fi

  if [[ $DontUpdateEnv == 0 ]] ; then
    aliUpdateMsg=' and updating alice-env.sh'
    aliUpdateFlag='-u'
  else
    aliUpdateMsg=' (not updating alice-env.sh as requested)'
    aliUpdateFlag='-k'
  fi

  Swallow --fatal --error-msg 'You must source the alice-env.sh script and pick the tuple you wish to build first!' \
    "Checking if ALICE environment works${aliUpdateMsg}" SourceEnvVars ${aliUpdateFlag}

}

# Install AliEn
function ModuleAliEn() {

  local ALIEN_TEMP_INST_DIR="/tmp/alien-temp-inst-$USER"
  local ALIEN_INSTALLER="$ALIEN_TEMP_INST_DIR/alien-installer"

  Banner 'Installing AliEn...'
  Swallow 'Checking that we are not using an external AliEn' \
    [ "$ALIENEXT_VER" != EXTERNAL ] || return

  Swallow -f "Creating temporary working directory" \
    mkdir -p "$ALIEN_TEMP_INST_DIR"
  local CURWD=`pwd`
  cd "$ALIEN_TEMP_INST_DIR"

  Swallow -f "Sourcing envvars" SourceEnvVars

  Swallow -f "Downloading AliEn installer" \
    Dl http://alien.cern.ch/alien-installer "$ALIEN_INSTALLER"
  #Swallow -f "Copying patched AliEn installer" \
  #        \cp $ALICE_PREFIX/alien-installer $ALIEN_INSTALLER

  Swallow -f "Making AliEn installer executable" \
    chmod +x "$ALIEN_INSTALLER"

  local InstallMsg=''
  if [ "$ALIEN_INSTALL_TYPE" == 'compile' ] ; then
    InstallMsg='Compiling AliEn from sources'
  else
    InstallMsg='Installing AliEn binaries'
  fi

  Swallow -f "$InstallMsg" \
    "$ALIEN_INSTALLER" -install-dir "$ALIEN_DIR" -batch -notorrent \
    -no-certificate-check -type "$ALIEN_INSTALL_TYPE"

  cd "$CURWD"
  Swallow -f "Removing temporary working directory" rm -rf "$ALIEN_TEMP_INST_DIR"

  if [[ "$SYSTEM_ALIEN_LIBS" == 1 ]]; then
    Swallow -f "Removing old AliEn libs in /usr/local/lib" \
            rm -f /usr/local/lib/libXrd* /usr/local/lib/libgapiUI*
    Swallow -f "Linking AliEn libs to /usr/local/lib" \
               bash -ce "for L in $GSHELL_ROOT/lib/*.{dylib,so};
                            do ln -nfs \$L /usr/local/lib; done"
  fi
}

# Module to fetch the alice-env.sh script
function ModuleFetchEnv() {
  local ALI_ENV_URL="https://raw.githubusercontent.com/dberzano/cern-alice-setup/master/alice-env.sh"
  local ALI_ENV_DEST=$(mktemp /tmp/alice-env-XXXXX)
  Banner "Fetching the ALICE environment script..."
  Swallow -f \
          --error-msg "Download failed, check your connectivity" \
          "Downloading alice-env.sh" \
          Dl $ALI_ENV_URL $ALI_ENV_DEST
  local ALI_ENV_SHEBANG="$(head -n1 $ALI_ENV_DEST)"
  Swallow -f \
          --error-msg "alice-env.sh script corrupted, please retry later" \
          "Checking script integrity" \
          [ "${ALI_ENV_SHEBANG:0:3}" == '#!/' ]
  Swallow -f \
          --success-msg "alice-env.sh script downloaded in $PWD: source it and follow the instructions" \
          "Moving script in place" \
          \mv $ALI_ENV_DEST $PWD/alice-env.sh
  return 0
}

# Fatal error
function Fatal() {
  echo -e "\033[31m$1\033[m"
  exit 1
}

# Remove old logs
function RemoveLogs() {
  rm -f "$SWALLOW_LOG".out "$SWALLOW_LOG".err
}

# Prints out a nice help
function Help() (

  local Cmd='bash <(curl -fsSL http://alien.cern.ch/alice-installer)'

  local CErr=$( echo -e "\033[31m" )
  local CWar=$( echo -e "\033[33m" )
  local CEmp=$( echo -e "\033[35m" )
  local COff=$( echo -e "\033[m" )
  local CTt=$( echo -e "\033[36m" )

  local errMsg="$1"

  local urlManual='https://dberzano.github.io/alice/install-aliroot/manual'
  local urlAuto='https://dberzano.github.io/alice/install-aliroot/auto'

  cat <<_EoF_

${CTt}alice-install.sh${COff} -- by Dario Berzano <dario.berzano@cern.ch>

Automatic installation of the ALICE framework.
The automatic installation follows exactly the same steps described on:

  ${CEmp}${urlManual}${COff}

Online manual of the automatic installation procedure:

  ${CEmp}${urlAuto}${COff}

To build, install, clean or update one or multiple components:

  ${CTt}${Cmd} \\
    [--get-alice-env] \\
    [--alien] [--root] [--geant3] [--fastjet] [--aliroot] [--aliphysics] \\
    [--all] [--all-but-alien] \\
    [--clean-alien] [--clean-root] [--clean-geant3] [--clean-fastjet] \\
    [--clean-aliroot] [--clean-aliphysics] \\
    [--clean-all] [--clean-all-but-alien] \\
    [--ncores <n>] \\
    [--pedantic] \\
    [--force-clean-slate] \\
    [--dont-update-env] \\
    [--one-log-per-user] \\
    [--verbose] \\
    [--download-only|--no-download] \\
    [--compiler [gcc|clang|/prefix/to/gcc]] \\
    [--type [normal|optimized|debug]]${COff}

Components will be processed in the correct dependency order, regardless of the
given switches order, e.g. ROOT is be always installed before Geant 3, and
cleanups always occur before installations.

To install everything from scratch, you need to get the ALICE environment script
first:

  ${CTt}${Cmd} --get-alice-env${COff}

If you just want to generate a summary to send as a bug report:

  ${CTt}${Cmd} --bugreport${COff}

For instance, to install all (including AliEn) using Clang as compiler in debug
mode:

  ${CTt}${Cmd} \\
    --all --compiler clang --type debug${COff}

Switches (all of them are optional):

  ${CEmp}--ncores <n>${COff}        Build using <n> parallel threads, instead of automatically
                      calculating the optimal number

  ${CEmp}--pedantic${COff}          Stricter warning handling: useful for testing new code

  ${CEmp}--force-clean-slate${COff} (POTENTIALLY DANGEROUS!) Discard all your local changes in
                      all source directories and sync with the remote ones. This
                      is useful if you want a clean source, and you are 100%
                      sure you are not going to lose your work

  ${CEmp}--dont-update-env${COff}   (POTENTIALLY DANGEROUS!) Do not download updates of the
                      environment script while installing. Note that the latest
                      version of the installation script is in sync with the
                      latest version of the environment one, so expect problems
                      if you use this switch

  ${CEmp}--one-log-per-user${COff}  (POTENTIALLY DANGEROUS!) Without this switch it is
                      possible to start several build sessions per user, and log
                      files will be distinct. By turning on this option only one
                      log file is generated per user and it is not possible to
                      launch several build sessions at the same time

  ${CEmp}--verbose${COff}           Print out the commands being executed under the hood

  ${CEmp}--compiler <comp>${COff}   Instead of picking the compiler automatically, choose a
                      custom one. You can choose "gcc" or "clang", or specify
                      the full path of your custom gcc installation

  ${CEmp}--type <type>${COff}       Build type: choose between optimized, normal and debug.
                      The default is normal. "debug" turns off all optimizations
                      and enables debug symbols, while "optimized" generates no
                      debug symbol and uses the maximum level of optimization.
                      Those build options are applied to every component

  ${CEmp}--download-only${COff}     Only download the specified components: don't build.
                      Useful if you want to proceed manually to give special
                      build options

  ${CEmp}--no-download${COff}       Only build, don't download or update. Useful if you don't
                      want to get the updates from the remote repositories, or
                      if you are offline

_EoF_

  SourceEnvVars > /dev/null 2>&1
  Rv=$?
  if [[ "$Rv" == 100 ]] ; then

    # alice-env.sh script is not loaded
    cat <<_EoF_
${CWar}Please load your alice-env.sh script and select the tuple you wish to install
before running the automatic installation.${COff}

_EoF_

  elif [[ "$Rv" != 0 ]] ; then

    # alice-env.sh script cannot be loaded: some error occurred
    cat <<_EoF_
${CErr}An unknown problem occurred while loading alice-env.sh with tuple ${ALI_nAliTuple}.${COff}
Full path to the script:
  ${CTt}${ALI_EnvScript}${COff}

_EoF_

  else

    # alice-env.sh script was loaded but no action was provided

    local ALIEN_STR='always the latest version'
    local ROOT_STR="${CEmp}${ROOT_VER}${COff}"
    local G3_STR="${CEmp}${G3_VER}${COff}"
    local ALICE_STR="${CEmp}${ALICE_VER}${COff}"
    local FASTJET_STR="${CEmp}${FASTJET_VER}${COff}"
    local ALIPHYSICS_STR="${CEmp}${ALIPHYSICS_VER}${COff}"

    if [[ $ALIENEXT_VER == EXTERNAL ]]; then
      ALIEN_STR="will not be built, taken as-is from ${CTt}${ALIEN_DIR}${COff}"
    fi

    if [[ $ROOT_VER == '' ]]; then
      ROOT_STR='will not be installed'
    elif [[ $ROOT_VER == EXTERNAL ]] ; then
      ROOT_STR="will not be built, taken as-is from ${CTt}${ROOT_SUBDIR}${COff}"
    elif [[ $ROOT_VER != $ROOT_SUBDIR ]]; then
      ROOT_STR="${CEmp}${ROOT_VER}${COff} (subdir: ${CTt}${ROOT_SUBDIR}${COff})"
    fi

    if [[ $G3_VER == '' ]]; then
      G3_STR='will not be installed'
    elif [[ $G3_VER == EXTERNAL ]] ; then
      G3_STR="will not be built, taken as-is from ${CTt}${G3_SUBDIR}${COff}"
    elif [[ $G3_VER != $G3_SUBDIR ]]; then
      G3_STR="${CEmp}${G3_VER}${COff} (subdir: ${CTt}${G3_SUBDIR}${COff})"
    fi

    if [[ $FASTJET_VER == '' ]]; then
      FASTJET_STR='will not be installed'
      FJCONTRIB_STR="${FASTJET_STR}"
    else
      FJCONTRIB_STR="${CEmp}${FJCONTRIB_VER}${COff} (same dir of FastJet)"
      if [[ $FASTJET_VER != $FASTJET_SUBDIR ]]; then
        FASTJET_STR="${CEmp}${FASTJET_VER}${COff} (subdir: ${CTt}${FASTJET_SUBDIR}${COff})"
      fi
    fi

    if [[ $ALICE_VER == '' ]]; then
      ALICE_STR='will not be installed'
    elif [[ $ALICE_VER == EXTERNAL ]] ; then
      ALICE_STR="will not be built, taken as-is from ${CTt}${ALICE_SUBDIR}${COff}"
    elif [[ $ALICE_VER != $ALICE_SUBDIR ]]; then
      ALICE_STR="${CEmp}${ALICE_VER}${COff} (subdir: ${CTt}${ALICE_SUBDIR}${COff})"
    fi

    if [[ $ALIPHYSICS_VER == '' ]]; then
      ALIPHYSICS_STR='will not be installed'
    elif [[ $ALIPHYSICS_VER != $ALIPHYSICS_SUBDIR ]]; then
      ALIPHYSICS_STR="${CEmp}${ALIPHYSICS_VER}${COff} (subdir: ${CTt}${ALIPHYSICS_SUBDIR}${COff})"
    fi

    local BUILD_MODE_STR="${CTt}${BUILD_MODE}${COff}"
    if [[ $BUILD_MODE == custom-gcc ]]; then
      BUILD_MODE_STR="using custom gcc at ${CTt}${CUSTOM_GCC_PATH}${COff}"
    fi

    cat <<_EoF_
If you re-run this script with one or more actions now, the following
configuration will be used:

ALICE Environment script:
  ${CTt}${ALI_EnvScript}${COff}

Software installation prefix (nothing will be installed outside it):
  ${CTt}${ALICE_PREFIX}${COff}

Compiler (set with ${CEmp}--compiler${COff}): ${BUILD_MODE_STR}
(You can choose between $( echo ${SUPPORTED_BUILD_MODES} | sed -e 's/ /, /g'))

Build type (set with ${CEmp}--type${COff}): ${CTt}${BuildType}${COff}
(You can choose between debug, normal, optimized)

You have selected tuple ${CEmp}number ${ALI_nAliTuple}${COff}. This corresponds to:

  AliEn            ${ALIEN_STR}
  ROOT             ${ROOT_STR}
  Geant 3          ${G3_STR}
  FastJet          ${FASTJET_STR}
  FastJet Contrib  ${FJCONTRIB_STR}
  AliRoot Core     ${ALICE_STR}
  AliPhysics       ${ALIPHYSICS_STR}

_EoF_

  fi

  # Error message, if any
  if [[ $errMsg != '' ]]; then
    echo ">> ${CErr}${errMsg}${COff}" | cat
    echo ''
  fi

)

# Check if ROOT has a certain feature (case-insensitive match)
function RootConfiguredWithFeature() {
  if [[ -x "${ROOTSYS}/bin/root-config" ]] ; then
    "${ROOTSYS}/bin/root-config" --features | grep -qi "$1"
    return $?
  fi
  "$(dirname "$ROOTSYS")"/build/bin/root-config --features | grep -qi "$1"
}

# Detects proper build options based on the current operating system
function DetectOsBuildOpts() {

  local KernelName=`uname -s`
  local VerFile='/etc/lsb-release'
  local OsName
  local OsVer

  if [[ $KernelName == 'Darwin' ]] ; then
    ALIEN_INSTALL_TYPE='user'

    # Needed for including <cstdlib>: fixes fabs errors with libc++
    FASTJET_PATCH_HEADERS=1

    OsVer=`uname -r | cut -d. -f1`
    if [[ $OsVer -ge 11 ]] ; then
      # 11 = Lion (10.7)
      SUPPORTED_BUILD_MODES='clang custom-gcc'
    fi
    if [[ $OsVer -ge 12 ]]; then
      # 12 = Mountain Lion (10.8)
      BUILDOPT_CPATH='/usr/X11/include'  # XQuartz
      ALIEN_INSTALL_TYPE='compile'
      MIN_ROOT_VER_STR='v5-34-18'
    fi
    if [[ $OsVer -ge 13 ]]; then
      # 13 = Mavericks (10.9)
      SUPPORTED_BUILD_MODES='clang'
    fi
    if [[ $OsVer -ge 14 ]]; then
      # 14 = Yosemite (10.10)
      MIN_ROOT_VER_STR='v5-34-30'
    fi
    if [[ $OsVer -ge 15 ]]; then
      # 15 = El Capitan (10.11)
      SYSTEM_ALIEN_LIBS=1
    fi
  elif [[ $KernelName == 'Linux' ]] ; then
    ALIEN_INSTALL_TYPE='compile'
    SUPPORTED_BUILD_MODES='gcc custom-gcc clang'
    OsName=`source $VerFile > /dev/null 2>&1 ; echo $DISTRIB_ID`
    OsVer=`source $VerFile > /dev/null 2>&1 ; echo $DISTRIB_RELEASE | tr -d .`
    # https://en.wikipedia.org/wiki/List_of_Linux_Mint_releases
    if [[ "$OsName" == 'Ubuntu' && "$OsVer" -ge 1110 && "$OsVer" -le 1404 ]]; then
      BUILDOPT_LDFLAGS='-Wl,--no-as-needed'
    elif [[ "$OsName" == 'LinuxMint' && "$OsVer" -ge 12 && "$OsVer" -le 17 ]] ; then
      BUILDOPT_LDFLAGS='-Wl,--no-as-needed'
    fi
  fi

  MIN_ROOT_VER_NUM=$( ConvertVersionStringToNumber "$MIN_ROOT_VER_STR" )
  BUILD_MODE=`echo $SUPPORTED_BUILD_MODES | awk '{print $1}'`

  # Report debug, if requested
  if [[ $DebugDetectOs == 1 ]] ; then
    # Output value of all the variables set by this function
    echo
    echo -e "\033[33mOperating-system specific build options\033[m"
    for VarName in ALIEN_INSTALL_TYPE FASTJET_PATCH_HEADERS SUPPORTED_BUILD_MODES BUILDOPT_CPATH \
      MIN_ROOT_VER_STR BUILDOPT_LDFLAGS ; do
      echo -e " \033[35m* \033[34m${VarName}=\033[m\033[35m$(eval echo \$$VarName)\033[m"
    done
  fi

}

# Convert a version string to a number, e.g.:
#   "v5-34-15" -> 5034015
# Special version "all" means "there is no minimum version" and it is converted to 0:
#   "all" -> 0
# If a string cannot be converted, it will return a "large" numebr:
#   "v5-34-00-patches" -> 999999999
# This function is used to check the minimum version of a software.
function ConvertVersionStringToNumber() (
  VerStr="$1"
  if [[ "$VerStr" == 'all' ]] ; then
    echo 0
  elif [[ "$VerStr" =~ ^v?0*([0-9]{1,3})[-.]0*([0-9]{1,3})[-.]0*([0-9]{1,3})$ ]] ; then
    Maj=${BASH_REMATCH[1]}
    Min=${BASH_REMATCH[2]}
    Pat=${BASH_REMATCH[3]}
    echo $(( Maj*1000000 + Min*1000 + Pat ))
  else
    echo 999999999
  fi
  return 0
)

# Main function
function Main() {

  local DO_FETCH_ENV=0
  local DO_ALIEN=0
  local DO_ROOT=0
  local DO_G3=0
  local DO_FASTJET=0
  local DO_ALICE=0
  local DO_ALIPHYSICS=0
  local DO_CLEAN_ALIEN=0
  local DO_CLEAN_ALICE=0
  local DO_CLEAN_ALIPHYSICS=0
  local DO_CLEAN_ROOT=0
  local DO_CLEAN_G3=0
  local DO_CLEAN_FASTJET=0
  local DO_BUGREPORT=0

  local N_INST=0
  local N_CLEAN=0
  local N_INST_CLEAN=0
  local PARAM

  local GenerateDoc=0
  local Pedantic=''
  local ForceCleanSlate=0
  local SingleLogPerUser=0

  # Look for debug
  for (( i=0 ; i<=$# ; i++ )) ; do
    if [[ ${!i} == '--verbose' ]] ; then
      DebugSwallow=1
      DebugDetectOs=1
    fi
  done

  # Detect proper build options
  DetectOsBuildOpts

  # Parse parameters
  while [ $# -gt 0 ]; do
    if [ "${1:0:2}" == "--" ]; then
      PARAM="${1:2}"
      case "$PARAM" in

        #
        # Install targets
        #

        alien)
          DO_ALIEN=1
        ;;

        root)
          DO_ROOT=1
        ;;

        geant3)
          DO_G3=1
        ;;

        fastjet)
          DO_FASTJET=1
        ;;

        aliroot)
          DO_ALICE=1
        ;;

        aliphysics)
          DO_ALIPHYSICS=1
        ;;

        all-but-alien)
          DO_ROOT=1
          DO_G3=1
          DO_FASTJET=1
          DO_ALICE=1
          DO_ALIPHYSICS=1
        ;;

        all)
          DO_ALIEN=1
          DO_ROOT=1
          DO_G3=1
          DO_FASTJET=1
          DO_ALICE=1
          DO_ALIPHYSICS=1
        ;;

        #
        # Cleanup targets (AliEn is not to be cleaned up)
        #

        clean-alien)
          DO_CLEAN_ALIEN=1
        ;;

        clean-root)
          DO_CLEAN_ROOT=1
        ;;

        clean-geant3)
          DO_CLEAN_G3=1
        ;;

        clean-fastjet)
          DO_CLEAN_FASTJET=1
        ;;

        clean-aliroot)
          DO_CLEAN_ALICE=1
        ;;

        clean-aliphysics)
          DO_CLEAN_ALIPHYSICS=1
        ;;

        clean-all)
          DO_CLEAN_ALIEN=1
          DO_CLEAN_ROOT=1
          DO_CLEAN_G3=1
          DO_CLEAN_FASTJET=1
          DO_CLEAN_ALICE=1
          DO_CLEAN_ALIPHYSICS=1
        ;;

        clean-all-but-alien)
          DO_CLEAN_ROOT=1
          DO_CLEAN_G3=1
          DO_CLEAN_FASTJET=1
          DO_CLEAN_ALICE=1
          DO_CLEAN_ALIPHYSICS=1
        ;;

        #
        # Build type
        #

        type)

          if [[ $2 == 'normal' || $2 == 'optimized' || $2 == 'debug' ]] ; then
            BuildType="$2"
            shift
          else
            Help "Build type \"$2\" not supported, use one of: normal, optimized, debug"
            exit 1
          fi

        ;;

        #
        # Other targets
        #

        verbose)
          # already checked on top, skip it
        ;;

        bugreport)
          DO_BUGREPORT=1
        ;;

        get-alice-env)
          DO_FETCH_ENV=1
        ;;

        ncores)
          NCORES="$2"
          expr "$NCORES" + 0 > /dev/null 2> /dev/null
          if [ $? != 0 ]; then
            Help "--ncores must be followed by a number greater than zero"
            exit 1
          fi
          shift
        ;;

        compiler)
          BUILD_MODE="$2"

          if [ "$BUILD_MODE" == '' ]; then
            Help "No compiler specified, use one of: $SUPPORTED_BUILD_MODES"
            exit 1
          elif [ "${BUILD_MODE:0:1}" == '/' ]; then
            BUILD_MODE='custom-gcc'
            CUSTOM_GCC_PATH="$2"
          fi

          shift

          # Is this build mode supported?
          local Found=0
          local B
          for B in $SUPPORTED_BUILD_MODES ; do
            if [ "$B" == "$BUILD_MODE" ]; then
              Found=1
              break
            fi
          done
          if [ "$Found" != 1 ]; then
            Help "Unsupported compiler: $BUILD_MODE, use one \
                 of: $SUPPORTED_BUILD_MODES"
            exit 1
          fi

        ;;

        download-only)
          DOWNLOAD_MODE='only'
        ;;

        no-download)
          DOWNLOAD_MODE='no'
        ;;

        doc)
          GenerateDoc=1
        ;;

        pedantic)
          Pedantic=1
        ;;

        force-clean-slate)
          ForceCleanSlate=1
        ;;

        dont-update-env)
          DontUpdateEnv=1
        ;;

        one-log-per-user)
          SingleLogPerUser=1
        ;;

        *)
          Help "Unrecognized parameter: $1"
          exit 1
        ;;

      esac
    else
      Help "Unrecognized parameter: $1"
      exit 1
    fi
    shift
  done

  # Log files
  [[ "$SingleLogPerUser" == 1 ]] && \
    SWALLOW_LOG="/tmp/alice-autobuild-${USER}" || \
    SWALLOW_LOG="/tmp/alice-autobuild-${USER}-${$}"
  export SWALLOW_LOG
  export ERR="${SWALLOW_LOG}.err"
  export OUT="${SWALLOW_LOG}.out"

  # How many build actions?
  let N_INST=DO_ALIEN+DO_ROOT+DO_G3+DO_FASTJET+DO_ALICE+DO_ALIPHYSICS
  let N_CLEAN=DO_CLEAN_ALIEN+DO_CLEAN_ROOT+DO_CLEAN_G3+DO_CLEAN_FASTJET+DO_CLEAN_ALICE+DO_CLEAN_ALIPHYSICS
  let N_INST_CLEAN=N_INST+N_CLEAN

  if [[ $DO_FETCH_ENV == 0 && $DO_BUGREPORT == 0  && $N_INST_CLEAN == 0 ]]; then
    Help 'Nothing to do: what do you want to install?'
    exit 1
  elif [[ $DO_FETCH_ENV == 1 && $N_INST_CLEAN -gt 0 ]]; then
    Help 'Cannot fetch alice-env.sh and update/build/clean something at the same time'
    exit 1
  elif [[ "$USER" == "root" && $N_INST_CLEAN -gt 0 ]]; then
    Help 'I am refusing to continue the installation as root user'
    exit 1
  fi

  # Remove spurious log files left
  RemoveLogs

  # Prepare bugreport. This is always done. If --bugreport requested, quit
  # after preparing it, without deleting logfiles
  PrepareBugReport
  if [ $DO_BUGREPORT == 1 ]; then
    echo ""
    echo "Bug report information collected."
    ShowBugReportInfo
    return 0
  fi

  # Where are the logfiles?
  echo ""
  echo "Log messages are being written to:"
  echo ""
  echo -e "  \033[34mstderr:\033[m $ERR"
  echo -e "  \033[34mstdout:\033[m $OUT"


  # Perform required actions
  if [[ $DO_FETCH_ENV == 1 ]]; then
    ModuleFetchEnv
  else

    # Checking prerequisites
    ModuleCheckPrereq

    SourceEnvVars > /dev/null 2>&1
    echo ""

    if [ $MJ == 1 ]; then
      echo "Building on single core (no parallel build)"
    else
      echo "Building using $MJ parallel threads"
    fi

    Banner 'Non-interactive installation begins: go get some tea and scones'

    # All modules
    [[ $DO_CLEAN_ALIEN      == 1 ]] && ModuleCleanAliEn
    [[ $DO_ALIEN            == 1 ]] && ModuleAliEn
    [[ $DO_CLEAN_ROOT       == 1 ]] && ModuleCleanRoot
    [[ $DO_ROOT             == 1 ]] && ModuleRoot $ForceCleanSlate
    [[ $DO_CLEAN_G3         == 1 ]] && ModuleCleanGeant3
    [[ $DO_G3               == 1 ]] && ModuleGeant3 $ForceCleanSlate
    [[ $DO_CLEAN_FASTJET    == 1 ]] && ModuleCleanFastJet
    [[ $DO_FASTJET          == 1 ]] && ModuleFastJet
    [[ $DO_CLEAN_ALICE      == 1 ]] && ModuleCleanAliRoot
    [[ $DO_ALICE            == 1 ]] && ModuleAliRoot $GenerateDoc $ForceCleanSlate $Pedantic
    [[ $DO_CLEAN_ALIPHYSICS == 1 ]] && ModuleCleanAliPhysics
    [[ $DO_ALIPHYSICS       == 1 ]] && ModuleAliPhysics $GenerateDoc $ForceCleanSlate $Pedantic
  fi

  # Remove logs: if we are here, everything went right, so no need to see the
  # logs
  RemoveLogs

  echo ""
}

Main "$@"
