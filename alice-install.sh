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

export SWALLOW_LOG="/tmp/alice-autobuild-$USER-$$"
export ERR="$SWALLOW_LOG.err"
export OUT="$SWALLOW_LOG.out"
export NCORES=0
export BUILD_MODE='' # clang, gcc, custom-gcc
export SUPPORTED_BUILD_MODES=''
export CUSTOM_GCC_PATH='/opt/gcc'
export BUILDOPT_LDFLAGS=''
export BUILDOPT_CPATH=''
export ALIEN_INSTALL_TYPE=''
export FASTJET_PATCH_HEADERS=0
export DOWNLOAD_MODE=''
export MIN_ROOT_VER_NUM=''
export MIN_ROOT_VER_STR='all'

#
# Functions
#

# Sources environment variables
function SourceEnvVars() {
  local R UpdateFlag
  [[ ! -r "$ALI_EnvScript" ]] && return 100
  [[ "$1" == '-u' ]] && UpdateFlag='-u'
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
  echo -e "$MSG" >> "$OUT"
  echo -e "$MSG" >> "$ERR"

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
  while [[ "${1:0:1}" == '-' ]] ; do
    case "$1" in
      -f|--fatal)
        FATAL=1
      ;;
      --error-msg)
        ERRMSG="$2"
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

  if [[ $RET != 0 ]] && [[ $FATAL == 1 ]]; then
    if [[ "$ERRMSG" != '' ]] ; then
      # Produce a custom error message instead of log output
      echo
      echo -e "\033[31m${ERRMSG}\033[m"
      echo
    else
      LastLogLines -e "$OP"
    fi
    exit 1
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
    echo "uname -a: `uname -a`"
    echo "which gcc: `which gcc 2>/dev/null`"
    echo "which g++: `which g++ 2>/dev/null`"
    echo "which clang: `which clang 2>/dev/null`"
    echo "which clang++: `which clang++ 2>/dev/null`"
    echo "which gfortran: `which gfortran 2>/dev/null`"
    echo "which ld: `which ld 2>/dev/null`"
    echo "which make: `which make 2>/dev/null`"
    echo "which cmake: `which cmake 2>/dev/null`"
    echo "root-config --f77: `root-config --f77 2>/dev/null`"
    echo "root-config --cc: `root-config --cc 2>/dev/null`"
    echo "root-config --cxx: `root-config --cxx 2>/dev/null`"
    echo "root-config --ld: `root-config --ld 2>/dev/null`"
    echo "root-config --features: `root-config --features 2>/dev/null`"
    echo "root-config --cflags: `root-config --cflags 2>/dev/null`"
    echo "root-config --auxcflags: `root-config --auxcflags 2>/dev/null`"
    echo "root-config --ldflags: `root-config --ldflags 2>/dev/null`"
    echo "=== ALICE SOFTWARE VERSIONS ==="
    echo "ROOT: $ROOT_VER"
    echo "Geant3: $G3_VER"
    echo "AliRoot: $ALICE_VER"
    echo "FastJet: $FASTJET_VER"
    echo "FJ Contrib: $FJCONTRIB_VER"
    echo "=== TOOLS VERSIONS ==="
    if [ -r /etc/lsb-release ] ; then
      echo "*** /etc/lsb-release ***"
      cat /etc/lsb-release
    fi
    echo "*** gcc ***"
    gcc -v 2>&1
    echo "*** g++ ***"
    g++ -v 2>&1
    echo "*** gfortran ***"
    gfortran -v 2>&1
    echo "*** clang ***"
    clang -v 2>&1
    echo "*** clang++ ***"
    clang++ -v 2>&1
    echo "*** ld ***"
    ld -v 2>&1
    echo "*** cmake ***"
    cmake --version 2>&1
    echo "*** git ***"
    git --version 2>&1
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

  Banner "Installing ROOT..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  Swallow --fatal \
    --error-msg "ROOT $ROOT_VER is not supported on your platform: use at least $MIN_ROOT_VER_STR." \
    "Ensuring ROOT $ROOT_VER is OK for your platform" \
    [ $( ConvertVersionStringToNumber "$ROOT_VER" ) -ge $MIN_ROOT_VER_NUM ]

  if [ ! -d "$ROOTSYS" ]; then
    Swallow -f "Creating ROOT directory" mkdir -p "$ROOTSYS"
  fi

  Swallow -f "Moving into ROOT directory" cd "$ROOTSYS"

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'only' ] ; then

    #
    # Downloading ROOT from Git
    #

    local ROOTGit="${ROOTSYS}/../git"

    Swallow -f 'Creating ROOT Git local directory' mkdir -p "$ROOTGit"
    Swallow -f 'Moving into ROOT Git local directory' cd "$ROOTGit"
    [ ! -e "$ROOTGit/.git" ] && \
      SwallowProgress -f --pattern 'Cloning ROOT Git repository (might take some time)' \
        git clone http://root.cern.ch/git/root.git .

    Swallow -f 'Updating list of remote ROOT Git branches' \
      git remote update origin --prune

    Swallow -f "Checking out ROOT $ROOT_VER" git checkout "$ROOT_VER"

    if [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      SwallowProgress -f --pattern "Updating ROOT $ROOT_VER from Git" git pull --rebase
    fi

    SwallowProgress -f --pattern 'Staging ROOT source in build directory' \
      rsync -avc --exclude '**/.git' "$ROOTGit"/ "$ROOTSYS"

  fi # end download

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'no' ] ; then

    #
    # Build ROOT
    #

    Swallow -f 'Moving into ROOT build directory' cd "$ROOTSYS"

    # Choose correct configuration
    local ConfigOpts="--with-pythia6-uscore=SINGLE \
      --with-alien-incdir=$GSHELL_ROOT/include \
      --with-alien-libdir=$GSHELL_ROOT/lib \
      --with-monalisa-incdir="$GSHELL_ROOT/include" \
      --with-monalisa-libdir="$GSHELL_ROOT/lib" \
      --with-xrootd=$GSHELL_ROOT \
      --enable-minuit2 \
      --enable-roofit \
      --enable-soversion \
      --disable-bonjour \
      --enable-builtin-freetype"

    # Are --disable-fink and --enable-cocoa available (OS X only)?
    if [ "`uname`" == 'Darwin' ] ; then
      if [ `./configure --help 2>/dev/null|grep -c finkdir` == 1 ]; then
        ConfigOpts="$ConfigOpts --disable-fink"
      fi
      if [ `./configure --help 2>/dev/null|grep -c cocoa` == 1 ]; then
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

    SwallowProgress -f --pattern "Configuring ROOT" ./configure $ConfigOpts

    local AppendLDFLAGS AppendCPATH
    [ "$BUILDOPT_LDFLAGS" != '' ] && AppendLDFLAGS="LDFLAGS=$BUILDOPT_LDFLAGS"
    [ "$BUILDOPT_CPATH" != '' ] && AppendCPATH="CPATH=$BUILDOPT_CPATH"

    SwallowProgress -f --pattern "Building ROOT" make -j$MJ $AppendLDFLAGS $AppendCPATH

    # To fix some problems during the creation of PARfiles in AliRoot
    if [ -e "$ROOTSYS/test/Makefile.arch" ]; then
      Swallow -f "Linking Makefile.arch" \
        ln -nfs "$ROOTSYS/test/Makefile.arch" "$ROOTSYS/etc/Makefile.arch"
    fi

  fi # end build

}

