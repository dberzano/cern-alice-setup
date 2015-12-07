#!/bin/bash

Cwd="$PWD"
cd "$(dirname "$0")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ContainerShort=$2; shift ;;
    --tag) ContainerTag=$2; shift ;;
    --workdir) WorkDir=$2; shift ;;
    --host) HostName=$2; shift ;;
    --badge) Badge=1 ;;
    *) echo "Unknown parameter: $1" >&2; exit 1 ;;
  esac
  shift
done

ContainerShort=${ContainerShort:-slc6}
ContainerTag=${ContainerTag:-latest}
Container="alisw/${ContainerShort}-builder:${ContainerTag}"

Arch="${ContainerShort}_$(uname -m|sed -e 's|_|-|g')"

WorkDirDefault=$PWD/$( date --utc +%Y%m%d-%H%M%S-$ContainerShort )
WorkDir=${WorkDir:-$WorkDirDefault}
[[ $WorkDir == 'auto' ]] && WorkDir="default-$ContainerShort"

HostName=${HostName:-$ContainerShort-$RANDOM}

[[ ${WorkDir:0:1} != / ]] && WorkDir="${Cwd}/${WorkDir}"

mkdir -p "$WorkDir"
UserId=`id -u`
GroupId=`id -g`
cat > "$WorkDir"/entrypoint.sh <<EoF
#!/bin/bash
groupadd builder -g $GroupId
useradd builder -u $UserId -g $GroupId
cd \$(dirname \$0)
ln -nfs /alisw/alidist .
ln -nfs /alisw/alibuild .
mkdir -p /work/sw
chown $UserId:$GroupId /work/sw
ln -nfs /mirror /work/sw/MIRROR
ln -nfs /work/globus /home/builder/.globus
RC=/etc/bashrc
NCORES=\$((\$(grep -c bogomips /proc/cpuinfo)*2))
[[ ! -e \$RC ]] && RC=/etc/bash.bashrc
echo -e "\nexport PS1='[$ContainerShort] \\h \\w \\\\$> '" >> \$RC
echo -e "\nalias aliBuild='cd /work;time alibuild/aliBuild --architecture $Arch --jobs \$NCORES --debug build'" >> \$RC
echo "> su builder"
echo "> alibuild/aliBuild --remote-store /remotestore::rw --architecture ${Arch} --jobs \$NCORES --debug build ROOT"
bash
EoF
chmod a+x "$WorkDir"/entrypoint.sh

docker pull $Container

[[ "$Badge" != '' ]] && printf "\e]1337;SetBadgeFormat=%s\a" \
                               $(echo -n "$ContainerShort" | base64)

echo "==> Architecture: $ContainerShort"
echo "==> Using as working dir: $WorkDir"
docker run \
  --rm -it \
  --privileged \
  -v /cvmfs:/cvmfs:ro \
  -v "$WorkDir":/work:rw \
  -v $HOME/alisw:/alisw:rw \
  -v $HOME/alisw/testenv/cache/remotestore:/remotestore:rw \
  -v $HOME/alisw/testenv/cache/mirror:/mirror:rw \
  ${HostName:+-h $HostName} \
  $Container \
  /work/entrypoint.sh

[[ "$Badge" != '' ]] && printf "\e]1337;SetBadgeFormat=\a"
