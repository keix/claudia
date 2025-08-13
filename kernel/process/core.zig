// Process management for Claudia kernel
// RISC-V specific process structures and scheduling

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");

// Process ID type
pub const PID = u32;

// External assembly function for context switching
extern fn context_switch(old_context: *Context, new_context: *Context) void;

// Process states
pub const ProcessState = enum {
    UNUSED, // Slot not in use
    EMBRYO, // Being created
    SLEEPING, // Sleeping on a wait channel
    RUNNABLE, // Ready to run
    RUNNING, // Currently running
    ZOMBIE, // Terminated but not yet cleaned up
};

// Wait queue for blocking I/O
pub const WaitQ = struct {
    head: ?*Process = null,

    pub fn init() WaitQ {
        return WaitQ{ .head = null };
    }
};

// RISC-V CPU context for process switching (callee-saved registers only)
// Matches the layout expected by context.S
pub const Context = struct {
    ra: u64, // x1 - return address
    sp: u64, // x2 - stack pointer
    s0: u64, // x8 - saved register / frame pointer
    s1: u64, // x9 - saved register
    s2: u64, // x18 - saved register
    s3: u64, // x19 - saved register
    s4: u64, // x20 - saved register
    s5: u64, // x21 - saved register
    s6: u64, // x22 - saved register
    s7: u64, // x23 - saved register
    s8: u64, // x24 - saved register
    s9: u64, // x25 - saved register
    s10: u64, // x26 - saved register
    s11: u64, // x27 - saved register

    pub fn zero() Context {
        return std.mem.zeroes(Context);
    }
};

// Process control block
pub const Process = struct {
    pid: PID, // Process ID
    state: ProcessState, // Process state
    context: Context, // CPU context for kernel-level switching
    user_frame: ?*trap.TrapFrame, // User mode trap frame (null for kernel processes)
    stack: []u8, // Process stack
    name: [16]u8, // Process name (null-terminated)
    parent: ?*Process, // Parent process
    exit_code: i32, // Exit code when zombie

    // Simple linked list for process queue
    next: ?*Process,

    pub fn init(pid: PID, name: []const u8, stack: []u8) Process {
        var proc = Process{
            .pid = pid,
            .state = .EMBRYO,
            .context = Context.zero(),
            .user_frame = null,
            .stack = stack,
            .name = std.mem.zeroes([16]u8),
            .parent = null,
            .exit_code = 0,
            .next = null,
        };

        // Copy name (max 15 chars + null terminator)
        const copy_len = @min(name.len, 15);
        @memcpy(proc.name[0..copy_len], name[0..copy_len]);
        proc.name[copy_len] = 0;

        // Process name copied

        // Initialize context for new process
        initProcessContext(&proc);

        // Context initialized

        return proc;
    }

    pub fn getName(self: *const Process) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..len];
    }
};

// Simple process table
const MAX_PROCESSES = 64;
var process_table: [MAX_PROCESSES]Process = undefined;
var next_pid: PID = 1;

// Current running process
pub var current_process: ?*Process = null;

// Ready queue (simple linked list)
var ready_queue_head: ?*Process = null;
var ready_queue_tail: ?*Process = null;

// Debug counters for infinite loop detection
var idle_count: u32 = 0;
var loop_count: u32 = 0;

// Global state for cooperative scheduling
var in_idle_mode: bool = false;

// Simple stack allocator for child processes
var child_stack_pool: [8][4096]u8 = undefined;
var child_stack_used: [8]bool = [_]bool{false} ** 8;

// Trap frame pool for child processes
var child_frame_pool: [8]trap.TrapFrame = undefined;
var child_frame_used: [8]bool = [_]bool{false} ** 8;

