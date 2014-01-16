#!/bin/bash

################################################################################
### Benchmark configuration
################################################################################

# The tag to append to the output data filenames
TAG=${TAG:-"NONE"}

# Numer of instences to run concurrently
CINTS=${CINTS:-1}

# The benchmark command to execute
BENCH=${BENCH:-"perf bench --format=simple sched pipe -l1000000"}

# The FTrace plugin to use (by default just events)
TRACER=${TRACER:-""}
#TRACER=${TRACER:-function_graph}

# The FTrace events to trace
EVENTS=${EVENTS:-"sched:sched_switch sched:sched_process_fork sched:sched_process_latency sched_cbs:*"}

# The CPUs Sandbox where tests should be run
SBOX=${SBOX:-"/sys/fs/cgroup/sbox"}
if [[ ! -f ${SBOX}/cpuset.cpus ]]; then
	echo "ERROR: CPUs sandbox [$SBOX] not configured"
	exit -1
fi
CPUS=${CPUS:-`cat /sys/fs/cgroup/sbox/cpuset.cpus`}


################################################################################
### Do not touch under this line
################################################################################

TESTD=${TESTD:-`pwd`}
CHRT=${CHRT:-/home/derkling/bin/chrt}
TERM=${TERM:-gnome-terminal}


COLOR_WHITE="\033[1;37m"
COLOR_LGRAY="\033[37m"
COLOR_GRAY="\033[1;30m"
COLOR_BLACK="\033[30m"
COLOR_RED="\033[31m"
COLOR_LRED="\033[1;31m"
COLOR_GREEN="\033[32m"
COLOR_LGREEN="\033[1;32m"
COLOR_BROWN="\033[33m"
COLOR_YELLOW="\033[1;33m"
COLOR_BLUE="\033[34m"
COLOR_LBLUE="\033[1;34m"
COLOR_PURPLE="\033[35m"
COLOR_PINK="\033[1;35m"
COLOR_CYAN="\033[36m"
COLOR_LCYAN="\033[1;36m"
COLOR_RESET="\033[0m"

log_info()
{
  echo -e $*
}

log_title1()
{
  echo -e "$COLOR_WHITE...::::: $* $COLOR_RESET"
}

log_title2()
{
  echo -e "$COLOR_LGRAY*** $* $COLOR_RESET"
}

log_info()
{
  echo -e "$COLOR_GREEN$* $COLOR_RESET"
}

log_debug()
{
  echo -e "$COLOR_BLUE$* $COLOR_RESET"
}

log_warn()
{
  echo -e "$COLOR_PINK$* $COLOR_RESET"
}

################################################################################
### Utilities
################################################################################


