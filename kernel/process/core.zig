// Process management for Claudia kernel
// RISC-V specific process structures and scheduling

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");
const defs = @import("abi");
const timer = @import("../time/timer.zig");

// Debug flag for process scheduling
const DEBUG_SCHEDULER = false;

// Process ID type
pub const PID = u32;

// Debug print helper
fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    _ = fmt;
    _ = args;
    if (DEBUG_SCHEDULER) {
        // Simple debug output without printf for now
        uart.puts("[SCHED] ");
        // TODO: Add proper formatting when needed
    }
}

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

// RISC-V CPU context for process switching (all general purpose registers)
// Matches the layout expected by context.S
pub const Context = struct {
    ra: u64, // x1 - return address
    sp: u64, // x2 - stack pointer
    gp: u64, // x3 - global pointer
    tp: u64, // x4 - thread pointer
    t0: u64, // x5 - temporary
    t1: u64, // x6 - temporary
    t2: u64, // x7 - temporary
    s0: u64, // x8 - saved register / frame pointer
    s1: u64, // x9 - saved register
    a0: u64, // x10 - function argument/return value
    a1: u64, // x11 - function argument
    a2: u64, // x12 - function argument
    a3: u64, // x13 - function argument
    a4: u64, // x14 - function argument
    a5: u64, // x15 - function argument
    a6: u64, // x16 - function argument
    a7: u64, // x17 - function argument
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
    t3: u64, // x28 - temporary
    t4: u64, // x29 - temporary
    t5: u64, // x30 - temporary
    t6: u64, // x31 - temporary
    satp: u64, // Supervisor Address Translation and Protection register
    sepc: u64, // Supervisor Exception Program Counter
    sstatus: u64, // Supervisor Status register

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
    is_kernel: bool, // Kernel-only process flag
    cwd: [256]u8, // Current working directory
    cwd_len: usize, // Length of current working directory
    page_table_ppn: u64, // Physical page number of page table root (0 = kernel PT)

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
            .is_kernel = false,
            .cwd = std.mem.zeroes([256]u8),
            .cwd_len = 1,
            .page_table_ppn = 0, // Default to kernel page table
            .next = null,
        };

        // Initialize with root directory
        proc.cwd[0] = '/';
        proc.cwd[1] = 0;

        // Copy name (max 15 chars + null terminator)
        const copy_len = @min(name.len, 15);
        @memcpy(proc.name[0..copy_len], name[0..copy_len]);
        proc.name[copy_len] = 0;

        // Don't initialize context here - it will be done after assignment to table

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

// Simple stack allocator for child processes
var child_stack_pool: [8][4096]u8 = undefined;
var child_stack_used: [8]bool = [_]bool{false} ** 8;

// Trap frame pool for child processes
var child_frame_pool: [8]trap.TrapFrame = undefined;
var child_frame_used: [8]bool = [_]bool{false} ** 8;