// Process scheduler
pub const Scheduler = struct {
    // Initialize the process system
    pub fn init() void {
        // Initialize process table
        for (&process_table) |*proc| {
            proc.state = .UNUSED;
            proc.pid = 0;
            proc.next = null;
        }

        // Reset global state
        current_process = null;
        ready_queue_head = null;
        ready_queue_tail = null;
        next_pid = 1;
    }

    // Allocate a new process
    pub fn allocProcess(name: []const u8, stack: []u8) ?*Process {
        // Find unused slot
        for (&process_table) |*proc| {
            if (proc.state == .UNUSED) {
                proc.* = Process.init(next_pid, name, stack);
                next_pid += 1;

                return proc;
            }
        }
        return null; // No free slots
    }

    pub fn makeRunnable(proc: *Process) void {
        // Already runnable, avoid duplicate queue entry
        if (proc.state == .RUNNABLE) return;

        // Not eligible for scheduling (terminated or unused)
        if (proc.state == .ZOMBIE or proc.state == .UNUSED) return;

        proc.state = .RUNNABLE;
        proc.next = null;
        if (ready_queue_tail) |tail| {
            tail.next = proc;
            ready_queue_tail = proc;
        } else {
            ready_queue_head = proc;
            ready_queue_tail = proc;
        }
    }

    // Remove and return next runnable process
    pub fn dequeueRunnable() ?*Process {
        if (ready_queue_head) |head| {
            ready_queue_head = head.next;
            if (ready_queue_head == null) {
                ready_queue_tail = null;
            }
            head.next = null;
            return head;
        }
        return null;
    }

    pub fn schedule() ?*Process {
        // If we have a current, try to rotate it out and switch from it
        if (current_process) |proc| {
            // Only make runnable if still RUNNING (not SLEEPING or ZOMBIE)
            if (proc.state == .RUNNING) {
                makeRunnable(proc);
            }

            // Find next runnable process
            if (dequeueRunnable()) |next| {
                next.state = .RUNNING;
                current_process = next;

                // Switch from the previous kernel context to the next one
                context_switch(&proc.context, &next.context);
                return next;
            }

            return null;
        }

        // No current: first dispatch or resuming from idle
        if (dequeueRunnable()) |next| {
            next.state = .RUNNING;
            current_process = next;

            // First run → no previous context to switch from
            processEntryPointWithProc(next); // noreturn
        }

        return null;
    }

    // Exit current process
    pub fn exit(exit_code: i32) void {
        if (current_process) |proc| {
            proc.state = .ZOMBIE;
            proc.exit_code = exit_code;

            current_process = null;
            _ = schedule(); // Find next process to run
        }
    }

    // Sleep current process on wait queue
    pub fn sleepOn(wq: *WaitQ, proc: *Process) void {
        // Assert that we're sleeping the current process
        if (current_process != proc) {
            // This should not happen - only current process can sleep itself
            return;
        }

        proc.state = .SLEEPING;

        // Add to wait queue
        proc.next = wq.head;
        wq.head = proc;

        // Switch to another process - sleepOn() does not return until woken up
        _ = schedule();
        // When we reach here, this process has been woken up and is RUNNING again
        // The wakeAll() call will have made us RUNNABLE and scheduler picked us up
    }

    // Wake all processes on wait queue
    pub fn wakeAll(wq: *WaitQ) void {
        csr.disableInterrupts();

        while (wq.head) |proc| {
            wq.head = proc.next;
            proc.next = null;
            // makeRunnable will set state to RUNNABLE
            makeRunnable(proc);
        }

        csr.enableInterrupts();
    }

    // Main scheduler loop - handles all scheduling and idle
    pub fn run() noreturn {
        while (true) {
            // Try to schedule a process
            if (schedule()) |_| {
                // Process is now running, continue scheduling
            } else {
                // No runnable processes, wait for interrupt
                csr.enableInterrupts();
                csr.wfi();
            }
        }
    }

    // Get current running process
    pub fn getCurrentProcess() ?*Process {
        return current_process;
    }

    // Request scheduler to run (e.g., from timer interrupt)
    pub fn yield() void {
        if (current_process) |proc| {
            // makeRunnable will set state to RUNNABLE and add to queue
            makeRunnable(proc);

            // Schedule next process
            _ = schedule();
        }
    }

    // Fork current process (simplified implementation)
    pub fn fork() isize {
        const parent = current_process orelse return -1;

        // Allocate static kernel stack for child (simple allocator)
        const child_stack = allocateChildStack() orelse return -1;

        // Create child process
        const child = allocProcess("child", child_stack) orelse return -1;

        // Copy parent process context - but child should not go to processEntryPoint
        // Instead, child should resume from the syscall return point
        child.parent = parent;

        // Copy user mode trap frame if it exists
        if (parent.user_frame) |parent_frame| {
            // Allocate independent trap frame for child
            const child_frame = allocateChildTrapFrame() orelse return -1;
            child_frame.* = parent_frame.*;
            child_frame.a0 = 0; // Child returns 0 from fork
            child.user_frame = child_frame;

            // Set up child context to return directly to user mode
            // by bypassing the normal process entry point
            child.context = parent.context;
            child.context.ra = @intFromPtr(&forkedChildReturn);
        } else {
            // No user frame - this shouldn't happen for forked processes
            return -1;
        }

        // Make child runnable
        makeRunnable(child);

        // Parent returns child PID
        const child_pid = @as(isize, @intCast(child.pid));
        return child_pid;
    }

    // Execute program (replace current process image)
    pub fn exec(filename: []const u8, args: []const u8) isize {
        _ = args;
        const current = current_process orelse return -1;

        uart.puts("[proc] exec: ");
        uart.puts(filename);
        uart.puts("\n");

        // For simplicity, only support "shell" for now
        if (std.mem.eql(u8, filename, "shell") or std.mem.eql(u8, filename, "/bin/shell")) {
            // Replace current process with shell
            return execShell(current);
        } else {
            uart.puts("[proc] exec: Unsupported program: ");
            uart.puts(filename);
            uart.puts("\n");
            return -1;
        }
    }
};

