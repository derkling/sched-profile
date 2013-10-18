#!/usr/bin/python
""" Scheduler Testing and Benchmark Reporting

(c) 2013, Patrick Bellasi <derkling@gmail.com>
Licensed under the terms of the GNU GPL License version 2

This is a...
"""

import sys
import getopt
import os
import fnmatch
import tempfile
import subprocess
import math
import time
import platform
import multiprocessing
import logging
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gs
from datetime import datetime

################################################################################
### Initialization and Environment Checking
################################################################################

if os.geteuid() != 0:
    print("#\n# This scripts requires ROOT permission to properly setup CPUFreq during tests.")
    sys.exit(2)


################################################################################
### System Utilities
################################################################################

def get_cpus_count():
    return multiprocessing.cpu_count()


def get_cpufreq_governor():
    return subprocess.Popen(["cat",
    "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"],
    stdout=subprocess.PIPE).stdout.readline().rstrip()


def get_platform_description():

    """Get a description of the platform (CPU, HW/SW versions)"""

    # Get CPUs description
    plat = platform.uname()
    with open('/proc/cpuinfo') as f:
        for line in f:
            if line.strip():
                data = line.rstrip('\n')
                # Check for CPU model
                if data.startswith('model name'):
                    model_name = data.split(':')[1]
                # Check for HT support
                if data.startswith('cpu cores'):
                    if (data.split(':')[1] > 1):
                        ht = " (HT)"
                    break

    cpuSystem = str(cpuCores) + "x" + model_name + ht
    #if (platf[3].find("SMP") != -1):
    #    cpuSystem += " (SMP)"
    pltVersion = plat[0] + " v" + plat[2] + ", " + plat[4]

    return (cpuSystem, pltVersion)


################################################################################
### System configuration
################################################################################

cpuCores = get_cpus_count()
cpuGovernor = get_cpufreq_governor()
(cpuSystem, pltVersion) = get_platform_description()

# Internal configuration flags
conf_sche = "cfs"
conf_inst = 2
conf_plot = 0
conf_runs = 1
conf_show = 0
conf_trgt = 0
conf_verb = 0


################################################################################
### Samples Collection and Statistics
################################################################################

class Stats():
    def __init__(self):
        self.ssum   = .0
        self.ssum2  = .0
        self.scount =  0

    def do_stats(self):
        self.savg = (self.ssum  / self.scount)
        self.svar = (self.ssum2 / self.scount) - (self.savg * self.savg)
        self.sstd = (math.sqrt(self.svar))
        self.sste = (self.sstd / math.sqrt(self.scount))
        self.sc95 = (1.96 * self.sste)
        self.sc99 = (2.58 * self.sste)

    def set_data(self, ssum, ssum2, scount):
        self.ssum   = ssum
        self.ssum2  = ssum2
        self.scount = scount
        self.do_stats()

    def add_sample(self, sample):
        self.ssum   += sample
        self.ssum2  += (sample * sample)
        self.scount += 1

    def get_count(self):
        return self.scount

    def get_avg(self):
        return self.savg

    def get_var(self):
        return self.svar

    def get_std(self):
        return self.std

    def get_ste(self):
        return self.ste

    def get_c95(self):
        return self.sc95

    def get_c99(self):
        return self.sc99

    def get_stats(self):
        self.do_stats()
        return (self.scount, self.savg, self.svar, self.sstd, self.sste, self.sc95, self.sc99)



################################################################################
### Test Configuration, Execution and Plotting
################################################################################

