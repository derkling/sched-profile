#!/bin/bash


SCHED=${1:-"cbs"}
CPUS=${2:-"3"}


### Round parsing
cat > parse_rounds.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# CBS Rounds\\n")
	printf("# Round %13s %13s %8s %8s %8s | %3s %8s %8s %12s %12s\\n",
		"Time[s]", "RQTime[ns]", "Lw" , "Rt", "Re", "Nr", "Lw", "Rt_SP", "Rt_corr", "Rt_next")
}
/cbs_round/ {
	#print ">>>>> " \$0
	printf(" %6d %13.6f %13d %8d %8d %8d | %3d %8d %8d %12d %12d\\n",
		++i, \$3, \$6, \$9, \$11, \$14, \$17, \$19, \$21, \$24, \$26)
}
EOF
chmod a+x parse_rounds.awk

trace-cmd report --cpu $CPUS ${SCHED}_trace.dat 2>/dev/null | \
	tr ':=' '  ' | ./parse_rounds.awk \
	> ${SCHED}_rounds.dat


### Round parsing
cat > parse_bursts.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# CBS Bursts\\n")
	printf("# Burst %19s %13s %13s | %8s %8s %8s %8s %8s %8s\\n",
		"Task", "Time[s]", "SETime[ns]", "Rquota", "Tt_SP", "Te", "Tn", "Tb", "Tt")
}
/cbs_burst/ {
	#print ">>>>> " \$0
	printf(" %5d %20s %13.6f %13d | %8d %8d %8d %8d %8d %8d\\n",
		++i, \$1, \$3, \$6, \$9, \$12, \$14, \$16, \$18, \$20)
}
EOF
chmod a+x parse_bursts.awk

trace-cmd report --cpu $CPUS ${SCHED}_trace.dat 2>/dev/null | \
	tr ':=' '  ' | ./parse_bursts.awk \
	> ${SCHED}_bursts.dat

trace-cmd report --cpu $CPUS ${SCHED}_trace.dat 2>/dev/null \
	> ${SCHED}_events.dat