// Entry point for process with direct pointer passing
fn processEntryPointWithProc(proc: *Process) noreturn {
    // Run process-specific code based on process name
    const name = proc.getName();
    if (std.mem.eql(u8, name, "init")) {
        user.initActualUserMode();
    } else if (std.mem.eql(u8, name, "child")) {
        // Child process - return to user mode with saved trap frame
        // This should never actually execute because fork returns directly to syscall handler
        uart.puts("[proc] Child process entry point reached\n");

        // If we somehow get here, just continue execution in user mode
        // The trap frame should already be set up to return to the correct location
        if (proc.user_frame) |_| {
            // Return to user mode by pretending we came from a trap
            // This is a bit of a hack, but it should work for basic fork
            uart.puts("[proc] Returning child to user mode\n");
        }
    } else {
        // Generic process - just exit
        uart.puts("[proc] Unknown process type: ");
        uart.puts(name);
        uart.puts("\n");
    }

    // Process finished - mark as zombie and yield
    proc.state = .ZOMBIE;
    proc.exit_code = 0;

    // Yield to scheduler
    Scheduler.yield();

    // Should never reach here
    while (true) {
        csr.wfi();
    }
}

// Initialize process context for context switching
fn initProcessContext(proc: *Process) void {
    // Set up stack pointer to top of allocated stack (grows downward)
    proc.context.sp = @intFromPtr(proc.stack.ptr) + proc.stack.len - 16;

    // Set return address to process entry point
    proc.context.ra = @intFromPtr(&processEntryPoint);

    // Initialize all callee-saved registers to zero
    proc.context.s0 = 0;
    proc.context.s1 = 0;
    proc.context.s2 = 0;
    proc.context.s3 = 0;
    proc.context.s4 = 0;
    proc.context.s5 = 0;
    proc.context.s6 = 0;
    proc.context.s7 = 0;
    proc.context.s8 = 0;
    proc.context.s9 = 0;
    proc.context.s10 = 0;
    proc.context.s11 = 0;

    // Store process pointer in s0 so entry point can access it
    proc.context.s0 = @intFromPtr(proc);
}

// Entry point for newly created processes (called via context switch)
fn processEntryPoint() noreturn {
    // Get process pointer from s0 register (passed from context init)
    const proc: *Process = asm volatile ("mv %[proc], s0"
        : [proc] "=r" (-> *Process),
    );

    // Delegate to common entry point
    processEntryPointWithProc(proc);
}

// Entry point for forked child processes - return directly to user mode
fn forkedChildReturn() noreturn {
    const child_proc = current_process orelse {
        uart.puts("[proc] ERROR: No current process in forked child return\n");
        while (true) {
            csr.wfi();
        }
    };

    uart.puts("[proc] Forked child returning to user mode: PID ");
    uart.putHex(child_proc.pid);
    uart.puts("\n");

    // Get the child's trap frame and return to user mode
    const frame = child_proc.user_frame orelse {
        uart.puts("[proc] ERROR: No trap frame in forked child\n");
        while (true) {
            csr.wfi();
        }
    };

    returnToUserMode(frame);
}