class Test():
    def __init__(
            self, label="A Test Name", description="A Test Description",
            command=(), instances=-1, runs=30, sched="cfs"):
        """Configured a new test"""

        if (instances == -1):
            instances = 4 * cpuCores

        # Keep track of test configuration
        self.label   = label
        self.desc    = description
        self.command = command
        self.insts   = instances
        self.runs    = runs
        self.sched   = sched.upper()
        if (self.sched == "CFS"):
            self.sched_switch="-o"
        else:
            self.sched_switch="-c"

        # setup temporary data file
        self.timestamp = datetime.fromtimestamp(time.time())
        self.strtstamp  = self.timestamp.strftime("%Y%m%d_%H%M%S")
        self.fname = self.timestamp.strftime("./test_"+self.sched+"_"+self.strtstamp+"_"+self.label+".dat")
        self.fdata = open(self.fname, "w")

        # Setup Test Timestamping report format
        self.time_values =  "Real  CtxF  CtxV  Sig"
        self.time_format =  "%e    %c    %w    %k "
        self.time_ftype  = (  1,    0,    0,    0  )

        self.cpuscount = multiprocessing.cpu_count()

        self.cpufreqgov = subprocess.Popen(["cat",
            "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"],
                    stdout=subprocess.PIPE).stdout.readline().rstrip()
        self.cpufreqcur = subprocess.Popen(["cat",
            "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"],
                    stdout=subprocess.PIPE).stdout.readline().rstrip()

        self.metrics = ("tt", "rt", "ctxf", "ctxv", "sigc")

    def __del__(self):
        self.fdata.close()

    def test(self):
        """Run one instance of the configured test and collect generated output"""
        # /usr/bin/time -f "$TIME_FORMAT" <TEST> 2>&1 | tail -n1
        self.perf_insts.append(subprocess.Popen(
            ["taskset", "-c", conf_trgt ] +
            ["/usr/bin/time", "-f", self.time_format ] +
            ["/home/derkling/bin/chrt", self.sched_switch, "0"] +
            self.command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False))

    def dump(self):
        """ Generate a test header and dump it on console"""
        # Dump header on logfile
        self.fdata.write("#"*80+"\n")
        self.fdata.write("# Benchmark              : %s\n" % (self.label))
        self.fdata.write("#    %s\n"                       % (self.desc))
        self.fdata.write("# Scheduler              : %s\n" % (self.sched))
        self.fdata.write("# Maximum instances      : %d\n" % (self.insts))
        self.fdata.write("# Number or runs         : %d\n" % (self.runs))
        self.fdata.write("# Number of CPUs         : %d\n" % (self.cpuscount))
        self.fdata.write("# CPUfreq governor       : %s\n" % (self.cpufreqgov))
        self.fdata.write("# CPUfreq frequency (Hz) : %s\n" % (self.cpufreqcur))
        self.fdata.write("# Test date              : %s\n" % (self.timestamp.strftime('./%Y-%m-%d %H:%M:%S')))
        self.fdata.write("#\n")
        self.fdata.flush()

        # Report logfile header on console
        subprocess.Popen(["cat", self.fname]).wait()

        # Dump statisicts header on logfile
        fheader = "# paris"
        for m in self.metrics:
            fheader += " %8.7s_avg %7.6s_var %7.6s_std %7.6s_ste %7.6s_c95 %7.6s_c99" % (m, m, m, m, m, m)
        self.fdata.write(fheader+"\n")
        self.fdata.write("#"+"="*(len(fheader)-1)+"\n")

        # Dump statistics headed on console
        cheader = "# paris"
        for m in self.metrics:
            cheader += " %8.7s_avg %7.6s_c99" % (m, m)
        print cheader
        print "#"+"="*(len(cheader)-1)

    def run(self):
        """Run the configured test"""
        logging.debug("Test " + self.label + " output on: " + self.fname);
        self.dump()

        for max_insts in range(self.insts):
            print "%7d ...\r" % (max_insts+1),

            # reset total time counter
            stats = {}
            stats["tt"] = Stats()
            stats["rt"] = Stats()
            stats["tf"] = Stats()
            stats["tv"] = Stats()
            stats["ts"] = Stats()

            for run in range(self.runs):
                # setup insts list
                self.perf_insts=[]

                rt_start = time.time()

                for task in range(max_insts+1):
                    self.test()

                for p in self.perf_insts:
                    # wait for task pair to finish and ...
                    p.wait()

                    # ... collect task execution time and their sum
                    time_str = p.stderr.readline()
                    (ttime, tctxf, tctxv, tsigc) = [t(s) for t,s in zip((float,int,int,int), time_str.split())]

                    # Add samples to statistics
                    stats["tt"].add_sample(ttime)
                    stats["tf"].add_sample(tctxf)
                    stats["tv"].add_sample(tctxv)
                    stats["ts"].add_sample(tsigc)

                    #print "%9f => %9f" % (ttime, tt_sum)
                    #print "="*78

                # Collect run execution time and their sum
                rt_end   = time.time()
                rtime    = (rt_end - rt_start)
                stats["rt"].add_sample(rtime)

            # for run

            count = stats['tt'].get_count()
            fstats = "%7d " % (count/self.runs)
            cstats = "%7d " % (count/self.runs)

            for s in ('tt', 'rt', 'tf', 'tv', 'ts'):
                (count, avg, var, std, ste, c95, c99) = stats[s].get_stats()

                ffmt = "%12.1f %11.1f %11.1f %11.1f %11.1f %11.1f "
                cfmt = "%12.1f %11.1f "
                if (s=='tt' or s=='rt'):
                    ffmt = "%12.9f %11.9f %11.9f %11.9f %11.9f %11.9f "
                    cfmt = "%12.9f %11.9f "

                # Format stats for logfile
                fstats += ffmt % (avg, var, std, ste, c95, c99)
                # Format stats for console
                cstats += cfmt % (avg, c99)

            self.fdata.write(fstats+"\n")
            print cstats

        # for max_insts

        self.fdata.flush()
        logging.info("Test " + self.label + " data: " + self.fname)
        return self.fname


    def plot(self, datafile=""):

        if (datafile==""):
            datafile=self.fname

        if (conf_verb):
            logging.debug("Parsing " + datafile + "...");

        data = np.loadtxt(datafile)

        # Setup graph geometry, axis and legend

        logging.debug("Plotting...")

        # Plot for Task and Run Completon time
        fig = plt.figure()
        fig.suptitle("Test " + self.label + " Analysis", fontsize=18)
        fig.suptitle("("+" ".join(self.command)+")", fontsize=11, y=.94)
        fig.suptitle(cpuSystem, fontsize=10, y=.91)
        fig.suptitle(pltVersion + ", " + self.sched, fontsize=10, y=.88)

        grids = gs.GridSpec(2,1,height_ratios=[3,1])
        plt_t = fig.add_subplot(grids[0])
        fig.subplots_adjust(top=.85)

        plt_u = fig.add_subplot(grids[1])
        plt_u.set_ybound(0,1)

        # Compute fairness index and test-/run-time
        ui = []
        xi = [c[0]  for c in data]
        tt = [c[1]  for c in data]
        te = [c[6]  for c in data]
        rt = [c[7]  for c in data]
        re = [c[12] for c in data]
        for x in range(len(data)):
            ui.append(1 - (tt[x] / rt[x]))

        # Add Test and Run Completion times
        time_plots = [
                plt_t.errorbar(xi, tt, te),
                plt_t.errorbar(xi, rt, re)]
        plt_t.legend(time_plots, ["Task time", "Run time"], loc=4, prop={'size':11})
        plt_t.set_ylabel("Time [s]")

        index_plots = [
                plt_u.bar(xi, ui)]
        plt_u.legend(index_plots, ["Unfairness index"], loc=1, prop={'size':11})
        plt_u.set_xlabel("Number of task instances")
        plt_u.set_ylabel("Index")
        plt_u.axis(ymin=0, ymax=1)

        graph_name = datafile.replace(".dat", ".pdf")
        logging.info("Plotting "+graph_name+"...")
        plt.savefig(
                graph_name,
                papertype = 'a3',
                format = 'pdf')

        if conf_show:
            plt.show()


