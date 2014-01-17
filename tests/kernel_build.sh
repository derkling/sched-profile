#!/bin/bash

KDIR=${KDIR:-'/usr/src/linux'}
BDIR=${BDIR:-'/tmp/schedtest_kernel_build'}
JOBS=${JOBS:-4}
TARGET=${TARGET:-''}

# Setup BUILD directory
[[ -d $BDIR ]] || mkdir $BDIR
rm -rf $BDIR/*

# Setup configuration file
cd $KDIR || exit -1
make mrproper $>/dev/null

# Make the kernel
cp arch/x86/configs/x86_64_defconfig $BDIR/.config
yes '' | make O=$BDIR oldconfig &>/dev/null
make O=$BDIR allnoconfig &>/dev/null
make O=$BDIR -j$JOBS $TARGET

