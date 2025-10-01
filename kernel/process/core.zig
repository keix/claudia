// Process management subsystem public interface
// This module re-exports key functionality from:
//   - scheduler: Process scheduling and context switching
//   - syscalls: System call implementations (fork, exec, wait)
//   - types: Core data structures (Process, Context, etc.)
//   - context: Context initialization and switching logic

const scheduler = @import("scheduler.zig");
pub const syscalls = @import("syscalls.zig");
const types = @import("types.zig");
const context = @import("context.zig");

pub const Process = types.Process;
pub const ProcessState = types.ProcessState;
pub const PID = types.PID;
pub const WaitQ = types.WaitQ;
pub const Context = types.Context;
pub const isTerminated = types.isTerminated;

// Scheduler namespace - groups all scheduling-related functions
pub const Scheduler = struct {
    pub const init = scheduler.init;
    pub const allocProcess = scheduler.allocProcess;
    pub const makeRunnable = scheduler.makeRunnable;
    pub const dequeueRunnable = scheduler.dequeueRunnable;
    pub const schedule = scheduler.schedule;
    pub const scheduleNext = scheduler.scheduleNext;
    pub const exit = scheduler.exit;
    pub const sleepOn = scheduler.sleepOn;
    pub const wakeAll = scheduler.wakeAll;
    pub const run = scheduler.run;
    pub const getCurrentProcess = scheduler.getCurrentProcess;
    pub const yield = scheduler.yield;
    pub const reapZombies = scheduler.reapZombies;

    pub const fork = syscalls.fork;
    pub const exec = syscalls.exec;
};

// Get currently executing process
// Note: This directly accesses scheduler's current_process variable
pub fn getCurrentProcess() ?*Process {
    return scheduler.current_process;
}