# Module to fetch and compile Geant3
function ModuleGeant3() {

  Banner "Installing Geant3..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'only' ] ; then

    #
    # Git clone of Geant3
    #

    Swallow -f "Creating Geant3 Git clone directory" mkdir -p $ALICE_PREFIX/geant3/git
    Swallow -f "Moving to the Geant3 Git clone directory" cd $ALICE_PREFIX/geant3/git

    if [[ ! -d "$ALICE_PREFIX/geant3/git/.git" ]] ; then
      SwallowProgress -f --pattern "Cloning Geant3 Git repository" git clone http://root.cern.ch/git/geant3.git .
    fi

    SwallowProgress -f --pattern "Updating the list of Git references" git remote update --prune

    if [[ ! -d "$GEANT3DIR/.git" ]] ; then
      Swallow -f "Cleaning up leftovers on the local clone for $G3_VER" rm -rf "$GEANT3DIR"
      SwallowProgress -f --pattern "Creating a local Git clone for Geant3 version $G3_VER" git-new-workdir "$ALICE_PREFIX/geant3/git" "$GEANT3DIR" "$G3_VER"
    fi

    Swallow -f "Moving to the local Git clone for Geant3 version $G3_VER" cd "$GEANT3DIR"
    Swallow -f "Checking out Geant3 version $G3_VER" git checkout "$G3_VER"

    if [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      SwallowProgress -f --pattern "Updating Geant3 branch $G3_VER from Git" git pull --rebase
    fi

  fi # end download

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'no' ] ; then

    #
    # Build Geant3
    #

    Swallow -f "Moving to the local Git clone for Geant3 version $G3_VER" cd "$GEANT3DIR"
    SwallowProgress -f --pattern "Building Geant3" make -j$MJ

  fi

}

