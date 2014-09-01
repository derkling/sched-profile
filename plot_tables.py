#!/usr/bin/python

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gs
import matplotlib as mpl
import string
import math
import glob
import sys
import re
import gc

################################################################################
#  Configuration
################################################################################

# 1: show the plots, 0: plot on PDF
show_plot = 0

# Plots font size
fsize = 10

################################################################################
#   Statistics Accumulator
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
#   Round Metrics of interest
################################################################################
# Record data:
# Round       Time[s]    RQTime[ns]       Lw       Rt       Re |  Nr       Lw    Rt_SP      Rt_corr      Rt_next
metrics = {
# Label          Name                    Description                              Column
 "Time":      [ "Time [s]",             "Workload completion time [s]",              1,   0],
 "RQ_time":   [ "RQ run time",          "",                                          2,   1],
 "Lw_prev":   [ "RQ weight (previous)", "",                                          3,   2],
 "Rt_prev":   [ "Round time",           "",                                          4,   3],
 "Re_prev":   [ "Round error",          "",                                          6,   4],
 "Nr_next":   [ "SE next round",        "",                                          8,   5],
 "Lw_next":   [ "RQ weight (next)",     "",                                          9,   6],
 "Sp_next":   [ "Round time SP",        "",                                         10,   7],
 "Co_next":   [ "Round correction",     "",                                         12,   8],
 "Cd_next":   [ "Round correction old", "",                                         13,   9],
 "Rt_next":   [ "Round time next",      "",                                         14,  10],
 "Rt_start":  [ "Round time start",     "",                                         15,  11],
 "Rt_end":    [ "Round time (exp) end", "",                                         16,  12],
# "Rc_prev":   [ "Round time clamped",   "",                                          5,   4],
# "Sa_next":   [ "Round time saturated", "",                                         11,   9],
}

mColumns = [c[2] for c in metrics.values()]
def mName(m):
    return metrics[m][0]
def mDesc(m):
    return metrics[m][1]
def mData(m):
    return data[:, metrics[m][3]] 

def plot_rounds(rounds_data):
    global data

    # Loading data from file
    data = np.loadtxt(rounds_data, usecols=sorted(mColumns))
    mTime = data[:, 0]

    # Setup figure
    fig = plt.figure()

    grids = gs.GridSpec(3,1,height_ratios=[2,1,1])
    fig.subplots_adjust(
        left   = 0.10,
        bottom = 0.10,
        right  = 0.95,
        top    = 0.95,
        wspace = 0.20,
        hspace = 0.40,
    )

    # ax = plt.gca()
    # ax.get_xaxis().get_major_formatter().set_useOffset(False)

    ################################################################################
    # Plot RoundTime
    ################################################################################
    p1 = fig.add_subplot(grids[0])

    l1, = p1.plot(mTime, mData("Sp_next"), 'r')
    l2, = p1.plot(mTime, mData("Rt_prev"), 'b')

    # Setup X-Axis
    # p1.set_xlabel("Time [s]")
    p1.set_ylabel("[tq]")

    # Setup Graph title
    p1.set_title("Round Time Control")
    p1.grid(True)

    # Add legend
    p1.legend([l1, l2], ["Set Point", "Measured"], prop={'size':fsize})

    ################################################################################
    # Plot RoundTime Error
    ################################################################################

    p2 = fig.add_subplot(grids[1])

    l1, = p2.plot(mTime, mData("Re_prev"), 'b')

    # Setup X-Axis
    # p2.set_xlabel("Time [s]")
    p2.set_ylabel("[tq]")

    # Setup Graph title
    # p2.set_title("Round Time Error")
    p2.grid(True)

    # Add legend
    p2.legend([l1], ["Error"], prop={'size':fsize})

    ################################################################################
    # Plot RoundTime Correction
    ################################################################################

    p3 = fig.add_subplot(grids[2])

    l1, = p3.plot(mTime, mData("Co_next"), 'b')

    # Setup X-Axis
    p3.set_xlabel("Time [s]")
    p3.set_ylabel("")

    # Setup Graph title
    # p3.set_title("Round Correction")
    p3.grid(True)

    # Add legend
    p3.legend([l1], ["Correction"], prop={'size':fsize})

    for item in (
        [p1.title, p1.xaxis.label, p1.yaxis.label]  +
        [p2.title, p2.xaxis.label, p2.yaxis.label]  +
        [p3.title, p3.xaxis.label, p3.yaxis.label]  +
        p1.get_xticklabels() + p1.get_yticklabels() +
        p2.get_xticklabels() + p2.get_yticklabels() +
        p3.get_xticklabels() + p3.get_yticklabels()):
        item.set_fontsize(fsize)

    # Plot the graph...
    if show_plot:
        plt.show()
    else:
        rounds_figure = string.replace(rounds_data, ".dat", ".pdf")
        # print "Plotting [", rounds_figure, "]..."
        plt.savefig(
                rounds_figure,
                papertype = 'a3',
                format = 'pdf',
                )

