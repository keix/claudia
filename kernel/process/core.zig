// Process management public API for Claudia kernel
// Re-exports key functionality from modularized components

const scheduler = @import("scheduler.zig");
pub const syscalls = @import("syscalls.zig");
const types = @import("types.zig");
const context = @import("context.zig");

// Re-export types
pub const Process = types.Process;
pub const ProcessState = types.ProcessState;
pub const PID = types.PID;
pub const WaitQ = types.WaitQ;
pub const Context = types.Context;
pub const isTerminated = types.isTerminated;

// Re-export scheduler functions
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

    // System calls
    pub const fork = syscalls.fork;
    pub const exec = syscalls.exec;
};

// Re-export current process getter
pub fn getCurrentProcess() ?*Process {
    return scheduler.current_process;
}
