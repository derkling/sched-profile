#!/bin/bash

################################################################################
### Benchmark configuration
################################################################################

# The tag to append to the output data filenames
TAG=${TAG:-"NONE"}

# The scheduler to run the test for
SCHED=${SCHED:-"all"}

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
# CPUFreq Utilities
################################################################################

# Check root permission
check_root() {
  # Make sure only root can run our script
  if [ "x`id -u`" != "x0" ]; then
    echo -e "ERROR: This script must be run as root\n\n"
    exit 1
  fi
}

set_cpufreq() {

  case $1 in
    d) GOV='ondemand'
      ;;
    i) GOV='interactive'
      ;;
    p) GOV='performance'
      ;;
    s) GOV='powersave'
      ;;
    u) GOV='userspace'
      ;;
    *) echo "Invalid CPUFreq setup [$1]"
      exit 1
      ;;
  esac

  # Requested frequency for on-demand governor
  # if not speficied the minimum frequency will be configured
  FREQ=${2:-0}

  CUR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)

  check_root

  CPUS=`grep processor /proc/cpuinfo | cut -d: -f2`

  if [ $CUR != $GOV ]; then
    echo "Setting CPUfreq governor to [$GOV]..."
    local P
    for P in $CPUS; do
      echo $GOV > /sys/devices/system/cpu/cpu$P/cpufreq/scaling_governor
    done
  fi

  if [ $GOV == "userspace" ]; then
    echo "Setting CPUfreq userspace frequency to [$FREQ]..."
    local P
    for P in $CPUS; do
      echo $FREQ > /sys/devices/system/cpu/cpu$P/cpufreq/scaling_setspeed
    done
  fi

  echo "CPUFreq Configuration:"
  local P
  for P in $CPUS; do
    GOV=$(cat /sys/devices/system/cpu/cpu$P/cpufreq/scaling_governor)
    FRQ=$(cat /sys/devices/system/cpu/cpu$P/cpufreq/scaling_cur_freq)
    AVL=$(cat /sys/devices/system/cpu/cpu$P/cpufreq/scaling_available_frequencies)
    echo "CPU$P: $GOV @ $FRQ ($AVL)"
  done

}



################################################################################
### FTrace Utility Functions
################################################################################

TRACING=${TRACING:-/sys/kernel/debug/tracing}
FILTER=${FILTER:-tracepoints_sched_compare.txt}
OPTIONS=${OPTIONS:-print-parent sleep-time graph-time funcgraph-duration funcgraph-overhead funcgraph-cpu funcgraph-abstime funcgraph-proc}