for rounds_data in glob.glob('cbs_table_*_rounds.dat'):
    print "Plotting rounds [", rounds_data, "]..."
    plot_rounds(rounds_data)

################################################################################
#   Bursts Metrics of interest
################################################################################
# Record data:
# Burst                Task       Time[s]    SETime[ns] |   Rquota    Tt_SP       Te       Tn       Tb       Tt
metrics = {
# Label          Name                    Description                  Column  Index
# 'Task':     [ 'Task',                 'Task name',                  1,      0],
 'Time':      [ 'Time [s]',             'Burst completion time [s]',  2,      0],
 'Tr_quota':  [ 'Round quota',          '',                           5,      1],
 'Tb_sp':     [ 'Burst SP',             '',                           7,      2],
 'Tb_error':  [ 'Burst error',          '',                           8,      3],
 'Tb_next':   [ 'Burst next',           '',                           9,      4],
 'Tb_timer':  [ 'Burst assigned',       '',                          10,      5],
 'Tb':        [ 'Burst measured',       '',                          12,      6],
 'Tb_start':  [ 'Burst time start',     '',                          13,      7],
 'Tb_stop':   [ 'Burst time (exp) end', '',                          14,      8],
# 'Tb_reinit': [ 'Burst reinit',       '',                            6,      2],
}

mColumns = [c[2] for c in metrics.values()]
def mName(m):
    return metrics[m][0]
def mDesc(m):
    return metrics[m][1]
def mData(t,m):
    idx = metrics[m][3]
    return [d[idx] for d in data[t]]
def mTime(t):
    idx = metrics['Time'][3]
    return [d[idx] for d in data[t]]

