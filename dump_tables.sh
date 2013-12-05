#!/bin/bash

SCHED=${1:-"cbs"}
CPUS=${2:-"3"}

DATFILE="${SCHED}_trace_*.dat"
DATFILE=`echo $DATFILE`
RNDFILE=${DATFILE/.dat/_rounds.dat}
BRSFILE=${DATFILE/.dat/_bursts.dat}
LTSFILE=${DATFILE/.dat/_latencies.dat}
EVTFILE=${DATFILE/.dat/_events.dat}

################################################################################
### Round parsing
cat > parse_rounds.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# CBS Rounds\\n")
	printf("# Round %13s %13s %8s %8s %3s %8s | %3s %8s %8s %3s %12s %12s %12s %14s %14s\\n",
		"Time[s]", "RQTime[ns]", "Lw" , "Rt", "Clp", "Re", "Nr", "Lw", "Rt_SP", "Sat", "Rt_corr", "Rt_cold", "Rt_next", "RStart", "REnd")
}
/cbs_round/ {
	#print ">>>>> " \$0
	printf(" %6d %13.6f %13d %8d %8d %3s %8d | %3d %8d %8d %3s %12d %12d %12d %14d %14d\\n",
		++i, \$3, \$6, \$8, \$10, \$11, \$13, \$15, \$17, \$19, \$20, \$22, \$24, \$26, \$28, \$30)
}
EOF
chmod a+x parse_rounds.awk

trace-cmd report --cpu $CPUS $DATFILE 2>/dev/null | \
	tr '|[]' ' ' | ./parse_rounds.awk \
	> $RNDFILE

################################################################################
### Round parsing
cat > parse_bursts.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# CBS Bursts\\n")
	printf("# Burst %19s %13s %13s | %8s %3s %8s %8s %8s %8s %3s %8s %14s %14s\\n",
		"Task", "Time[s]", "SETime[ns]", "Rquota", "Rei", "Tt_SP", "Te", "Tn", "Tb", "Src", "Tt", "BStart", "BStop")
}
/cbs_burst/ {
	#print ">>>>> " \$0
	printf(" %5d %20s %13.6f %13d | %8d %3s %8d %8d %8d %8d %3s %8d %14d %14d\\n",
		++i, \$1, \$3, \$6, \$8, \$9, \$11, \$13, \$15, \$17, \$18, \$20, \$22, \$24)
}
EOF
chmod a+x parse_bursts.awk

trace-cmd report --cpu $CPUS $DATFILE 2>/dev/null | \
	tr '|[]' ' ' | ./parse_bursts.awk \
	> $BRSFILE

################################################################################
### Latency parsing
cat > parse_latencies.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# Scheduling Latency\\n")
	printf("# %5s %19s %13s %13s %13s\\n",
		"Burst", "Task", "Time[s]", "Delay[ns]", "Slice[ns]")
}
/sched_process_latency/ {
	#print ">>>>> " \$0
	printf(" %5d %20s %13.6f %13d %13d\\n",
		++i, \$1, \$3, \$6, \$8)
}
EOF
chmod a+x parse_latencies.awk

trace-cmd report --cpu $CPUS $DATFILE 2>/dev/null | \
	tr '|[]=' ' ' | ./parse_latencies.awk \
	> $LTSFILE

################################################################################
### Events dumping
trace-cmd report --cpu $CPUS $DATFILE 2>/dev/null \
	> $EVTFILE