sbox_to_cpulist() {
  CPULIST=${CPUS//,/ }
  echo "Expaning [$CPULIST]..."
  [[ $CPULIST == *-* ]] || return
  for R in $CPULIST; do
    if [[ $R != *-* ]]; then
      LIST+="$R "
      continue
    fi
    for C in `seq ${R/-/ }`; do
      LIST+="$C "
    done
  done
  CPULIST=$LIST
}
sbox_to_cpulist

################################################################################
### FTrace Utility Functions
################################################################################

TRACING=${TRACING:-/sys/kernel/debug/tracing}
FILTER=${FILTER:-tracepoints_sched_compare.txt}
OPTIONS=${OPTIONS:-print-parent sleep-time graph-time funcgraph-duration funcgraph-overhead funcgraph-cpu funcgraph-abstime funcgraph-proc}

trace_setup() {

  log_info "[CONF] Setup FTrace [128K] buffer size..."
  echo 131072 > $TRACING/buffer_size_kb
  # Tracer
  if [ "x$TRACER" != "x" ]; then
    log_info "[CONF] Setup FTrace [$TRACER] tracer..."
    echo $TRACER > $TRACING/current_tracer
    log_info "[CONF]  setup tracer options..."
    for o in $OPTIONS; do
      echo $o > $TRACING/trace_options
    done
    OPTS=`cat $TRACING/trace_options | sort | tr '\n' ' '`
    echo "   $OPTS"
    log_info "[CONF]  setup tracer filters..."
    for f in $(grep -v -e '^#' $FILTER); do
      echo $f >> $TRACING/set_ftrace_filter || \
        echo "   failed to setup [$f] filter/s"
    done
  fi
  # Events
  if [ "x$EVENTS" != "x" ]; then
    log_info "[CONF] Setup FTrace [$EVENTS] event/s..."
    echo > $TRACING/set_event
    echo "$EVENTS" > $TRACING/set_event
  fi

}

trace_start() {
  log_warn "===== Trace START ====="
  log_info "Command [$1]"
  echo 1 > $TRACING/tracing_on
}

trace_stop() {
  echo 0 > $TRACING/tracing_on
  log_warn "===== Trace  STOP ====="
}

trace_reset() {
  # Events
  if [ "x$EVENTS" != "x" ]; then
    log_debug "### Reset FTrace filters..."
    echo > $TRACING/set_ftrace_filter
  fi
  # Tracer
  if [ "x$TRACER" != "x" ]; then
    log_debug "### Reset FTrace tracer..."
    echo nop > $TRACING/current_tracer
  fi
}


################################################################################
### Scheduler specific testing
################################################################################

test_cbs() {
  log_info "[TEST] Running [$TAG] on CBS scheduler..."
  pushd $TESTD
  JOBS=''
  CMD="$CHRT -f 10
        taskset -c ${CPUS}
        $CHRT -c 0
        $BENCH"
  trace_start "$CMD"
  for I in `seq $CINTS`; do
    $CMD | tee cbs_trace_$TAG.log &
    JOBS+="`echo $!` "
    echo -en "$I instances running...\r"
  done
  popd

  log_debug "Waiting for tests PIDs: $JOBS..."
  wait $JOBS
  trace_stop
  trace-cmd extract &>/dev/null
  mv trace.dat cbs_trace_$TAG.dat
  cat > cbs_trace_$TAG.txt <<EOF
################################################################################
# Date:    `date`
# System:  `uname -a`
# CPUs:    $CPULIST
# CPUFreq: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor  | sort -u`
# CPU Hz:  `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq  | sort -u`
# Sched Features:
`cat /sys/kernel/debug/sched_features`
# Traced Events:
$EVENTS
################################################################################
# TAG:
$TAG
# BENCHMARK:
$BENCH
# COMMAND:
$CMD
EOF

}

test_fair() {
  log_info "[TEST] Running [$TAG] on FAIR scheduler..."
  pushd $TESTD
  JOBS=''
  CMD="$CHRT -f 10
        taskset -c ${CPUS}
        $CHRT -o 0
        $BENCH"
  trace_start "$CMD"
  for I in `seq $CINTS`; do
    $CMD | tee fair_trace_$TAG.log &
    JOBS+="`echo $!` "
    echo -en "$I instances running...\r"
  done
  popd

  log_debug "Waiting for tests PIDs: $JOBS..."
  wait $JOBS
  trace_stop
  trace-cmd extract &>/dev/null
  mv trace.dat fair_trace_$TAG.dat
  cat > fair_trace_$TAG.txt <<EOF
################################################################################
# Date:    `date`
# System:  `uname -a`
# CPUs:    $CPULIST
# CPUFreq: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor  | sort -u`
# CPU Hz:  `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq  | sort -u`
# Sched Features:
`cat /sys/kernel/debug/sched_features`
# Traced Events:
$EVENTS
################################################################################
# TAG:
$TAG
# BENCHMARK:
$BENCH
# COMMAND:
$CMD
EOF

}


################################################################################
### Test Function
################################################################################

trace_multi() {
  log_info "[CONF] Running [$TAG] tests with [$CINTS] instances..."

  trace_setup
  test_cbs
  trace_reset

  if [[ "$EVENTS" == *sched:* || "$TRACER" != "" ]]; then
    trace_setup
    test_fair
    trace_reset
  fi

}


################################################################################
### Trace Reporting Functions
################################################################################

report_sched_latency() {
  if [[ "$EVENTS" == *switch* && "$EVENTS" == *wakepu*  ]]; then
    return 1
  fi
  log_info "[DATA] Sched Latency ${1^^*}"
  trace-cmd report -i $1_trace_$TAG.dat \
    --cpu ${CPUS} -w -F "sched_switch, sched_wakeup.*" \
    &>/dev/null | tail -n4
  kernelshark $1_trace_$TAG.dat &
  $TERM -e "./trace_pager.sh -i $1_trace_$TAG.dat --cpu=${CPUS}" &
}

report_sched_time() {
  if [[ "$TRACER" != *function* ]]; then
    return 1
  fi
  log_info "[DATA] Sched Time ${1^^*}"
  rm -f $1_time_sched_$TAG.dat 2>/dev/null
  trace-cmd report -i $1_trace_$TAG.dat \
    --cpu ${CPUS} &>/dev/null | \
    tr -d ':' | \
    awk -v FILE=$1_time_sched_$TAG.dat '
          BEGIN {
            t0=0
            tmin=999999
            tmax=0
          }
          / schedule()/ {
            while ($0 !~ /\|  \}/) {
              if (!getline)
                next;
            };
            if (!t0)
              t0=$3
            t=$(NF-3);
            if (t>tmax)
              tmax=t
            if (t<tmin)
              tmin=t
            sum+=t;
            n++;
            print $3-t0 " " t >> FILE
          }
          END {
            if (n!=0)
              print n " " tmin " " tmax " " sum/n "[us]"
          }'
  if [ ! -f $1_trace_sched_$TAG.dat ]; then
    echo "Empty trace file."
    return
  fi
  gnuplot -e "
    set terminal pdf;
    set title 'Scheduling Time ($1)';
    set xlabel 'Time [s]';
    set ylabel 'log(schedule())';
    set output '$1_time_sched.pdf';
    set yrange [5:200];
    set logscale y;
    plot '$1_time_sched_$TAG.dat';"
}