# Module to fetch and compile FastJet
function ModuleFastJet() {

  local MinFastJetVerStr='v3.0.6'
  local MinFastJetVerNum=$( ConvertVersionStringToNumber "$MinFastJetVerStr" )

  # FastJet versions will be downloaded from tarballs on the official website
  local FASTJET_URL_PATTERN='http://fastjet.fr/repo/fastjet-%s.tar.gz'
  local FASTJET_TARBALL='source.tar.gz'

  # FastJet contrib (optional)
  local FJCONTRIB_URL_PATTERN='http://fastjet.hepforge.org/contrib/downloads/fjcontrib-%s.tar.gz'
  local FJCONTRIB_TARBALL='contrib.tar.gz'

  Banner "Installing FastJet..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  Swallow "Checking if FastJet support has been requested" [ "$FASTJET_VER" != '' ] || return

  Swallow --fatal \
    --error-msg "FastJet $FASTJET_VER is not supported: use at least $MinFastJetVerStr." \
    "Ensuring FastJet $FASTJET_VER is supported" \
    [ $( ConvertVersionStringToNumber "$FASTJET_VER" ) -ge $MinFastJetVerNum ]

  Swallow --fatal \
    --error-msg 'FastJet contrib is mandatory when installing FastJet.' \
    'Ensuring FastJet contrib is enabled' \
    [ "$FJCONTRIB_VER" != '' ]

  Swallow -f "Creating FastJet directory" mkdir -p "$FASTJET/src"
  Swallow -f "Moving into FastJet source directory" cd "$FASTJET/src"

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'only' ]; then

    #
    # Download, unpack and patch FastJet tarball
    #

    if [ ! -e "$FASTJET_TARBALL" ]; then
      SwallowProgress -f --percentage "Downloading FastJet v$FASTJET_VER" \
        Dl $( printf "$FASTJET_URL_PATTERN" "$FASTJET_VER" ) "$FASTJET_TARBALL"
    fi

    if [ ! -d fastjet-"$FASTJET_VER" ]; then
      SwallowProgress -f --pattern "Unpacking FastJet tarball" \
        tar xzvvf "$FASTJET_TARBALL"
    fi

    if [ "$FJCONTRIB_VER" != '' ] ; then

      # Optional FastJet contrib

      if [ ! -e "$FJCONTRIB_TARBALL" ]; then
        SwallowProgress -f --percentage "Downloading FastJet contrib v$FJCONTRIB_VER" \
          Dl $( printf "$FJCONTRIB_URL_PATTERN" "$FJCONTRIB_VER" ) "$FJCONTRIB_TARBALL"
      fi

      if [ ! -d fjcontrib-"$FJCONTRIB_VER" ]; then
        SwallowProgress -f --pattern "Unpacking FastJet contrib tarball" \
          tar xzvvf "$FJCONTRIB_TARBALL"
      fi

    fi

    if [ "$FASTJET_PATCH_HEADERS" == 1 ]; then

      # Patching FastJet headers: libc++ fixup

      function FastJetPatchLibcpp() {
        find . -name '*.h' -or -name '*.hh' | \
          while read F; do
            echo '#include <cstdlib>' > "$F.0" && \
              cat "$F" | grep -v '#include <cstdlib>' >> "$F.0" && \
              \mv -f "$F.0" "$F" || return 1
          done
      }

      Swallow -f "Patching FastJet headers: libc++ workaround" FastJetPatchLibcpp
      unset FastJetPatchLibcpp

    fi

  fi

  if [ "$DOWNLOAD_MODE" == '' ] || [ "$DOWNLOAD_MODE" == 'no' ] ; then

    #
    # Build FastJet
    #

    Swallow -f "Moving into FastJet build directory" \
      cd "$FASTJET/src/fastjet-$FASTJET_VER"

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

    export CXXFLAGS="$BUILDOPT_LDFLAGS -lgmp"
    SwallowProgress -f --pattern "Configuring FastJet" \
      ./configure --enable-cgal --prefix=$FASTJET

    SwallowProgress -f --pattern "Building FastJet" make -j$MJ install

    if [[ "$FJCONTRIB_VER" != '' ]] ; then

      #
      # Build FastJet contrib (optional)
      #

      Swallow -f 'Sourcing envvars' SourceEnvVars
      Swallow -f 'Moving into FastJet contrib build directory' \
        cd "$FASTJET/src/fjcontrib-$FJCONTRIB_VER"

      SwallowProgress -f --pattern 'Configuring FastJet contrib' \
        ./configure CXX="$CXX" CXXFLAGS="$CXXFLAGS"
      SwallowProgress --pattern 'Building FastJet contrib' make -j$MJ
      SwallowProgress --pattern 'Installing FastJet contrib' make install
      SwallowProgress -f --pattern 'Building FastJet contrib shared library' \
        make -j$MJ fragile-shared
      SwallowProgress -f --pattern 'Installing FastJet contrib shared library' \
        make fragile-shared-install

    fi

    unset CXXFLAGS CXX

  fi

}