def plot_bursts(bursts_data):
    global data

    # Data Loading loop
    time_start = 0;
    data = {}
    infile = open(bursts_data, 'r')
    # infile = open('test.dat', 'r')
    for line in infile:
        if line[0] == '#':
            continue
        values = str.split(line)
        e = values[1]
        m = [values[i] for i in sorted(mColumns)]
        if (e not in data.keys()):
            data[e] = []
        data[e].append(m)
        if (time_start == 0):
            time_start = m[1]

    # print data
    # print mData('hb_ctl-32254', 'BT')
    # print mData('hb_tx_001_00-32276', 'Time')
    # print "Applications: ", len(data.keys())

    # print "Columns: ", mColumns
    # print "Data: ", mData('wlg-3818', "Tb_sp")
    # exit(0)

    tasks_count = len(data.keys())

    # Setup figure geometry
    fig_size = (720, tasks_count * 720 / 5)
    fig_dpi = 300
    fig_inches  = (
        5 * fig_size[0] / fig_dpi,
        5 * fig_size[1] / fig_dpi,
    )

    # Setup figure
    fig = plt.figure(figsize=fig_inches, dpi=fig_dpi)

    grids = gs.GridSpec(tasks_count, 2)
    fig.subplots_adjust(
        left   = 0.10,
        bottom = 0.05,
        right  = 0.95,
        top    = 0.95,
        wspace = 0.30,
        hspace = 0.30,
    )

    # Application specifica data plotting
    plot_id = 0
    for task in sorted(data.keys()):

        # print 'Plotting taks: ', task, ' @ time: ', mTime(task)
        # print 'Tb_sp',    mData(task, 'Tb_sp')
        # print 'Tb',       mData(task, 'Tb')
        # print 'Tb_error', mData(task, 'Tb_error')
        # print 'Tb_next',  mData(task, 'Tb_next')

        ################################################################################
        # Plot Round Time SP and Measured
        ################################################################################
        p1 = fig.add_subplot(grids[plot_id])

        l1, = p1.plot(mTime(task), mData(task, 'Tb_sp'), 'r')
        l2, = p1.plot(mTime(task), mData(task, 'Tb'),    'b')
        # print 'Taks (' + task + ') Tb_SP: ', mData(task, 'Tb_sp')
        # print 'Taks (' + task + ') Tb: ', mData(task, 'Tb')

        # Setup X-Axis
        # p1.set_xlabel("Time [s]")
        p1.set_ylabel('[tq]')

        # Setup Graph title
        p1.set_title('Burst Time Action (' + task +')')
        p1.grid(True)

        # Add legend
        p1.legend([l1, l2], ['Set Point', 'Measured'], prop={'size':fsize})

        ################################################################################
        # Plot Round Time Error and Next
        ################################################################################
        p2 = fig.add_subplot(grids[plot_id+1])

        l1, = p2.plot(mTime(task), mData(task, 'Tb_error'), 'r')
        l2, = p2.plot(mTime(task), mData(task, 'Tb_next'),  'g')
        # print 'Taks (' + task + ') Tb_error: ', mData(task, 'Tb_error')
        # print 'Taks (' + task + ') Tb_next: ', mData(task, 'Tb_next')

        # Setup X-Axis
        # p1.set_xlabel("Time [s]")
        p2.set_ylabel('[tq]')

        # Setup Graph title
        p2.set_title('Burst Time Control (' + task + ')')
        p2.grid(True)

        # Add legend
        p2.legend([l1, l2], ['Error', 'Next'], prop={'size':fsize})

        plot_id += 2

        for item in (
            [p1.title, p1.xaxis.label, p1.yaxis.label]  +
            [p2.title, p2.xaxis.label, p2.yaxis.label]  +
            p1.get_xticklabels() + p1.get_yticklabels() +
            p2.get_xticklabels() + p2.get_yticklabels()):
            item.set_fontsize(fsize)

    # Plot the graph...
    if show_plot:
        plt.show()
    else:
        bursts_figure = string.replace(bursts_data, ".dat", ".pdf")
        # print "Plotting [", bursts_figure, "]..."
        plt.savefig(
                bursts_figure,
                orientation = 'portrait',
                format = 'pdf',
                )

for bursts_data in glob.glob('cbs_table_*_bursts.dat'):
    print "Plotting bursts [", bursts_data, "]..."
    plot_bursts(bursts_data)

################################################################################
#   Latency Metrics of interest
################################################################################
# Record data:
# Burst                Task       Time[s]     Delay[ns]     Slice[ns]
metrics = {
# Label          Name                    Description                  Column  Index
# 'Task':     [ 'Task',                 'Task name',                   1,      0],
 'Time':      [ 'Time [s]',             'Burst completion time [s]',   2,      0],
 'Delay':     [ 'Delay [ns]',           'Ready task RQ delay [ns]',    3,      1],
 'Slice':     [ 'Slice [ns]',           'Running task CPU slice [ns]', 4,      2],
 'CPU':       [ 'CPU',                  'CPU Latency [ns]',            5,      3],
}
mColumns = [c[2] for c in metrics.values()]

