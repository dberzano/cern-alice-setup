#!/bin/bash -e
TMP=$(mktemp -d /tmp/makeflow-$UID-XXXXX)
cd "$(dirname "$0")"
NTASKS=$1
[[ "$NTASKS" == '' ]] && NTASKS=3 || shift
{
  printf 'INPUT=input_data.txt\nSCRIPT=./myjob.sh\n'
  echo -n "results.txt:"
  for ((I=1; I<=NTASKS; I++)); do printf " results_%03d.txt" $I; done
  printf '\n\tLOCAL cat'
  for ((I=1; I<=NTASKS; I++)); do printf " results_%03d.txt" $I; done
  printf ' > results.txt\n'
  for ((I=1; I<=NTASKS; I++)); do
    printf 'results_%03d.txt: $INPUT $SCRIPT\n' $I
    printf '\t$SCRIPT $INPUT %03d > results_%03d.txt\n' $I $I
  done
} > Makeflow
echo 'this is the input data' > input_data.txt
{
  echo 'INPUT=$(cat $1)'
  echo 'shift'
  echo 'echo my job has been invoked on $(hostname) with parameters $@ and it says $INPUT'
  echo 'sleep 120'
} > myjob.sh
chmod +x myjob.sh
echo "*** Working under $TMP ***"
exec makeflow "$@"