# Module to fetch, update and compile AliRoot
function ModuleAliRoot() {

  Banner 'Installing AliRoot Core...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  # AliRoot variables: only ${ALICE_ROOT} needed
  # - ${ALICE_ROOT}: installation directory
  # - ${ALICE_ROOT}/../build: build directory
  # - ${ALICE_ROOT}/../src: source directory

  local AliRootBase=$( dirname "${ALICE_ROOT}" )
  local AliRootInst="$ALICE_ROOT"
  local AliRootSrc="${AliRootBase}/src"
  local AliRootTmp="${AliRootBase}/build"

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
        git clone http://git.cern.ch/pub/AliRoot .
    fi
    AliRootGit=$(cd "$AliRootGit";pwd)

    SwallowProgress -f --pattern \
      'Updating list of remote AliRoot Git branches' \
      git remote update origin --prune

    # Source is ${AliRootSrc} his will be a Git directory on its own that shares
    # the object database, but with its own index. This is possible via the
    # git-new-workdir[1] script
    # [1] http://nuclearsquid.com/writings/git-new-workdir/

    # Shallow copy with git-new-workdir
    if [[ ! -d "${AliRootSrc}/.git" ]] ; then
      rmdir "$AliRootSrc" > /dev/null 2>&1  # works if dir is empty
      SwallowProgress -f --pattern \
        "Creating a local clone for version ${ALICE_VER}" \
        git-new-workdir "$AliRootGit" "$AliRootSrc" "$ALICE_VER"
    fi

    Swallow -f 'Moving to local clone' cd "$AliRootSrc"
    Swallow -f "Checking out AliRoot version $ALICE_VER" \
      git checkout "$ALICE_VER"

    if [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      # if we are working on a clone made with git-new-workdir, changes in the
      # git object database will be propagated to all the sibling clones
      SwallowProgress -f --pattern \
        "Updating AliRoot $ALICE_VER from Git" git pull --rebase
    fi

  fi # end download

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'no' ]] ; then

    #
    # Build AliRoot
    #

    Swallow -f 'Moving into AliRoot build directory' cd "$AliRootTmp"
    Swallow -f 'Checking if ROOT has OpenGL enabled' RootHasOpenGl

    # Assemble cmake command
    if [[ ! -e 'Makefile' ]]; then

      # Build with FastJet?
      local FastJetFlag="-DFASTJET=$FASTJET"

      if [[ "$BUILDOPT_LDFLAGS" != '' ]]; then

        # Special configuration for latest Ubuntu/Linux Mint
        SwallowProgress -f --pattern \
          'Bootstrapping AliRoot build with CMake (using LDFLAGS)' \
          cmake "$AliRootSrc" \
            -DCMAKE_C_COMPILER=`root-config --cc` \
            -DCMAKE_CXX_COMPILER=`root-config --cxx` \
            -DCMAKE_Fortran_COMPILER=`root-config --f77` \
            -DCMAKE_MODULE_LINKER_FLAGS="$BUILDOPT_LDFLAGS" \
            -DCMAKE_SHARED_LINKER_FLAGS="$BUILDOPT_LDFLAGS" \
            -DCMAKE_EXE_LINKER_FLAGS="$BUILDOPT_LDFLAGS" \
            -DCMAKE_INSTALL_PREFIX="$AliRootInst" \
            -DALIEN="$ALIEN_DIR" \
            -DROOTSYS="$ROOTSYS" \
            $FastJetFlag

      else

        # Any other configuration (no linker)
        SwallowProgress -f --pattern \
          'Bootstrapping AliRoot build with CMake' \
          cmake "$AliRootSrc" \
            -DCMAKE_C_COMPILER=`root-config --cc` \
            -DCMAKE_CXX_COMPILER=`root-config --cxx` \
            -DCMAKE_Fortran_COMPILER=`root-config --f77` \
            -DCMAKE_INSTALL_PREFIX="$AliRootInst" \
            -DALIEN="$ALIEN_DIR" \
            -DROOTSYS="$ROOTSYS" \
            $FastJetFlag

      fi

    fi

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

  Banner 'Installing AliPhysics...'
  Swallow -f 'Sourcing envvars' SourceEnvVars

  # AliPhysics variables: only ${ALICE_PHYSICS} needed
  # - ${ALICE_PHYSICS}: installation directory
  # - ${ALICE_PHYSICS}/../build: build directory
  # - ${ALICE_PHYSICS}/../src: source directory

  local AliPhysicsBase=$( dirname "${ALICE_PHYSICS}" )
  local AliPhysicsInst="$ALICE_PHYSICS"
  local AliPhysicsSrc="${AliPhysicsBase}/src"
  local AliPhysicsTmp="${AliPhysicsBase}/build"

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
        git clone http://git.cern.ch/pub/AliPhysics .
    fi
    AliPhysicsGit=$(cd "$AliPhysicsGit";pwd)

    SwallowProgress -f --pattern \
      'Updating list of remote AliPhysics Git branches' \
      git remote update origin --prune

    # Shallow copy with git-new-workdir
    if [[ ! -d "${AliPhysicsSrc}/.git" ]] ; then
      rmdir "$AliPhysicsSrc" > /dev/null 2>&1  # works if dir is empty
      SwallowProgress -f --pattern \
        "Creating a local clone for version ${ALIPHYSICS_VER}" \
        git-new-workdir "$AliPhysicsGit" "$AliPhysicsSrc" "$ALIPHYSICS_VER"
    fi

    Swallow -f 'Moving to local clone' cd "$AliPhysicsSrc"
    Swallow -f "Checking out AliPhysics version $ALIPHYSICS_VER" \
      git checkout "$ALIPHYSICS_VER"

    if [[ "$(git rev-parse --abbrev-ref HEAD)" != 'HEAD' ]] ; then
      # update only if on a branch: errors are fatal
      SwallowProgress -f --pattern \
        "Updating AliPhysics $ALIPHYSICS_VER from Git" git pull --rebase
    fi

  fi # end download

  if [[ "$DOWNLOAD_MODE" == '' || "$DOWNLOAD_MODE" == 'no' ]] ; then

    # Build AliPhysics

    Swallow -f 'Moving into AliPhysics build directory' cd "$AliPhysicsTmp"

    SwallowProgress -f --pattern \
      'Configuring AliPhysics with CMake' \
      cmake "$AliPhysicsSrc" \
        -DCMAKE_INSTALL_PREFIX="$AliPhysicsInst" \
        -DALIEN="$ALIEN_DIR" \
        -DROOTSYS="$ROOTSYS" \
        -DFASTJET="$FASTJET" \
        -DALIROOT="$ALICE_ROOT"

    SwallowProgress -f --percentage 'Building AliPhysics' make -j$MJ
    SwallowProgress -f --percentage 'Installing AliPhysics' make -j$MJ install

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
  Banner "Cleaning AliEn..."
  Swallow -f "Sourcing envvars" SourceEnvVars
  find "$ALICE_PREFIX" -maxdepth 1 -name 'alien.v*' -and -type d | \
  while read AliEnDir ; do
    AliEnVer=`basename "$AliEnDir"`
    AliEnVer=${AliEnVer:6}
    Swallow -f "Removing AliEn $AliEnVer" rm -rf "$AliEnDir"
  done
  Swallow -f "Removing symlink to latest AliEn $ALIEN_DIR" rm -f "$ALIEN_DIR"
}