# Overall statistics on big tasks
data = {}
delay_stats = {}
slice_stats = {}
# Per task statistics
tasks_data = {}
tasks_delay_stats = {}
tasks_slice_stats = {}
# Per cpu statistics
cpus_data = {}
cpus_delay_stats = {}
cpus_slice_stats = {}

# Metrics access utilities
def mName(m):
    return metrics[m][0]
def mDesc(m):
    return metrics[m][1]
def mData(view,t,m):
    idx = metrics[m][3]
    if view=='Tasks':
        return [d[idx] for d in tasks_data[t]]
    if view=='Cpus':
        return [d[idx] for d in cpus_data[t]]
    # by default, return overall metrics
    return [d[idx] for d in data[t]]
def mStats(view, metric, plot_id):
    if (view == 'Tasks'):
        if (metric == 'Delay'):
            return tasks_delay_stats[plot_id].get_stats()
        return tasks_slice_stats[plot_id].get_stats()
    if (view == 'Cpus'):
        if (metric == 'Delay'):
            return cpus_delay_stats[plot_id].get_stats()
        return cpus_slice_stats[plot_id].get_stats()
    # By default, return overall metrics
    if (metric == 'Delay'):
        return delay_stats[plot_id].get_stats()
    return slice_stats[plot_id].get_stats()
def mTime(view, t):
    idx = metrics['Time'][3]
    if (view == 'Tasks'):
        return [d[idx] for d in tasks_data[t]]
    if (view == 'Cpus'):
        return [d[idx] for d in cpus_data[t]]
    return [d[idx] for d in data[t]]



def plot_latencies(latencies_data):
    global data, delay_stats, slice_stats
    global tasks_data, tasks_delay_stats, tasks_slice_stats
    global cpus_data, cpus_delay_stats, cpus_slice_stats

    # # Load big-tasks list
    # Initialize overall data
    data['Overall'] = []
    delay_stats['Overall'] = Stats()
    slice_stats['Overall'] = Stats()

    # Data Loading loop
    time_start = 0;
    infile = open(latencies_data, 'r')
    # infile = open('test.dat', 'r')
    for line in infile:
        if line[0] == '#':
            continue
        values = str.split(line)
        task = values[1]
        m = [values[i] for i in sorted(mColumns)]
        data['Overall'].append(m)

        mdelay = float(m[metrics['Delay'][3]])
        mslice = float(m[metrics['Slice'][3]])
        delay_stats['Overall'].add_sample(mdelay)
        slice_stats['Overall'].add_sample(mslice)

        # per TASK stats
        if (task not in tasks_data.keys()):
            tasks_data[task] = []
            tasks_delay_stats[task] = Stats()
            tasks_slice_stats[task] = Stats()
        tasks_data[task].append(m)
        tasks_delay_stats[task].add_sample(mdelay)
        tasks_slice_stats[task].add_sample(mslice)

        # per CPU stats
        cpu = m[metrics['CPU'][3]]
        if (cpu not in cpus_delay_stats.keys()):
            cpus_data[cpu] = []
            cpus_delay_stats[cpu] = Stats()
            cpus_slice_stats[cpu] = Stats()
        cpus_data[cpu].append(m)
        cpus_delay_stats[cpu].add_sample(mdelay)
        cpus_slice_stats[cpu].add_sample(mslice)

        if (time_start == 0):
            time_start = m[1]

    if (len(data['Overall']) == 0):
        print "   No data collected for [" + latencies_data + "]"
        return

    plot_latencies_per(latencies_data, 'Tasks')
    plot_latencies_per(latencies_data, 'Cpus')
    plot_latencies_per(latencies_data, 'Overall')

    # print data
    # print mData('Task', 'hb_ctl-32254', 'BT')
    # print mData('Task', 'hb_tx_001_00-32276', 'Time')
    # print "Applications: ", len(tasks_data.keys())

    # print "Columns: ", mColumns
    # print "Data: ", mData('Task', 'wlg-3818', "Tb_sp")
    # exit(0)

