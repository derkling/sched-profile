#!/bin/bash

TRACING=${TRACING:-/sys/kernel/debug/tracing}
TRACER=${TRACER:-function_graph}
EVENTS=${EVENTS:-"sched:*"}

echo "Setup tracer [$TRACER]..."
echo nop > $TRACING/current_tracer
echo $TRACER > $TRACING/current_tracer

echo "Setup events [$EVENTS]..."
echo > $TRACING/set_event
echo "$EVENTS" > $TRACING/set_event

echo "Tracing command [$*]..."
echo $$ > $TRACING/set_ftrace_pid
exec $*