# Clean up ROOT
function ModuleCleanRoot() {
  Banner "Cleaning ROOT..."
  Swallow -f "Sourcing envvars" SourceEnvVars
  Swallow "Checking if ROOT is really installed" [ -f "$ROOTSYS"/Makefile ] || return 0
  Swallow -f "Removing ROOT $ROOT_VER" rm -rf "$ROOTSYS"
}

# Clean up Geant3
function ModuleCleanGeant3() {
  Banner "Cleaning Geant3..."
  Swallow -f "Sourcing envvars" SourceEnvVars
  Swallow "Checking if Geant3 is really installed" [ -f "$GEANT3DIR"/Makefile ] || return 0
  Swallow -f "Removing Geant3 $G3_VER" rm -rf "$GEANT3DIR"
}

# Clean up Fastjet
function ModuleCleanFastJet() {
  Banner "Cleaning FastJet..."
  Swallow -f "Sourcing envvars" SourceEnvVars
  Swallow "Checking if FastJet is really installed" [ -f "$FASTJET/src/fastjet-$FASTJET_VER/configure" ] || return 0
  Swallow -f "Removing FastJet $FASTJET_VER" rm -rf "$FASTJET"
}

# Clean up AliRoot
function ModuleCleanAliRoot() {
  Banner 'Cleaning AliRoot...'

  local AliRootBase=$( dirname "${ALICE_ROOT}" )
  local AliRootInst="$ALICE_ROOT"
  local AliRootSrc="${AliRootBase}/src"
  local AliRootTmp="${AliRootBase}/build"

  Swallow -f 'Sourcing envvars' SourceEnvVars
  Swallow 'Checking if AliRoot is really there' [ -d "$AliRootTmp" ] || return 0
  Swallow -f 'Removing AliRoot build directory' rm -rf "$AliRootTmp"
  Swallow -f "Removing AliRoot install directory" rm -rf "$AliRootInst"
}