################################################################################
### Tests Utility Functions
################################################################################

def run_all_tests():
    """Run all the supported tests and plot coresponding data"""

    logging.debug("# Running all tests...")

    # Perf PIPE
    logging.debug("# Test: Perf PIPEs...")
    cmd = ["perf", "bench", "--format=simple", "sched", "pipe", "-l1000000"]
    #cmd = ["perf", "bench", "--format=simple", "sched", "pipe", "-l100000"]
    test = Test(
            "PerfPIPE",
            "Perf PIPE benchmark (" + " ".join(cmd) + ")",
            cmd, conf_inst, conf_runs, conf_sche)
    test.run()
    test.plot()

    # Perf MESSAGING
    logging.debug("# Test: Perf MESSAGINGs...")
    cmd = ["perf", "bench", "--format=simple", "sched", "messaging", "-p", "-g1", "-l5000"]
    #cmd = ["perf", "bench", "--format=simple", "sched", "messaging", "-p", "-g1", "-l100"]
    test = Test(
            "PerfMESSAGING",
            "Perf MESSAGING benchmark (" + " ".join(cmd) + ")",
            cmd, 2, conf_runs, conf_sche)
    test.run()
    test.plot()

    return 0

################################################################################
### Main and Command Line Processing
################################################################################

class Usage(Exception):
    def __init__(self, msg):
        self.msg = msg

def process(arg):
    """Command Line Arguments Processing"""
    logging.debug("Processing argument " + arg)


def main(argv=None):
    global conf_sche
    global conf_inst
    global conf_plot
    global conf_runs
    global conf_show
    global conf_trgt
    global conf_verb

    if argv is None:
        argv = sys.argv
    try:
        try:
            opts, args = getopt.getopt(argv[1:], "hci:pr:st:v",
                    ["help", "cbs", "instances", "plot", "runs", "show", "target-cpus", "verbose"])
        except getopt.error, msg:
            raise Usage(msg)
        # process options
        for o, a in opts:
            if o in ("-h", "--help"):
                print __doc__
                return 0
            if o in ("-c", "--cbs"):
                conf_sche = "cbs"
                continue
            if o in ("-i", "--instances"):
                conf_inst = int(a)
                continue
            if o in ("-p", "--plot"):
                conf_plot = 1
                return 0
            if o in ("-r", "--runs"):
                conf_runs = int(a)
                continue
            if o in ("-s", "--show"):
                conf_show = 1
                continue
            if o in ("-t", "--target-cpus"):
                conf_trgt = a
                continue
            if o in ("-v", "--verbose"):
                conf_verb = 1
                continue
        # process arguments
        for arg in args:
            process(arg) # process() is defined elsewhere

    except Usage, err:
        print >>sys.stderr, err.msg
        print >>sys.stderr, "for help use --help"
        return 2

    # Setup Logging
    if (conf_verb):
        logging.basicConfig(format="%(asctime)s %(message)s", level=logging.DEBUG)

    if (conf_plot):
        return plot_all_tests()

    return run_all_tests()

if __name__ == "__main__":
    sys.exit(main())

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
