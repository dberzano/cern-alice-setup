#!/bin/bash

Cwd="$PWD"
cd "$(dirname "$0")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ContainerShort=$2 ;;
    --tag) ContainerTag=$2 ;;
    --workdir) WorkDir=$2 ;;
    --host) HostName=$2 ;;
    *) echo "Unknown parameter: $1" >&2; exit 1 ;;
  esac
  shift 2
done

ContainerShort=${ContainerShort:-slc6}
ContainerTag=${ContainerTag:-latest}
Container="alisw/${ContainerShort}-builder:${ContainerTag}"

WorkDirDefault=$PWD/$( date --utc +%Y%m%d-%H%M%S-$ContainerShort )
WorkDir=${WorkDir:-$WorkDirDefault}

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
echo -e "\nexport PS1='[$ContainerShort] \\h \\w \\\\$> '" >> /etc/bashrc
echo -e "\nalias aliBuild='cd /work;alibuild/aliBuild --architecture $ContainerShort --jobs 50 --debug build'" >> /etc/bashrc
echo "> su builder"
echo "> alibuild/aliBuild --remote-store /remotestore::rw --architecture ${ContainerShort}_x86-64 --jobs 50 --debug build ROOT"
bash
EoF
chmod a+x "$WorkDir"/entrypoint.sh

docker pull $Container

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