# Clean up AliPhysics
function ModuleCleanAliPhysics() {
  Banner 'Cleaning AliPhysics...'
  Swallow -f --error-msg 'Not yet implemented' \
    'Cleaning AliPhysics' false
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

  Banner 'Checking prerequisites...'
  Swallow -f 'Checking if on a 64 bit machine' [ `uname -m` == 'x86_64' ]
  Swallow -f --error-msg 'Command "git-new-workdir" cannot be found in your $PATH. Follow the instructions on the web to install it.' \
    'Checking for git-new-workdir script in $PATH' which git-new-workdir
  Swallow --fatal --error-msg 'You must source the alice-env.sh script and pick the tuple you wish to build first!' \
    'Checking if ALICE environment works and updating alice-env.sh' SourceEnvVars -u

}

# Install AliEn
function ModuleAliEn() {

  local ALIEN_TEMP_INST_DIR="/tmp/alien-temp-inst-$USER"
  local ALIEN_INSTALLER="$ALIEN_TEMP_INST_DIR/alien-installer"

  Banner "Installing AliEn..."
  Swallow -f "Creating temporary working directory" \
    mkdir -p "$ALIEN_TEMP_INST_DIR"
  local CURWD=`pwd`
  cd "$ALIEN_TEMP_INST_DIR"

  Swallow -f "Sourcing envvars" SourceEnvVars
  Swallow -f "Downloading AliEn installer" \
    Dl http://alien.cern.ch/alien-installer "$ALIEN_INSTALLER"
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
}