def plot_latencies_per(latencies_data, view):
    global data, delay_stats, slice_stats
    global tasks_data, tasks_delay_stats, tasks_slice_stats
    global cpus_data, cpus_delay_stats, cpus_slice_stats

    if (view == 'Tasks'):
        plot_data = tasks_data
    elif (view == 'Cpus'):
        plot_data = cpus_data
    else:
        plot_data = data


    # Setup output names
    latencies_figure = string.replace(latencies_data, '.dat', '_'+view.lower()+'.pdf')
    latencies_report = string.replace(latencies_figure, '.pdf', '.report')
    report_file = open(latencies_report, 'w')
    report_file.write("# %24s | %25s | %25s |\n" % (view, 'Delay', 'Slice'))
    report_file.write("# %24s | %12s %12s | %12s %12s |\n" % ('', 'Avg', 'Ci99', 'Avg', 'Ci99'))

    # Compute number of plots in that view
    plots_count = len(plot_data.keys())
    if (plots_count == 1):
        plots_count = 3

    # Setup figure geometry
    fig_size = (720, plots_count * 720 / 5)
    fig_dpi = 300
    fig_inches  = (
        5 * fig_size[0] / fig_dpi,
        5 * fig_size[1] / fig_dpi,
    )

    # Setup figure
    fig = plt.figure(figsize=fig_inches, dpi=fig_dpi)

    grids = gs.GridSpec(plots_count, 2)
    fig.subplots_adjust(
        left   = 0.10,
        bottom = 0.05,
        right  = 0.95,
        top    = 0.95,
        wspace = 0.30,
        hspace = 0.30,
    )

    # Application specific data plotting
    plot_id = 0
    for plot_key in sorted(plot_data.keys()):

        # print 'Plotting [',view, ']: ', plot_key, ' @ time: ', mTime(view, plot_key)
        # print 'Delay', mData(view, plot_key, 'Delay')
        # print 'Slice', mData(view, plot_key, 'Slice')

        ################################################################################
        # Plot Tasks Delay (once ready to run)
        ################################################################################
        p1 = fig.add_subplot(grids[plot_id])

        l1, = p1.plot(mTime(view, plot_key), mData(view, plot_key, 'Delay'), 'r+ ')

        (count, avg, var, std, ste, c95, c99) = mStats(view, 'Delay', plot_key)
        plt.axhline(y=avg, linewidth=1, color='g')
        plt.axhspan(max(1,avg-c99), avg+c99, facecolor='g', alpha=0.2)
        plt.axhspan(max(1,avg-(2*std)), avg+(2*std), facecolor='y', alpha=0.1)
        plt.axhspan(max(1,avg-(1*std)), avg+(1*std), facecolor='y', alpha=0.2)

        # Setup X-Axis
        # p1.set_xlabel("Time [s]")
        p1.set_ylabel('[ns]')
        p1.set_ylim(ymin=1, ymax=1000*1000000)
        p1.set_yscale('log')

        # Setup Graph title
        p1.set_title('Task(s) RQ Delay (' + plot_key +')')
        p1.grid(True)

        # Add legend
        # p1.legend([l1], ['RQ Delay'], prop={'size':fsize})

        # Report delay stats
        report_file.write("%26s   %12.3f %12.3f" % (plot_key, avg, c99))

        ################################################################################
        # Plot Tasks Timeslice
        ################################################################################
        p2 = fig.add_subplot(grids[plot_id+1])

        l1, = p2.plot(mTime(view, plot_key), mData(view, plot_key, 'Slice'), 'b+ ')
        (count, avg, var, std, ste, c95, c99) = mStats(view, 'Slice', plot_key)
        plt.axhline(y=avg, linewidth=1, color='g')
        plt.axhspan(max(1,avg-c99), avg+c99, facecolor='g', alpha=0.2)
        plt.axhspan(max(1,avg-(2*std)), avg+(2*std), facecolor='y', alpha=0.1)
        plt.axhspan(max(1,avg-(1*std)), avg+(1*std), facecolor='y', alpha=0.2)

        # Setup X-Axis
        # p1.set_xlabel("Time [s]")
        p2.set_ylabel('[ns]')
        p2.set_ylim(ymin=1, ymax=1000*1000000)
        p2.set_yscale('log')

        # Setup Graph title
        p2.set_title('Task(s) Running Slice (' + plot_key + ')')
        p2.grid(True)

        # Add legend
        #p2.legend([l1], ['CPU Slice'], prop={'size':fsize})

        # Report slice stats
        report_file.write("   %12.3f %12.3f\n" % (avg, c99))

        plot_id += 2

        for item in (
            [p1.title, p1.xaxis.label, p1.yaxis.label]  +
            [p2.title, p2.xaxis.label, p2.yaxis.label]  +
            p1.get_xticklabels() + p1.get_yticklabels() +
            p2.get_xticklabels() + p2.get_yticklabels()):
            item.set_fontsize(fsize)

    report_file.close()

    # Plot the graph...
    if show_plot:
        plt.show()
    else:
        latencies_figure = string.replace(latencies_data, '.dat', '_'+view.lower()+'.pdf')
        # print "Plotting [", latencies_figure, "]..."
        plt.savefig(
                latencies_figure,
                orientation = 'portrait',
                format = 'pdf',
                )

    # Clean-up all the memory
    fig.clf()
    plt.close()
    gc.collect()