################################################################################
### Complementary Tools generation
################################################################################

if [ ! -f trace_pager.sh ]; then
cat > trace_pager.sh <<EOF
#!/bin/bash
trace-cmd report \$* | less
EOF
chmod a+x trace_pager.sh
fi

if [ ! -f decompressor ]; then
cat > decompressor <<EOF
#!/bin/bash
DESTDIR=\`echo \$0 | sed 's/.bsx//'\`
ARCHIVE=\`awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0; }' \$0\`
mkdir \$DESTDIR || exit 1
tail -n+\$ARCHIVE \$0 | tar xj -C \$DESTDIR
cd \$DESTDIR
for C in $CPULIST; do
  echo "Dumping tables for CPU[\$C]..."
  ./dump_tables.sh \$C
done
echo "Plotting tables"
./plot_tables.py
cd ..
xdg-open \$DESTDIR
exit 0
__ARCHIVE_BELOW__
EOF
fi

################################################################################
### Main
################################################################################

clear
log_title1 "Trace Compare"

trace_multi

#report_sched_latency cb
#report_sched_time cbs
tar cjf cbs_trace_$TAG.tar.bz2 \
	cbs_trace_$TAG.txt \
	cbs_trace_$TAG.log \
	cbs_trace_$TAG.dat \
	dump_tables.sh \
	plot_tables.py

cat decompressor cbs_trace_$TAG.tar.bz2 > results_cbs_$TAG.bsx
chmod a+x results_cbs_$TAG.bsx

if [[ "$EVENTS" == *sched:* || "$TRACER" != "" ]]; then
  #report_sched_latency fair
  #report_sched_time fair
  tar cjf fair_trace_$TAG.tar.bz2 \
	  fair_trace_$TAG.txt \
	  fair_trace_$TAG.log \
	  fair_trace_$TAG.dat \
	  dump_tables.sh \
	  plot_tables.py
  cat decompressor fair_trace_$TAG.tar.bz2 > results_fair_$TAG.bsx
  chmod a+x results_fair_$TAG.bsx
fi

sleep 1
echo -e "\n\n\n"
