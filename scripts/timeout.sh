#!/usr/bin/env bash
# Runs a command as `timeout` does, exiting 124 once it has had its limit: timeout.sh SECONDS COMMAND... Its clock
# counts only the seconds the command could run: a host running suites and builds beside it queues it for a CPU, a GPU
# shared with other work holds it at the driver's open until there is room or stops it while the GPU is lent out, and
# those seconds are not the command's.
set -u
limit=$(($1 * 100))
shift
pid='' stop=''
trap 'stop=1; [ -n "$pid" ] && kill "$pid" 2>/dev/null' TERM INT HUP
"$@" &
pid=$!
if [ -n "$stop" ]; then kill "$pid" 2>/dev/null; fi
declare -A queued=()
used=0
read -r at _ </proc/uptime
at=${at/./}
while kill -0 "$pid" 2>/dev/null; do
  sleep 1
  read -r now _ </proc/uptime
  now=${now/./}
  # A thread waiting on another that waits for a CPU is held by that queue too, so the second's most-queued thread
  # stands for the process.
  most=0 held=0
  for task in /proc/"$pid"/task/*; do
    w=
    read -r w 2>/dev/null <"$task/wchan"
    if [[ $w == *fanotify* ]]; then held=1; fi
    read -r _ q _ 2>/dev/null <"$task/schedstat" || continue
    if [ -n "${queued[$task]:-}" ] && [ $((q - queued[$task])) -gt "$most" ]; then most=$((q - queued[$task])); fi
    queued[$task]=$q
  done
  read -r stat 2>/dev/null <"/proc/$pid/stat" || stat=
  stat=${stat##*) }
  if [ "$held" = 0 ] && [ "${stat%% *}" != T ]; then
    elapsed=$((now - at))
    most=$((most / 10000000))
    if [ "$most" -lt "$elapsed" ]; then used=$((used + elapsed - most)); fi
  fi
  at=$now
  if [ "$used" -ge "$limit" ]; then kill "$pid" 2>/dev/null; fi
done
code=0
wait "$pid" || code=$?
if [ "$used" -ge "$limit" ]; then exit 124; fi
exit "$code"