trace_setup() {

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
  echo 1 > $TRACING/free_buffer
  log_info "[CONF] Setup FTrace [10M] buffer size..."
  echo 10240 > $TRACING/buffer_size_kb
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

trace_collect() {
  RESULTS=$1 # The basename for trace and report filenames

  trace-cmd extract &>/dev/null
  mv trace.dat $RESULTS.dat
  cat > $RESULTS.txt <<EOF
################################################################################
# Date:    `date`
# System:  `uname -a`
# CPUs:    $CPULIST
# CPUFreq: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor  | sort -u`
# CPU Hz:  `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq  | sort -u`
# Sched Features:
`[[ ! -f /sys/kernel/debug/sched_features ]] || cat /sys/kernel/debug/sched_features`
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
### Scheduler specific testing
################################################################################

test_sched() {
  RESULTS=$1 # The basename for experiment produced filenames

  log_info "[TEST] Running [$TAG] on ${SCHED^^} scheduler..."

  if [[ $SCHED==iks ]]; then
    # Force system on powersave to know in which OP we are starting the execution
    set_cpufreq s
  fi

  if [[ "x$CMD"="x" ]]; then
    log_info "Press a key to START the test: "
    read KEY
    # Manual test (start)
    echo 'Manual triggered caputre' > ${SCHED,,}_trace_$TAG.log
  fi

  # Start tracing
  trace_start "$CMD"

  if [[ $SCHED==iks ]]; then
    # Switch back to interactive governor once the trace has been started, thus
    # get all the cluster UP migrations on the trace
    set_cpufreq i
    sleep 1
  fi

  if [[ "x$CMD"="x" ]]; then
    log_info "Press a key to STOP the test: "
    read KEY
    # Manual test (stop)
  else
    pushd $TESTD
    JOBS=''
    for I in `seq $CINTS`; do
      $CMD | tee ${RESULTS}.log &
      JOBS+="`echo $!` "
      echo -en "$I instances running...\r"
    done
    popd
    log_debug "Waiting for tests PIDs: $JOBS..."
    wait $JOBS
  fi

  trace_stop

  trace_collect $RESULTS

}

test_cbs() {
  SCHED=cbs
  RESULTS="cbs_trace_$TAG"
  CMD="$CHRT -f 10
        taskset -c ${CPUS}
        $CHRT -c 0
        $BENCH"

  trace_setup
  test_sched $RESULTS
  trace_reset
}

test_fair() {
  SCHED=fair
  RESULTS="fair_trace_$TAG"
  CMD="$CHRT -f 10
        taskset -c ${CPUS}
        $CHRT -o 0
        $BENCH"

  trace_setup
  test_sched $RESULTS
  trace_reset
}

test_iks() {
  CMD="$BENCH"
  CPUS='0-7'
  EVENTS='cpu_migrate_finish sched_process_latency'
  RESULTS="iks_trace_$TAG"
  SCHED=iks

  trace_setup
  test_sched $RESULTS
  trace_reset
}

test_hmp() {
  CMD="$BENCH"
  CPUS='0-7'
  # EVENTS='sched_wakeup sched_switch cpu_migrate_finish sched_task_runnable_ratio sched_process_fork sched_process_free'
  EVENTS='sched_process_latency'
  RESULTS="hmp_trace_$TAG"
  SCHED=hmp

  trace_setup
  test_sched $RESULTS
  trace_reset
}


################################################################################
### Test Function
################################################################################

trace_multi() {
  log_info "[CONF] Running [$TAG] tests with [$CINTS] instances..."


  if [[ "$SCHED" == *hmp* ]]; then
    test_hmp
  fi

  if [[ "$SCHED" == *iks* ]]; then
    test_iks
  fi

  if [[ "$SCHED" == cbscomp || "$SCHED" == *cbs* || \
	  "$TRACER" != "" ]]; then
    test_cbs
  fi

  if [[ "$SCHED" == cbscomp || "$SCHED" == *fair* || \
	  "$EVENTS" == *sched:* || "$TRACER" != "" ]]; then
    test_fair
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

if [[ "$SCHED" == all || "$SCHED" == *cbs* || \
	"$TRACER" != "" ]]; then
  log_info "CBS Summmary"
  #report_sched_latency cb
  #report_sched_time cbs
fi

if [[ "$SCHED" == all || "$SCHED" == *fair* || \
	"$EVENTS" == *sched:* || "$TRACER" != "" ]]; then
  log_info "FAIR Summary"
  #report_sched_latency fair
  #report_sched_time fair
fi

# Packing test results
tar cjf ${SCHED,,}_trace_$TAG.tar.bz2 \
        ${SCHED,,}_trace_$TAG.txt \
        ${SCHED,,}_trace_$TAG.log \
        ${SCHED,,}_trace_$TAG.dat \
        dump_tables.sh \
        plot_tables.py
cat decompressor ${SCHED,,}_trace_$TAG.tar.bz2 > results_${SCHED,,}_$TAG.bsx
chmod a+x results_${SCHED,,}_$TAG.bsx
log_info "Test results: results_${SCHED,,}_$TAG.bsx"

# Cleanup packaged files
rm -f ${SCHED,,}_*

sleep 1
echo -e "\n\n\n"