# Plotting tasks latencies
for latencies_data in glob.glob('**_latencies.dat'):
    print "Plotting latencies [", latencies_data, "]..."
    plot_latencies(latencies_data)


################################################################################
#   Migration Metrics of interest
################################################################################
# Record data:
# Burst                Task       Time[s]     Delay[ns]     Slice[ns]
metrics = {
# Label          Name                    Description                  Column  Index
# 'Task':     [ 'Task',                 'Task name',                    1,      0],
 'Time':      [ 'Time [s]',             'Task migration time [s]',      3,      0],
 'Delta':     [ 'Delta [us]',           'Time last migration [us]',     4,      1],
 'Src':       [ 'Src CPU',              'Departing CPU',                5,      2],
 'Dst':       [ 'Dst CPU',              'Arrival CPU',                  6,      3],
}
mColumns = [c[2] for c in metrics.values()]

# The regex to match a CPU id within a migration filename, e.g.
# fair_table_MIG-WLG-B3P2I1_C07_migrations.dat
#                            ^^
#                            ||
#                    CPU Id to be matched
migcpu_regex = re.compile("(?<=_C)(?P<cpu_id>.*?)(?=_)")

def parse_migrations(migrations_data):
    global data

    # Getting CPU id
    match = migcpu_regex.search(migrations_data)
    cpu_id = 'C' + match.group('cpu_id')

    # Data Loading loop
    infile = open(migrations_data, 'r')
    # infile = open('test.dat', 'r')
    for line in infile:
        if line[0] == '#':
            continue
        values = str.split(line)
        m = [values[i] for i in sorted(mColumns)]
        if (cpu_id not in data.keys()):
            data[cpu_id] = []
            delta_stats[cpu_id] = Stats()
        data[cpu_id].append(m)
        # print "Sample: ", m, "\ndelta: ", metrics['Delta'][3], " => ", float(m[metrics['Delta'][3]])
        delta_stats[cpu_id].add_sample(float(m[metrics['Delta'][3]]))


