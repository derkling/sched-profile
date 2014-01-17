#!/bin/bash

TESTS=${TESTS:-"all"}

################################################################################
# Testing Scheduler Migration Support
################################################################################

# Migrations - Compiling a small kernel
if [[ "$TESTS" == all || "$TESTS" == *mig* || "$TESTS" == kbuild_small ]]; then
  echo ".:: Test [kbuild_small]..."
  TAG="MIG-KBUILD_SMALL" \
  TARGET="kernel/" \
  BENCH="./tests/kernel_build.sh" \
  EVENTS="sched:sched_migrate_task sched:sched_process_fork sched:sched_process_exec sched:sched_wakeup sched:sched_wakeup_new" \
  chrt -f 12 ./trace_compare.sh
fi

# Migrations - Compiling a small kernel
if [[ "$TESTS" == all || "$TESTS" == *mig* || "$TESTS" == kbuild_full ]]; then
  echo ".:: Test [kbuild_full]..."
  TAG="MIG-KBUILD_FULL" \
  TARGET="vmlinux" \
  BENCH="./tests/kernel_build.sh" \
  EVENTS="sched:sched_migrate_task sched:sched_process_fork sched:sched_process_exec sched:sched_wakeup sched:sched_wakeup_new" \
  chrt -f 12 ./trace_compare.sh
fi

