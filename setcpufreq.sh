#!/bin/bash

usage() {
echo "Params: $#"
echo -e "\nUsage $0 [d|p]\n\n"
}

GOV="ondemand"
check_params() {
if [ $# -lt 1 ]; then
	usage && exit 1
fi

case $1 in
d) GOV='ondemand'
;;
p) GOV='performance'
;;
s) GOV='powersave'
;;
*) usage && exit 1
;;
esac

}

# Check root permission
check_root() {
# Make sure only root can run our script
if [ "x`id -u`" != "x0" ]; then
	echo -e "\nThis script must be run as root\n\n"
	exit 1
fi
}

check_root
check_params $@

CPUS=`grep processor /proc/cpuinfo | cut -d: -f2`

echo "Setting CPUfreq governor to [$GOV]..."
for P in $CPUS; do
	echo $GOV > /sys/devices/system/cpu/cpu$P/cpufreq/scaling_governor
done

echo "Current governor set to:"
for P in $CPUS; do
	echo -n "CPU$P: " && cat /sys/devices/system/cpu/cpu$P/cpufreq/scaling_governor
done

