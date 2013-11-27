#!/usr/bin/python

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gs
import matplotlib as mpl
import sys

################################################################################
#  Configuration
################################################################################

# 1: show the plots, 0: plot on PDF
show_plot = 0

# Plots font size
fsize = 10

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

# Loading data from file
data = np.loadtxt("cbs_rounds.dat", usecols=sorted(mColumns))
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

l1, = p1.plot(mTime, mData("Sp_next"), 'r-')
l2, = p1.plot(mTime, mData("Rt_prev"), 'b-')

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

l1, = p2.plot(mTime, mData("Re_prev"), 'b-')

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

l1, = p3.plot(mTime, mData("Co_next"), 'b-')

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
    print "Plotting [cbs_rounds.pdf]..."
    plt.savefig(
            "cbs_rounds.pdf",
            papertype = 'a3',
            format = 'pdf',
            )

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
 'Tb':        [ 'Burst measured',       '',                          11,      6],
 'Tb_start':  [ 'Burst time start',     '',                          12,      7],
 'Tb_stop':   [ 'Burst time (exp) end', '',                          13,      8],
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

# Data Loading loop
time_start = 0;
data = {}
infile = open('cbs_bursts.dat', 'r')
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
    
    l1, = p1.plot(mTime(task), mData(task, 'Tb_sp'), 'r-')
    l2, = p1.plot(mTime(task), mData(task, 'Tb'),    'b-')
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
    
    l1, = p2.plot(mTime(task), mData(task, 'Tb_error'), 'r-')
    l2, = p2.plot(mTime(task), mData(task, 'Tb_next'),  'g-')
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
    print "Plotting [cbs_bursts.pdf]..."
    plt.savefig(
            "cbs_bursts.pdf",
            orientation = 'portrait',
            format = 'pdf',
            )