def plot_migrations():
    cpus_count = len(data.keys())

    # Setup figure geometry
    fig_size = (720, cpus_count * 720 / 5)
    fig_dpi = 300
    fig_inches  = (
        5 * fig_size[0] / fig_dpi,
        5 * fig_size[1] / fig_dpi,
    )

    # Setup figure
    fig = plt.figure(figsize=fig_inches, dpi=fig_dpi)

    grids = gs.GridSpec(cpus_count, 2)
    fig.subplots_adjust(
        left   = 0.10,
        bottom = 0.05,
        right  = 0.95,
        top    = 0.95,
        wspace = 0.30,
        hspace = 0.30,
    )

    # Application specifica data plotting
    plot_id = 0
    for cpu in sorted(data.keys()):

        # print 'Plotting CPU: ', cpu, ' @ time: ', mTime(cpu)
        # print 'Delta', mData(cpu, 'Delta')

        ################################################################################
        # Plot Migration Interarrival events
        ################################################################################
        p1 = fig.add_subplot(grids[plot_id])

        l1, = p1.plot(mTime(cpu), mData(cpu, 'Delta'), 'r+ ')
        # print 'CPU (' + cpu + ') Delta: ', mData(cpu, 'Delta')

        # print "Delta(", cpu, "): ", delta_stats[cpu].get_stats()
        (count, avg, var, std, ste, c95, c99) = delta_stats[cpu].get_stats()
        plt.axhline(y=avg, linewidth=1, color='g')
        plt.axhspan(avg-c99, avg+c99, facecolor='g', alpha=0.2)
        plt.axhspan(max(0.000001,avg-(2*std)), avg+(2*std), facecolor='y', alpha=0.1)
        plt.axhspan(max(0.000001,avg-(1*std)), avg+(1*std), facecolor='y', alpha=0.2)

        # Setup X-Axis
        # p1.set_xlabel("Time [s]")
        p1.set_ylabel('[s]')
        p1.set_ylim(ymin=0.000001, ymax=1)
        p1.set_yscale('log')

        # Setup Graph title
        p1.set_title('Migrations Inter-Arrival Time (' + cpu +')')
        p1.grid(True)

        # Add legend
        p1.legend([l1], ['Interval'], prop={'size':fsize})

        ################################################################################
        # Plot Migration Departing and Arriving CPU
        ################################################################################
        p2 = fig.add_subplot(grids[plot_id+1])

        l1, = p2.plot(mTime(cpu), mData(cpu, 'Src'), 'r+ ')
        l2, = p2.plot(mTime(cpu), mData(cpu, 'Dst'), 'g+ ')

        # Setup X-Axis
        # p1.set_xlabel("Time [s]")
        p2.set_ylabel('[CPU]')
        p2.set_ylim(ymin=0, ymax=16)

        # Setup Graph title
        p2.set_title('Departing Arriving CPUs')
        p2.grid(True)

        # Add legend
        p2.legend([l1, l2], ['Dep', 'Arr'], prop={'size':fsize})

        plot_id += 2

        for item in (
            [p1.title, p1.xaxis.label, p1.yaxis.label]  +
            [p2.title, p2.xaxis.label, p2.yaxis.label]  +
            p1.get_xticklabels() + p1.get_yticklabels() +
            p2.get_xticklabels() + p2.get_yticklabels()):
            item.set_fontsize(fsize)

    # Plot the graph...
    if show_plot:
        plt.show()
    else:
        migrations_figure = string.replace(migrations_data, ".dat", ".pdf")
        # print "Plotting [", migrations_figure, "]..."
        plt.savefig(
                migrations_figure,
                orientation = 'portrait',
                format = 'pdf',
                )

# Reset plot data DB
data = {}
delta_stats = {}
for migrations_data in glob.glob('*_table_*_migrations.dat'):
    print "Parsing migrations [", migrations_data, "]..."
    parse_migrations(migrations_data)

#print "Columns: ", mColumns
#print "CPUs: ", len(data.keys())

match = migcpu_regex.search(migrations_data)
cpu_id = 'C' + match.group('cpu_id')
migrations_data = string.replace(migrations_data, cpu_id, "Call")
print "Plotting migrations [", migrations_data, "]..."
plot_migrations()
