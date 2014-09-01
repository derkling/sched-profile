#!/bin/bash

CPU=${1:-"3"}

DATFILE="*_trace_*.dat"
DATFILE=`echo $DATFILE`
TXTFILE=${DATFILE/.dat/.txt}
TABFILE=${DATFILE/_trace_/_table_}
CPUID=`printf "%02d" $CPU`
RNDFILE=${TABFILE/.dat/_C${CPUID}_rounds.dat}
BRSFILE=${TABFILE/.dat/_C${CPUID}_bursts.dat}
LTSFILE=${TABFILE/.dat/_C${CPUID}_latencies.dat}
MIGFILE=${TABFILE/.dat/_C${CPUID}_migrations.dat}
EVTFILE=${TABFILE/.dat/_C${CPUID}_events.dat}
AEVFILE=${TABFILE/.dat/_Call_events.dat}


################################################################################
### Parsing Test Report file
get_test_configuration() {
grep -A1 "$1" $TXTFILE | tail -n1
}

EVENTS=`get_test_configuration "Traced Events:"`
BTAG=`get_test_configuration "# TAG:"`
BCMD=`get_test_configuration "# BENCHMARK:"`

################################################################################
### Round parsing
if [[ "$DATFILE" == *cbs_* && "$EVENTS" == *cbs_round* ]]; then

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

trace-cmd report --cpu $CPU $DATFILE 2>/dev/null | \
	tr '|[]' ' ' | ./parse_rounds.awk \
	> $RNDFILE

fi # DATFILE == cbs_*


################################################################################
### Burst parsing
if [[ "$DATFILE" == *cbs_* && "$EVENTS" == *cbs_burst* ]]; then

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

trace-cmd report --cpu $CPU $DATFILE 2>/dev/null | \
	tr '|[]' ' ' | ./parse_bursts.awk \
	> $BRSFILE

fi # DATFILE == cbs_*

################################################################################
### Latency parsing
if [[ "$EVENTS" == *_process_latency* ]]; then

cat > parse_latencies.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# Scheduling Latency\\n")
	printf("# %5s %25s %13s %13s %13s %3s\\n",
		"Burst", "Task", "Time[s]", "Delay[ns]", "Slice[ns]", "CPU")
}

/kswitcher_0-(.*)cpu_migrate_finish/ {
	target = \$8
	sub("0x", "", target)
	printf("################################################################################\n")
	printf("# %s\\n", \$0)
	if (target < 100) {
		cpu_base = 0
		printf("# Switched to [big] cluster\\n")
	} else {
		cpu_base = 4
		printf("# Switched to [LITTLE] cluster\\n")
	}
}

/sched_process_latency/ {
	task=\$1
	cpu=\$2+cpu_base
	timestamp=\$3
	delay=\$6
	slice=\$8
	#print ">>>>> " \$0
	printf("%7d %25s %13.6f %13d %13d %3d\\n",
		++i, task, timestamp, delay, slice, cpu)
}
EOF
chmod a+x parse_latencies.awk

# Latencies are dumped in a single file for all CPUs
LTSFILE=${TABFILE/.dat/_Call_latencies.dat}
[[ -f $LTSFILE ]] || \
trace-cmd report $DATFILE 2>/dev/null | \
	tr '|[]=' ' ' | ./parse_latencies.awk \
	> $LTSFILE

cat > parse_ctx_switches.awk <<EOF
#!/usr/bin/awk -f
# Jump comment lines
/#/ {
	next
}
# Parse latency events, which match 1:1 with sched_switch events
{
	timestamp = \$3
	cpu_id = \$6

	# Per CPU events
	cpu_ctx_count[cpu_id]++
	if (cpu_start[cpu_id] == 0)
		cpu_start[cpu_id] = timestamp
	cpu_end[cpu_id] = timestamp

	# Overall events
	trace_ctx_count++
	if (trace_start == 0)
		trace_start = timestamp
	trace_end = timestamp
}
# Report computed per-CPU and overall rates
END {

	printf("# Trace start: %13.3f, end: %13.3f\\n", trace_start, trace_end)
        printf("# Contex Switches Analysis\\n")
        printf("# %5s %25s %13s %13s\\n",
                "CPU", "Count", "Time[s]", "Rate[Ctx/s]")

	if (trace_start == 0) {
		printf("# No sched_switch data\\n")
		exit 1
	}

	for (i in cpu_start) {
		if (cpu_ctx_count[i] == 0)
			continue

		# Compute Ctx Switches timeframe and ratio
		ctx_time = cpu_end[i] - cpu_start[i]
		if (ctx_time == 0)
			continue
		ctx_ratio = cpu_ctx_count[i] / ctx_time

		printf("%7d %25d %13.3f %13.1f\\n",
		i, cpu_ctx_count[i], ctx_time, ctx_ratio)
	}

	ctx_time = trace_end - trace_start
	ctx_ratio = trace_ctx_count / ctx_time

	printf("%7d %25d %13.3f %13.1f\\n",
		9999, trace_ctx_count, ctx_time, ctx_ratio)

}
EOF
chmod a+x parse_ctx_switches.awk

# Context switches are dumped in a single file
# CPU ID = 9999 represents the average rate over all the CPUs
CTXFILE=${TABFILE/.dat/_Call_ctxrate.dat}
[[ -f $CTXFILE ]] || \
cat $LTSFILE | ./parse_ctx_switches.awk > $CTXFILE

fi # EVENTS == *_process_latency*

################################################################################
### Migration parsing
if [[ "$EVENTS" == *_migrate_task* ]]; then

cat > parse_migrations.awk <<EOF
#!/usr/bin/awk -f
BEGIN {
	printf("# Task Migrations\\n")
	printf("# %5s %19s %3s %14s %14s %3s %3s\\n",
		"Count", "Task", "I/O", "Time[s]", "Delta[us]", "Src", "Dst")
	last_migration = 0
}
/sched_migrate_task/ {
	#print ">>>>> " \$0
	# Get number of current CPU
	CPU=\$2+0
	# Consider only migrations in or out the current CPU
	if (CPU!=\$12 && CPU!=\$14)
		next
	# Discard migration events on the same CPU
	if (\$12==\$14)
		next
	# Keep track of first migration
	if (last_migration==0) {
		last_migration = \$3
		next
	}
	# Report delta since last migration
	if (CPU==\$12)
		migration="out"
	else
		migration="in"
	delta = \$3 - last_migration
	printf(" %5d %20s %3s %14.6f %14.6f %03d %03d\\n",
		++i, \$6, migration, \$3, delta, \$12, \$14)
	last_migration = \$3
}
EOF
chmod a+x parse_migrations.awk

trace-cmd report --cpu $CPU $DATFILE 2>/dev/null | \
	tr '|[]=' ' ' | ./parse_migrations.awk \
	> $MIGFILE

fi # EVENTS == *_migrate_task*


################################################################################
### Events dumping
trace-cmd report --cpu $CPU $DATFILE 2>/dev/null \
	> $EVTFILE

[[ -f $AEVFILE ]] && exit 0
trace-cmd report $DATFILE 2>/dev/null \
	> $AEVFILE