# Module to create prefix directory
function ModulePrepare() {
  local TF
  Banner "Creating directory structure..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  mkdir -p "$ALICE_PREFIX" 2> /dev/null

  if [ "$USER" == "root" ]; then
    Swallow -f "Creating ALICE software directory" [ -d "$ALICE_PREFIX" ]
    Swallow -f "Opening permissions of ALICE directory" \
      chmod 0777 "$ALICE_PREFIX"
  else
    TF="$ALICE_PREFIX/dummy_$RANDOM"
    touch "$TF" 2> /dev/null
    if [ $? != 0 ]; then
      Fatal "Not enough permissions: please run \"sudo $Cmd --prepare\""
    fi
    rm "$TF"
  fi

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
function Help() {
  local Cmd='bash <(curl -fsSL http://cern.ch/go/NcS7)'
  local C="\033[1m"
  local Z="\033[m"
  local R="\033[31m"
  local M="\033[35m"
  local A="\033[36m"
  echo ""
  echo "alice-install.sh -- by Dario Berzano <dario.berzano@cern.ch>"
  echo ""
  echo "Tries to perform automatic installation of the ALICE framework."
  echo "Installation procedure follows exactly the steps described on:"
  echo ""
  echo -e "  ${C}https://dberzano.github.io/alice/install-aliroot/manual${Z}"
  echo ""
  echo "Usage:"
  echo ""

  echo "  To create dirs (do it only the first time, as root if needed):"
  echo -e "    ${C}[sudo|su -c] $Cmd --prepare${Z}"
  echo ""

  echo "  To build/install/update something (multiple choices allowed):"
  echo -e "    ${C}$Cmd [--alien] [--root] [--geant3] [--fastjet] [--aliroot] [--ncores <n>] [--compiler [gcc|clang|/prefix/to/gcc]]${Z}"
  echo ""

  echo "  To build/install/update everything (do --prepare first):"
  echo -e "    ${C}$Cmd --all${Z}"
  echo ""

  echo "  To cleanup something (multiple choices allowed - data is erased!):"
  echo -e "    ${C}$Cmd [--clean-root] [--clean-geant3] [--clean-fastjet] [--clean-aliroot]${Z}"
  echo ""

  echo "  To cleanup everything:"
  echo -e "    ${C}$Cmd --clean-all${Z}"
  echo ""

  echo "  You can cleanup then install like this:"
  echo -e "    ${C}$Cmd --clean-root --root --ncores 2${Z}"
  echo ""

  echo "  To prepare some debug information for your system:"
  echo -e "    ${C}$Cmd --bugreport${Z}"

  echo "  The --compiler option is not mandatory; you can either specify gcc or"
  echo "  clang, or the prefix to a custom GCC installation."
  echo ""

  echo "  Note that build/install/update as root user is disallowed."
  echo "  With optional --ncores <n> you specify the number of parallel builds."
  echo "  If nothing is specified, the default value (#cores + 1) is used."
  echo ""

  echo "  You can also decide to download only, or build only (not for AliEn):"
  echo -e "    ${C}$Cmd [--all|...] [--no-download|--download-only]${Z}"
  echo ""

  SourceEnvVars > /dev/null 2>&1
  Rv=$?
  if [[ "$Rv" == 100 ]] ; then
    echo -e "${R}Please load your alice-env.sh script selecting the tuple you wish to install first!${Z}"
    echo -e "${R}Note: you might need to upgrade your alice-env.sh script before!${Z}"
  elif [[ "$Rv" != 0 ]] ; then
    echo -e "${R}Problem loading ${ALI_EnvScript} with tuple ${ALI_nAliTuple}.${Z}"
  else

    local ROOT_STR="$ROOT_VER"
    local G3_STR="$G3_VER"
    local ALICE_STR="$ALICE_VER"
    local FASTJET_STR="$FASTJET_VER"

    if [ "$ROOT_VER" != "$ROOT_SUBDIR" ]; then
      ROOT_STR="$ROOT_VER (subdir: $ROOT_SUBDIR)"
    fi

    if [ "$G3_VER" != "$G3_SUBDIR" ]; then
      G3_STR="$G3_VER (subdir: $G3_SUBDIR)"
    fi

    if [ "$FASTJET_VER" == '' ]; then
      FASTJET_STR="won't be installed"
    elif [ "$FASTJET_VER" != "$FASTJET_SUBDIR" ]; then
      FASTJET_STR="$FASTJET_VER (subdir: $FASTJET_SUBDIR)"
    fi

    if [ "$ALICE_VER" != "$ALICE_SUBDIR" ]; then
      ALICE_STR="$ALICE_VER (subdir: $ALICE_SUBDIR)"
    fi

    local BUILD_MODE_STR="$BUILD_MODE"
    if [ "$BUILD_MODE" == "custom-gcc" ]; then
      BUILD_MODE_STR="$BUILD_MODE (under $CUSTOM_GCC_PATH)"
    fi

    echo -e "${R}Specify one or more actions among: ${M}--all, --alien, --aliroot, --geant3, --root, --fastjet${Z}"
    echo
    echo -e "If you re-run this script with one or more actions now, the following configuration will be used:"
    echo
    echo -e "${M}ALICE environment script: ${A}${ALI_EnvScript}${Z}"
    echo -e "${M}Software installation directory: ${A}${ALICE_PREFIX}${Z}"
    echo
    echo -e "${M}You have selected tuple ${A}#${ALI_nAliTuple}${M}:${Z}"
    echo
    echo -e "  ${M}AliEn:        ${A}always the latest version${Z}"
    echo -e "  ${M}ROOT:         ${A}$ROOT_STR${M} (minimum supported version: ${A}${MIN_ROOT_VER_STR}${M})${Z}"
    echo -e "  ${M}Geant3:       ${A}$G3_STR${Z}"
    echo -e "  ${M}FastJet:      ${A}$FASTJET_STR${Z}"
    echo -e "  ${M}AliRoot Core: ${A}$ALICE_STR${Z}"
    echo
    echo -e "${M}Compiler: ${A}$BUILD_MODE_STR${M} (supported: ${A}${SUPPORTED_BUILD_MODES}${M})${Z}"
  fi
  echo ""

  # Error message, if any
  if [ "$1" != "" ]; then
    echo -e '>> \033[31m'$1'\033[m'
    echo ""
  fi

}

# Check if ROOT has OpenGL
function RootHasOpenGl() {
  root-config --features | grep -q opengl
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
    if [[ $OsVer -ge 12 ]] ; then
      # 12 = Mountain Lion (10.8)
      BUILDOPT_CPATH='/usr/X11/include'  # XQuartz
      ALIEN_INSTALL_TYPE='compile'
      MIN_ROOT_VER_STR='v5-34-18'
    fi
    if [[ $OsVer -ge 13 ]] ; then
      # 13 = Mavericks (10.9)
      SUPPORTED_BUILD_MODES='clang'
    fi
    if [[ $OsVer -ge 14 ]] ; then
      # 14 = Yosemite (10.10)
      MIN_ROOT_VER_STR='v5-34-22'
    fi
  elif [[ $KernelName == 'Linux' ]] ; then
    ALIEN_INSTALL_TYPE='compile'
    SUPPORTED_BUILD_MODES='gcc custom-gcc clang'
    OsName=`source $VerFile > /dev/null 2>&1 ; echo $DISTRIB_ID`
    OsVer=`source $VerFile > /dev/null 2>&1 ; echo $DISTRIB_RELEASE | tr -d .`
    if [ "$OsName" == 'Ubuntu' ] && [ "$OsVer" -ge 1110 ]; then
      BUILDOPT_LDFLAGS='-Wl,--no-as-needed'
    elif [ "$OsName" == 'LinuxMint' ] && [ "$OsVer" -ge 12 ]; then
      BUILDOPT_LDFLAGS='-Wl,--no-as-needed'
    fi
  fi

  MIN_ROOT_VER_NUM=$( ConvertVersionStringToNumber "$MIN_ROOT_VER_STR" )
  BUILD_MODE=`echo $SUPPORTED_BUILD_MODES | awk '{print $1}'`

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

  local DO_PREP=0
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

        #
        # Other targets
        #

        bugreport)
          DO_BUGREPORT=1
        ;;

        prepare)
          DO_PREP=1
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

  # How many build actions?
  let N_INST=DO_ALIEN+DO_ROOT+DO_G3+DO_FASTJET+DO_ALICE+DO_ALIPHYSICS
  let N_CLEAN=DO_CLEAN_ALIEN+DO_CLEAN_ROOT+DO_CLEAN_G3+DO_CLEAN_FASTJET+DO_CLEAN_ALICE+DO_CLEAN_ALIPHYSICS
  let N_INST_CLEAN=N_INST+N_CLEAN

  if [ $DO_PREP == 0 ] && [ $DO_BUGREPORT == 0 ] && \
     [ $N_INST_CLEAN == 0 ]; then
    Help "Nothing to do"
    exit 1
  elif [ $DO_PREP == 1 ] && [ $N_INST_CLEAN -gt 0 ]; then
    Help "Can't prepare and update/build/clean something at the same time"
    exit 1
  elif [ "$USER" == "root" ] && [ $N_INST_CLEAN -gt 0 ]; then
    Help "I'm refusing to continue the installation as root user"
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
  echo "Installation log files can be consulted on:"
  echo ""
  echo -e "  \033[34mstderr:\033[m $ERR"
  echo -e "  \033[34mstdout:\033[m $OUT"

  # Checking prerequisites
  ModuleCheckPrereq

  # Perform required actions
  if [ $DO_PREP == 1 ]; then
    ModulePrepare
  else
    SourceEnvVars > /dev/null 2>&1
    echo ""

    if [ $MJ == 1 ]; then
      echo "Building on single core (no parallel build)"
    else
      echo "Building using $MJ parallel threads"
    fi

    Banner 'Non-interactive installation begins: go get some tea and scones'

    # All modules
    [ $DO_CLEAN_ALIEN      == 1 ] && ModuleCleanAliEn
    [ $DO_ALIEN            == 1 ] && ModuleAliEn
    [ $DO_CLEAN_ROOT       == 1 ] && ModuleCleanRoot
    [ $DO_ROOT             == 1 ] && ModuleRoot
    [ $DO_CLEAN_G3         == 1 ] && ModuleCleanGeant3
    [ $DO_G3               == 1 ] && ModuleGeant3
    [ $DO_CLEAN_FASTJET    == 1 ] && ModuleCleanFastJet
    [ $DO_FASTJET          == 1 ] && ModuleFastJet
    [ $DO_CLEAN_ALICE      == 1 ] && ModuleCleanAliRoot
    [ $DO_ALICE            == 1 ] && ModuleAliRoot
    [ $DO_CLEAN_ALIPHYSICS == 1 ] && ModuleCleanAliPhysics
    [ $DO_ALIPHYSICS       == 1 ] && ModuleAliPhysics
  fi

  # Remove logs: if we are here, everything went right, so no need to see the
  # logs
  RemoveLogs

  echo ""
}

Main "$@"