// Idle process resources
var idle_process: Process = undefined;
var idle_stack: [4096]u8 align(16) = undefined;

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
        
        // Initialize idle process
        idle_process = Process.init(0, "idle", &idle_stack);
        idle_process.state = .EMBRYO;
        idle_process.is_kernel = true;
        initIdleContext(&idle_process);
    }

    // Allocate a new process
    pub fn allocProcess(name: []const u8, stack: []u8) ?*Process {
        // Find unused slot
        for (&process_table) |*proc| {
            if (proc.state == .UNUSED) {
                proc.* = Process.init(next_pid, name, stack);
                next_pid += 1;

                // Re-initialize context with correct process pointer
                initProcessContext(proc);

                // Process is now ready to be made runnable
                proc.state = .EMBRYO;

                return proc;
            }
        }
        return null; // No free slots
    }

    pub fn makeRunnable(proc: *Process) void {
        // Already runnable, avoid duplicate queue entry
        if (proc.state == .RUNNABLE) {
            debugPrint("makeRunnable: PID {} already RUNNABLE\n", .{proc.pid});
            return;
        }

        // Not eligible for scheduling (terminated or unused)
        if (proc.state == .ZOMBIE or proc.state == .UNUSED) {
            debugPrint("makeRunnable: PID {} not eligible ({})\n", .{proc.pid, @tagName(proc.state)});
            return;
        }

        // Critical section - protect ready queue manipulation
        csr.disableInterrupts();
        defer csr.enableInterrupts();
        
        // Double-check not already in queue
        var p = ready_queue_head;
        while (p) |current| : (p = current.next) {
            if (current == proc) {
                debugPrint("makeRunnable: PID {} already in queue!\n", .{proc.pid});
                return;
            }
        }

        proc.state = .RUNNABLE;
        proc.next = null;
        
        debugPrint("makeRunnable: adding PID {} to queue\n", .{proc.pid});
        
        // DEBUG: Print when adding to queue
        uart.puts("[QUEUE] Adding PID ");
        uart.putDec(proc.pid);
        uart.puts(" to ready queue\n");
        
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
        // Critical section - protect ready queue manipulation
        csr.disableInterrupts();
        defer csr.enableInterrupts();

        if (ready_queue_head) |head| {
            debugPrint("dequeueRunnable: removing PID {} from queue\n", .{head.pid});
            ready_queue_head = head.next;
            if (ready_queue_head == null) {
                ready_queue_tail = null;
            }
            head.next = null;
            return head;
        }
        
        debugPrint("dequeueRunnable: queue empty\n", .{});
        return null;
    }

    // Internal scheduler function - must be called with current process set
    // This will context switch and not return until the current process runs again
    fn sched() void {
        const proc = current_process orelse unreachable;

        // Find next runnable process
        if (dequeueRunnable()) |next| {
            next.state = .RUNNING;
            current_process = next;

            // Context switch to next process
            context_switch(&proc.context, &next.context);
            // When we return here, this process has been rescheduled
        } else {
            // No runnable process - switch to idle process
            debugPrint("sched: no runnable process, switching to idle\n", .{});
            
            // DEBUG: Check idle process setup
            uart.puts("[SCHED] Switching to idle, context.ra=0x");
            uart.putHex(idle_process.context.ra);
            uart.puts(" context.sstatus=0x");
            uart.putHex(idle_process.context.sstatus);
            uart.puts("\n");
            
            idle_process.state = .RUNNING;
            current_process = &idle_process;
            
            // Context switch to idle process
            context_switch(&proc.context, &idle_process.context);
            // When we return here, this process has been rescheduled
        }
    }

    pub fn schedule() ?*Process {
        // Save current process state before switching
        if (current_process) |proc| {
            // Don't reschedule idle process unless something is runnable
            if (proc == &idle_process and ready_queue_head == null) {
                return proc;
            }
            
            // Only make runnable if still RUNNING (not SLEEPING or ZOMBIE) and not idle
            if (proc.state == .RUNNING and proc != &idle_process) {
                makeRunnable(proc);
            }

            // Find next runnable process
            if (dequeueRunnable()) |next| {
                next.state = .RUNNING;
                current_process = next;

                context_switch(&proc.context, &next.context);

                return next;
            } else {
                // No other runnable process - switch to idle
                debugPrint("schedule: no runnable process, switching to idle\n", .{});
                idle_process.state = .RUNNING;
                current_process = &idle_process;
                
                context_switch(&proc.context, &idle_process.context);
                return &idle_process;
            }
        }

        // No current process - try to find one to run
        if (dequeueRunnable()) |next| {
            next.state = .RUNNING;
            current_process = next;
            return next;
        }
        
        // Nothing runnable - use idle process
        idle_process.state = .RUNNING;
        current_process = &idle_process;
        return &idle_process;
    }

    // Schedule next process without making current runnable (for sleeping)
    pub fn scheduleNext() void {
        const proc = current_process orelse return;

        // Find next runnable process
        if (dequeueRunnable()) |next| {
            next.state = .RUNNING;
            current_process = next;

            // Context switch to next process
            context_switch(&proc.context, &next.context);
            // When we return here, this process has been rescheduled
        } else {
            // No runnable process - wait in a loop checking timers
            // Keep checking until this process or another becomes runnable
            while (proc.state == .SLEEPING and ready_queue_head == null) {
                csr.enableInterrupts();

                // Check timer periodically
                timer.tick();

                // Brief wait
                csr.wfi();
            }

            // Either this process was woken or another became runnable
            if (proc.state != .SLEEPING) {
                // This process was woken up, return to it
                return;
            }

            // Another process became runnable, schedule it
            if (ready_queue_head != null) {
                _ = schedule();
            }
        }
    }

    // Exit current process
    pub fn exit(exit_code: i32) void {
        if (current_process) |proc| {
            uart.puts("[EXIT] PID ");
            uart.putDec(proc.pid);
            uart.puts(" exiting with code ");
            uart.putDec(@as(u64, @intCast(exit_code)));
            uart.puts("\n");
            
            proc.state = .ZOMBIE;
            proc.exit_code = exit_code;

            // Free resources if this is a forked child
            if (proc.parent != null) {
                // Free child's stack
                freeChildStack(proc.stack);

                // Free child's trap frame
                if (proc.user_frame) |frame| {
                    freeChildTrapFrame(frame);
                }
            }

            // Free page table if process has its own (not kernel PT)
            if (proc.page_table_ppn != 0) {
                const virtual = @import("../memory/virtual.zig");
                var page_table = virtual.PageTable{
                    .root_ppn = proc.page_table_ppn,
                    .debug_watchdog_active = false,
                };
                page_table.deinit();
                proc.page_table_ppn = 0;
            }

            uart.puts("[EXIT] Scheduling next process\n");
            
            // Don't set current_process to null before calling sched()
            // sched() needs it for context switching
            sched(); // This will switch to another process and never return
            
            // This should never be reached
            uart.puts("[EXIT] ERROR: sched() returned!\n");
            unreachable;
        }
    }

    // Sleep current process on wait queue
    pub fn sleepOn(wq: *WaitQ, proc: *Process) void {
        // Assert that we're sleeping the current process
        if (current_process != proc) {
            // This should not happen - only current process can sleep itself
            return;
        }

        // Critical section to prevent lost wakeups
        csr.disableInterrupts();

        proc.state = .SLEEPING;

        // Add to wait queue
        proc.next = wq.head;
        wq.head = proc;

        // Re-enable interrupts before scheduling
        // This ensures interrupts can wake us up
        csr.enableInterrupts();

        // Switch to another process
        if (schedule()) |_| {
            // We switched to another process and came back
            // This means we were woken up and rescheduled

            return;
        }

        // Check if proc pointer is in kernel range
        const proc_addr = @intFromPtr(proc);
        if (proc_addr < 0x80000000 or proc_addr >= 0x90000000) {
            // This should not happen - process table is in kernel BSS
            @panic("Process pointer outside kernel range");
        }

        // For now, just wait with interrupts enabled
        // Don't switch page tables - stay with current process's page table
        while (proc.state == .SLEEPING) {
            // Enable interrupts
            csr.enableInterrupts();

            // Check timers periodically
            timer.tick();

            // Check if any process became runnable
            if (ready_queue_head != null) {
                // Resume normal scheduling
                _ = schedule();
                return;
            }

            // Wait for interrupt
            csr.wfi();
        }
    }

    // Wake all processes on wait queue
    pub fn wakeAll(wq: *WaitQ) void {
        csr.disableInterrupts();

        var count: u32 = 0;
        while (wq.head) |proc| {
            count += 1;
            wq.head = proc.next;
            proc.next = null;
            // makeRunnable will set state to RUNNABLE
            makeRunnable(proc);
        }

        csr.enableInterrupts();
    }

    // Main scheduler loop - handles all scheduling and idle
    pub fn run() noreturn {
        // Find and run the first process
        if (dequeueRunnable()) |proc| {
            proc.state = .RUNNING;
            current_process = proc;

            // Jump to the process entry point
            processEntryPointWithProc(proc);
        }

        // No processes to run - just idle
        while (true) {
            csr.enableInterrupts();

            // Check timer periodically
            timer.tick();

            // Check if any process became runnable
            if (ready_queue_head != null) {
                if (dequeueRunnable()) |proc| {
                    proc.state = .RUNNING;
                    current_process = proc;
                    processEntryPointWithProc(proc);
                }
            }

            csr.wfi();
        }
    }

    // Get current running process
    pub fn getCurrentProcess() ?*Process {
        return current_process;
    }

    // Request scheduler to run (e.g., from timer interrupt)
    pub fn yield() void {
        const proc = current_process orelse return;
        
        // DEBUG: Simple yield trace
        uart.puts("[YIELD] PID ");
        uart.putDec(proc.pid);
        uart.puts(" yielding\n");
        
        debugPrint("yield: PID {} ({})\n", .{ proc.pid, proc.getName() });
        
        // Only yield if currently running
        if (proc.state != .RUNNING) {
            debugPrint("yield: process not RUNNING, state={}\n", .{@tagName(proc.state)});
            return;
        }
        
        // Special handling for idle process
        if (proc == &idle_process) {
            // Idle process only yields if there's something to run
            if (ready_queue_head != null) {
                debugPrint("yield: idle process yielding to runnable process\n", .{});
                _ = schedule();
            }
            return;
        }
        
        // Mark as runnable and add to queue
        makeRunnable(proc);
        
        // Find next process to run
        if (dequeueRunnable()) |next| {
            // Check if we just dequeued ourselves (only process in system)
            if (next == proc) {
                debugPrint("yield: only process in system\n", .{});
                next.state = .RUNNING;
                current_process = next;
                return;
            }
            
            debugPrint("yield: switching {} -> {}\n", .{ proc.pid, next.pid });
            
            // DEBUG: Print context switch
            uart.puts("[SWITCH] ");
            uart.putDec(proc.pid);
            uart.puts(" -> ");
            uart.putDec(next.pid);
            uart.puts("\n");
            
            next.state = .RUNNING;
            current_process = next;
            
            // Perform context switch
            context_switch(&proc.context, &next.context);
            
            // We return here when this process runs again
            debugPrint("yield: resumed PID {}\n", .{proc.pid});
        } else {
            // No runnable process - switch to idle
            debugPrint("yield: no runnable process, switching to idle\n", .{});
            idle_process.state = .RUNNING;
            current_process = &idle_process;
            
            context_switch(&proc.context, &idle_process.context);
        }
    }

    // Clean up zombie processes (should be called periodically)
    pub fn reapZombies() void {
        for (&process_table) |*proc| {
            if (proc.state == .ZOMBIE) {
                // Mark as unused so it can be reused
                proc.state = .UNUSED;
                proc.pid = 0;
            }
        }
    }

    // Fork current process (simplified implementation)
    pub fn fork() isize {
        const parent = current_process orelse return defs.ESRCH;

        // Allocate static kernel stack for child (simple allocator)
        const child_stack = allocateChildStack() orelse return defs.ENOMEM;

        // Create child process
        const child = allocProcess("child", child_stack) orelse return defs.EAGAIN;

        // Copy parent process context - but child should not go to processEntryPoint
        // Instead, child should resume from the syscall return point
        child.parent = parent;

        // CRITICAL: For now, child shares parent's page table
        // This is a simplified fork - proper fork would copy the page table
        // The child MUST call exec() to get its own page table with kernel mappings
        
        // DEBUG: Print parent's SATP
        uart.puts("[FORK] Parent SATP=0x");
        uart.putHex(parent.context.satp);
        uart.puts("\n");

        // Copy user mode trap frame if it exists
        if (parent.user_frame) |parent_frame| {
            // Allocate independent trap frame for child
            const child_frame = allocateChildTrapFrame() orelse return -1;
            child_frame.* = parent_frame.*;
            child_frame.a0 = 0; // Child returns 0 from fork
            child_frame.gp = 0; // Ensure GP is 0 to prevent GP-relative addressing
            
            // CRITICAL: Adjust sepc to skip the ecall instruction
            // The parent's sepc will be incremented by the trap handler
            // but the child needs to return to the instruction after ecall
            child_frame.sepc = parent_frame.sepc + 4;
            
            child.user_frame = child_frame;
            
            // DEBUG: Print parent frame GP
            uart.puts("[FORK] Parent GP=0x");
            uart.putHex(parent_frame.gp);
            uart.puts("\n");

            // Set up child context - start fresh
            child.context = Context.zero();
            
            // Set up critical registers for child
            child.context.ra = @intFromPtr(&forkedChildReturn);
            child.context.sp = @intFromPtr(child.stack.ptr) + child.stack.len - 16;
            child.context.s0 = @intFromPtr(child); // Process pointer in s0
            child.context.a0 = 0; // Return value for fork (child returns 0)
            
            // CRITICAL: Set supervisor mode in context for proper return
            // SPP=1 (supervisor), SPIE=1 (interrupts enabled after sret)
            child.context.sstatus = (1 << 8) | (1 << 5); // SPP | SPIE
            
            // CRITICAL: Child must use parent's page table, not kernel's!
            // The parent is already running with a user page table that has
            // the user program mapped. The child needs the same mappings.
            child.context.satp = parent.context.satp;
            
            // Child inherits parent's user page table for later use
            child.page_table_ppn = parent.page_table_ppn;
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

    // Execute program (replace current process image) - noreturn on success
    pub fn exec(filename: []const u8, args: []const u8) isize {
        _ = args;
        const current = current_process orelse return -1;

        // For simplicity, only support "shell" for now
        if (std.mem.eql(u8, filename, "shell") or std.mem.eql(u8, filename, "/bin/shell")) {
            // Replace current process with shell - this does not return on success
            execShell(current);
            unreachable; // Should never reach here
        } else {
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
        unreachable; // Should not return
    } else if (std.mem.eql(u8, name, "child")) {
        // The trap frame should already be set up to return to the correct location
        if (proc.user_frame) |frame| {
            // DEBUG: Check frame pointer before using it
            uart.puts("[CHILD] Frame pointer: 0x");
            uart.putHex(@intFromPtr(frame));
            uart.puts(" SP in frame: 0x");
            uart.putHex(frame.sp);
            uart.puts("\n");
            
            // Verify frame is in kernel space
            if (@intFromPtr(frame) < 0x80000000) {
                uart.puts("[CHILD] ERROR: Frame pointer in user space!\n");
                while (true) {
                    csr.wfi();
                }
            }
            
            // Return to user mode by pretending we came from a trap
            // This is a bit of a hack, but it should work for basic fork
            returnToUserMode(frame);
            unreachable; // Should not return
        } else {
            // No trap frame - exit
            Scheduler.exit(-1);
            unreachable;
        }
    } else if (std.mem.eql(u8, name, "idle")) {
        // Idle process - jump to our own idle loop
        idleLoop();
    } else {
        // Generic process - just exit
        Scheduler.exit(0);
        unreachable;
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

    // Set SATP to kernel page table
    const memory = @import("../memory/core.zig");
    proc.context.satp = csr.SATP_SV39 | memory.kernel_page_table.root_ppn;
}

// Entry point for newly created processes (called via context switch)
fn processEntryPoint() noreturn {
    // Get process pointer from s0 register (passed from context init)
    const proc: *Process = asm volatile ("mv %[proc], s0"
        : [proc] "=r" (-> *Process),
    );

    // DEBUG: Verify process pointer
    uart.puts("[processEntryPoint] Process ptr: 0x");
    uart.putHex(@intFromPtr(proc));
    uart.puts(" PID: ");
    uart.putDec(proc.pid);
    uart.puts(" Name: ");
    uart.puts(proc.getName());
    uart.puts("\n");
    
    // Delegate to common entry point
    processEntryPointWithProc(proc);
}

// Entry point for forked child processes - return directly to user mode
fn forkedChildReturn() noreturn {
    const child_proc = current_process orelse {
        uart.puts("[forkedChildReturn] ERROR: No current process!\n");
        while (true) {
            csr.wfi();
        }
    };

    uart.puts("[forkedChildReturn] Child PID: ");
    uart.putDec(child_proc.pid);
    uart.puts(" Process ptr: 0x");
    uart.putHex(@intFromPtr(child_proc));
    if (child_proc.user_frame) |uf| {
        uart.puts(" user_frame ptr: 0x");
        uart.putHex(@intFromPtr(uf));
    } else {
        uart.puts(" user_frame: null");
    }
    uart.puts("\n");

    // Get the child's trap frame
    uart.puts("[forkedChildReturn] About to access user_frame field\n");
    const frame = child_proc.user_frame orelse {
        uart.puts("[forkedChildReturn] ERROR: No user frame!\n");
        while (true) {
            csr.wfi();
        }
    };
    
    uart.puts("[forkedChildReturn] Got frame, checking contents\n");
    
    // DEBUG: Print some key values from the frame
    uart.puts("[forkedChildReturn] frame.sepc=0x");
    uart.putHex(frame.sepc);
    uart.puts(" frame.sp=0x");
    uart.putHex(frame.sp);
    uart.puts(" frame.gp=0x");
    uart.putHex(frame.gp);
    uart.puts("\n");
    uart.puts("[forkedChildReturn] frame.s0=0x");
    uart.putHex(frame.s0);
    uart.puts(" frame.s1=0x");
    uart.putHex(frame.s1);
    uart.puts(" frame.tp=0x");
    uart.putHex(frame.tp);
    uart.puts("\n");
    
    // Check if any values look suspicious
    if (frame.gp != 0) {
        uart.puts("[WARNING] Child frame has non-zero GP!\n");
    }
    
    // DEBUG: Print exact register values before return
    uart.puts("[forkedChildReturn] Before return: a0=0x");
    uart.putHex(frame.a0);
    uart.puts(" a7=0x");
    uart.putHex(frame.a7);
    uart.puts("\n");
    
    // Use pure assembly implementation to avoid GP issues
    uart.puts("[forkedChildReturn] Calling assembly return function\n");
    
    // External assembly function
    const child_return_to_user = @extern(*const fn(*trap.TrapFrame) callconv(.C) noreturn, .{ .name = "child_return_to_user" });
    
    child_return_to_user(frame);
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

// Initialize idle process context
fn initIdleContext(proc: *Process) void {
    // Set up stack pointer to top of allocated stack (grows downward)
    proc.context.sp = @intFromPtr(proc.stack.ptr) + proc.stack.len - 16;
    
    // Set return address to idle loop
    proc.context.ra = @intFromPtr(&idleLoop);
    
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
    
    // Store process pointer in s0
    proc.context.s0 = @intFromPtr(proc);
    
    // Set SATP to kernel page table
    const memory = @import("../memory/core.zig");
    proc.context.satp = csr.SATP_SV39 | memory.kernel_page_table.root_ppn;
    
    // Set sstatus for supervisor mode (SPP=1)
    proc.context.sstatus = (1 << 8) | (1 << 5); // SPP | SPIE
}

// Idle loop - runs when no other process is runnable
fn idleLoop() noreturn {
    debugPrint("Entering idle loop\n", .{});
    
    // Ensure we're in supervisor mode
    const sstatus = csr.readSstatus();
    if ((sstatus & (1 << 8)) == 0) {
        uart.puts("[IDLE] ERROR: Not in supervisor mode!\n");
    }
    
    while (true) {
        // Enable interrupts to receive timer/device interrupts
        csr.enableInterrupts();
        
        // Check timers that might wake sleeping processes
        timer.tick();
        
        // Check if any process became runnable
        if (ready_queue_head != null) {
            debugPrint("Idle: found runnable process, yielding\n", .{});
            // Something is runnable, yield to scheduler
            Scheduler.yield();
        }
        
        // Wait for interrupt
        csr.wfi();
    }
}

// Return to user mode with given trap frame
noinline fn returnToUserMode(frame: *trap.TrapFrame) noreturn {
    // CRITICAL: Ensure GP is 0 before accessing anything
    asm volatile ("li gp, 0");
    
    // Double-check frame pointer is in kernel space
    if (@intFromPtr(frame) < 0x80000000) {
        uart.puts("[ERROR] Frame pointer in user space!\n");
        while (true) { csr.wfi(); }
    }
    
    uart.puts("[returnToUserMode] Starting CSR setup\n");
    
    // Set up RISC-V CSRs for return to user mode
    // SSTATUS: Use RMW to only modify SPP=0, SPIE=1, preserve other flags
    const cur_sstatus = csr.readSstatus();
    const cleared_spp = cur_sstatus & ~(@as(u64, 1) << 8); // SPP=0
    const sstatus_val = cleared_spp | (@as(u64, 1) << 5); // SPIE=1
    
    // Just use the simple assembly version
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
        \\fence.i
        \\sfence.vma zero, zero
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

// Execute shell program (replace process image with shell) - noreturn on success
fn execShell(_: *Process) noreturn {
    // Get the shell program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    if (code_size > 0 and code_size < 2097152) { // Allow up to 2MB for shell
        const code = @as([*]const u8, @ptrFromInt(start_addr))[0..code_size];

        // Execute the shell using the existing user program execution
        // This should never return on success
        user.executeUserProgram(code, "") catch {
            Scheduler.exit(-1);
            unreachable;
        };

        // If we somehow get here, the exec failed
        Scheduler.exit(-1);
        unreachable;
    } else {
        Scheduler.exit(-1);
        unreachable;
    }
}