// Allocate stack for child process
fn allocateChildStack() ?[]u8 {
    for (&child_stack_used, 0..) |*used, i| {
        if (!used.*) {
            used.* = true;
            return child_stack_pool[i][0..];
        }
    }
    return null; // No free stacks
}

// Free child stack (called when process exits)
fn freeChildStack(stack: []u8) void {
    for (&child_stack_pool, &child_stack_used) |*pool_stack, *used| {
        if (stack.ptr == pool_stack.ptr) {
            used.* = false;
            break;
        }
    }
}

// Allocate trap frame for child process
fn allocateChildTrapFrame() ?*trap.TrapFrame {
    for (&child_frame_used, 0..) |*used, i| {
        if (!used.*) {
            used.* = true;
            return &child_frame_pool[i];
        }
    }
    return null; // No free frames
}

// Free child trap frame (called when process exits)
fn freeChildTrapFrame(frame: *trap.TrapFrame) void {
    for (&child_frame_pool, &child_frame_used) |*pool_frame, *used| {
        if (frame == pool_frame) {
            used.* = false;
            break;
        }
    }
}

// Return to user mode with given trap frame
fn returnToUserMode(frame: *trap.TrapFrame) noreturn {
    uart.puts("[proc] Returning to user mode at PC: ");
    uart.putHex(frame.sepc);
    uart.puts(" with return value: ");
    uart.putHex(frame.a0);
    uart.puts("\n");

    // Set up RISC-V CSRs for return to user mode
    // SSTATUS: SPP=0 (user mode), SPIE=1 (enable interrupts on return)
    const sstatus_val: u64 = (1 << 5); // SPIE = 1, SPP = 0

    asm volatile (
    // Set up CSRs
        \\csrw sepc, %[pc]
        \\csrw sscratch, %[user_sp]
        \\csrw sstatus, %[sstatus]

        // Restore user registers from trap frame
        \\ld ra, 8(%[frame])
        \\ld gp, 16(%[frame])
        \\ld tp, 24(%[frame])
        \\ld t0, 32(%[frame])
        \\ld t1, 40(%[frame])
        \\ld t2, 48(%[frame])
        \\ld s0, 56(%[frame])
        \\ld s1, 64(%[frame])
        \\ld a0, 72(%[frame])
        \\ld a1, 80(%[frame])
        \\ld a2, 88(%[frame])
        \\ld a3, 96(%[frame])
        \\ld a4, 104(%[frame])
        \\ld a5, 112(%[frame])
        \\ld a6, 120(%[frame])
        \\ld a7, 128(%[frame])
        \\ld s2, 136(%[frame])
        \\ld s3, 144(%[frame])
        \\ld s4, 152(%[frame])
        \\ld s5, 160(%[frame])
        \\ld s6, 168(%[frame])
        \\ld s7, 176(%[frame])
        \\ld s8, 184(%[frame])
        \\ld s9, 192(%[frame])
        \\ld s10, 200(%[frame])
        \\ld s11, 208(%[frame])
        \\ld t3, 216(%[frame])
        \\ld t4, 224(%[frame])
        \\ld t5, 232(%[frame])
        \\ld t6, 240(%[frame])

        // Switch to user stack and return
        \\csrrw sp, sscratch, sp
        \\sret
        :
        : [frame] "r" (frame),
          [pc] "r" (frame.sepc),
          [user_sp] "r" (frame.sp),
          [sstatus] "r" (sstatus_val),
        : "memory"
    );

    unreachable;
}

// Execute shell program (replace process image with shell)
fn execShell(proc: *Process) isize {
    uart.puts("[proc] execShell: Loading shell for PID ");
    uart.putHex(proc.pid);
    uart.puts("\n");

    // Get the shell program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    uart.puts("[proc] Shell binary size: ");
    uart.putHex(code_size);
    uart.puts("\n");

    if (code_size > 0 and code_size < 2097152) { // Allow up to 2MB for shell
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];

        // Execute the shell using the existing user program execution
        user.executeUserProgram(code, "") catch return -1;

        // Should not return - the process image has been replaced
        return 0;
    } else {
        uart.puts("[proc] Invalid shell program size\n");
        return -1;
    }
}
