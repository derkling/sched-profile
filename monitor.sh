#!/bin/bash

TERM=${TERM:-gnome-terminal}

# Ensure the monitor is running on the HOST partition
echo $$ > cgroup/host/cgroup.procs
chrt -f 10 $TERM -geometry 139x70--9+-8 -e htop &
chrt -f 10 $TERM -geometry 139x29+-9+-8 -e 'watch -n1 "grep \"cbs_rq\[3\" -A32 /proc/sched_debug"' &
chrt -f 10 $TERM -geometry 139x29+-9+-8 -e 'watch -n1 "grep \"rt_rq\[3\" -A25 /proc/sched_debug"' &
chrt -f 11 $TERM -geometry 139x29--9-16 &
