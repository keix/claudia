// Process management for Claudia kernel
// RISC-V specific process structures and scheduling

const std = @import("std");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const trap = @import("../trap/core.zig");
const user = @import("../user/core.zig");
const defs = @import("abi");

// Process ID type
pub const PID = u32;

// External assembly function for context switching
extern fn context_switch(old_context: *Context, new_context: *Context) void;

// Return point for scheduler when no previous context exists
fn schedulerReturn() noreturn {
    // This should never be called - it's just a dummy return address
    @panic("schedulerReturn called - this should never happen");
}

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
    satp: u64, // Supervisor Address Translation and Protection register

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
            .next = null,
        };

        // Copy name (max 15 chars + null terminator)
        const copy_len = @min(name.len, 15);
        @memcpy(proc.name[0..copy_len], name[0..copy_len]);
        proc.name[copy_len] = 0;

        // Process name copied

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

// Debug counters for infinite loop detection
var idle_count: u32 = 0;
var loop_count: u32 = 0;

// Global state for cooperative scheduling
var in_idle_mode: bool = false;

// Debug: exec sequence counter for tracking double exec calls
var exec_sequence: u32 = 0;

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

                // Re-initialize context with correct process pointer
                initProcessContext(proc);

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

        // Critical section - protect ready queue manipulation
        csr.disableInterrupts();
        defer csr.enableInterrupts();

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
        // Critical section - protect ready queue manipulation
        csr.disableInterrupts();
        defer csr.enableInterrupts();

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
            // No runnable process - need to go to scheduler idle
            // Clear current process
            current_process = null;

            // Save context and jump to scheduler idle
            // This is tricky - we need to save context then jump to idle loop
            // For now, panic to see if we reach here
            @panic("No runnable process in sched()");
        }
    }

    pub fn schedule() ?*Process {
        // If we have a current, try to rotate it out and switch from it
        if (current_process) |proc| {
            // Only make runnable if still RUNNING (not SLEEPING or ZOMBIE)
            if (proc.state == .RUNNING) {
                // DEBUG: Current process is still running
                uart.puts("[SCHED] Current still RUNNING, pid=");
                uart.putHex(proc.pid);
                uart.puts("\n");
                makeRunnable(proc);
            } else if (proc.state == .SLEEPING) {
                uart.puts("[SCHED] Current SLEEPING, pid=");
                uart.putHex(proc.pid);
                uart.puts("\n");
            }

            // Find next runnable process
            if (dequeueRunnable()) |next| {
                next.state = .RUNNING;
                current_process = next;

                // Switch from the previous kernel context to the next one
                uart.puts("[SCHED] Context switching from pid=");
                uart.putHex(proc.pid);
                uart.puts(" to pid=");
                uart.putHex(next.pid);
                uart.puts("\n");

                // Debug: Check page table before context switch
                if (next.context.satp != 0) {
                    const ppn = next.context.satp & 0xFFFFFFFFFFF;
                    if (ppn == 0x802bf) {
                        const root_addr = ppn << 12;
                        const root_table = @as([*]const u64, @ptrFromInt(root_addr));
                        const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                        const l2_pte = root_table[vpn2];

                        uart.puts("[SCHED] L2 PTE before context switch: 0x");
                        uart.putHex(l2_pte);
                        if (l2_pte == 0) {
                            uart.puts(" - ALREADY CORRUPTED BEFORE SWITCH!\n");
                        } else {
                            uart.puts(" - OK\n");
                        }
                    }
                }

                context_switch(&proc.context, &next.context);

                // Debug: Check page table after context switch (when we return)
                const current_satp = csr.readSatp();
                const current_ppn = current_satp & 0xFFFFFFFFFFF;
                if (current_ppn == 0x802bf) {
                    const root_addr = current_ppn << 12;
                    const root_table = @as([*]const u64, @ptrFromInt(root_addr));
                    const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                    const l2_pte = root_table[vpn2];

                    uart.puts("[SCHED] L2 PTE after context switch return: 0x");
                    uart.putHex(l2_pte);
                    if (l2_pte == 0) {
                        uart.puts(" - CORRUPTED AFTER SWITCH!\n");
                    } else {
                        uart.puts(" - still OK\n");
                    }
                }

                return next;
            }

            // No runnable process found
            // If current is sleeping, keep it as current for interrupt context
            if (proc.state == .SLEEPING) {
                // Don't clear current_process - we need it for interrupt handling
                uart.puts("[SCHED] No runnable found for sleeping process, pid=");
                uart.putHex(proc.pid);
                uart.puts("\n");
            }

            return null;
        }

        // No current: shouldn't happen in normal operation
        // This would only happen if schedule() is called without a current process
        return null;
    }

    // Exit current process
    pub fn exit(exit_code: i32) void {
        if (current_process) |proc| {
            proc.state = .ZOMBIE;
            proc.exit_code = exit_code;
            current_process = null;
            _ = schedule(); // Find next process to run
            unreachable; // Normally never returns here
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

        // DEBUG: Check page table before schedule
        if (proc.context.satp != 0) {
            const ppn = proc.context.satp & 0xFFFFFFFFFFF;
            if (ppn == 0x802cf) {
                const root_addr = ppn << 12;
                const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
                const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                const l2_pte = root_table[vpn2];
                uart.puts("[SLEEP] Before schedule: L2 PTE = 0x");
                uart.putHex(l2_pte);
                uart.puts("\n");
            }
        }

        // Switch to another process
        if (schedule()) |_| {
            // We switched to another process and came back
            // This means we were woken up and rescheduled

            // DEBUG: Check page table after schedule
            if (proc.context.satp != 0) {
                const ppn = proc.context.satp & 0xFFFFFFFFFFF;
                if (ppn == 0x802cf) {
                    const root_addr = ppn << 12;
                    const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
                    const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                    const l2_pte = root_table[vpn2];
                    uart.puts("[SLEEP] After schedule return: L2 PTE = 0x");
                    uart.putHex(l2_pte);
                    if (l2_pte == 0) {
                        uart.puts(" CORRUPTED!\n");
                    } else {
                        uart.puts("\n");
                    }
                }
            }

            return;
        }

        // If schedule returns null, there's no other runnable process
        // We need to idle until this process is woken up
        uart.puts("[SLEEP] No other processes, idling until woken\n");
        uart.puts("  proc pointer: 0x");
        uart.putHex(@intFromPtr(proc));
        uart.puts("\n");

        // The process structure is in kernel memory, but we should verify
        // Check if proc pointer is in kernel range
        const proc_addr = @intFromPtr(proc);
        if (proc_addr < 0x80000000 or proc_addr >= 0x90000000) {
            uart.puts("[SLEEP] ERROR: Process pointer not in kernel range!\n");
            // This should not happen - process table is in kernel BSS
            @panic("Process pointer outside kernel range");
        }

        // For now, just wait with interrupts enabled
        // Don't switch page tables - stay with current process's page table
        var check_count: u32 = 0;
        while (proc.state == .SLEEPING) {
            // Periodic check for page table corruption
            check_count += 1;
            if (check_count % 100 == 0 and proc.context.satp != 0) {
                const ppn = proc.context.satp & 0xFFFFFFFFFFF;
                if (ppn == 0x802cf) {
                    const root_addr = ppn << 12;
                    const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
                    const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                    const l2_pte = root_table[vpn2];
                    if (l2_pte == 0) {
                        uart.puts("[SLEEP] CORRUPTION DETECTED in idle loop!\n");
                        uart.puts("  L2 PTE became 0 at check ");
                        uart.putHex(check_count);
                        uart.puts("\n");
                        // Halt to debug
                        while (true) {
                            csr.wfi();
                        }
                    }
                }
            }

            // Enable interrupts
            csr.enableInterrupts();

            // Wait for interrupt
            csr.wfi();
        }

        uart.puts("[SLEEP] Process woken up\n");
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
            uart.puts("[WAKE] Waking process pid=");
            uart.putHex(proc.pid);
            uart.puts(", state=");
            uart.putHex(@intFromEnum(proc.state));
            uart.puts("\n");

            // CRITICAL DEBUG: Check if user page table is still valid
            if (proc.context.satp != 0) {
                const ppn = proc.context.satp & 0xFFFFFFFFFFF;
                if (ppn == 0x802bf) {
                    const root_addr = ppn << 12;
                    const root_table = @as([*]const u64, @ptrFromInt(root_addr));
                    const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                    const l2_pte = root_table[vpn2];

                    uart.puts("[WAKE] Checking L2 PTE before makeRunnable: 0x");
                    uart.putHex(l2_pte);
                    if (l2_pte == 0) {
                        uart.puts(" - ALREADY CORRUPTED!\n");
                    } else {
                        uart.puts(" - still valid\n");
                    }
                }
            }

            makeRunnable(proc);

            // Check again after makeRunnable
            if (proc.context.satp != 0) {
                const ppn = proc.context.satp & 0xFFFFFFFFFFF;
                if (ppn == 0x802bf) {
                    const root_addr = ppn << 12;
                    const root_table = @as([*]const u64, @ptrFromInt(root_addr));
                    const vpn2 = (0x8021b000 >> 30) & 0x1FF;
                    const l2_pte = root_table[vpn2];

                    if (l2_pte == 0) {
                        uart.puts("[WAKE] L2 PTE corrupted AFTER makeRunnable!\n");
                    }
                }
            }
        }

        if (count > 0) {
            uart.puts("[WAKE] Woke ");
            uart.putHex(count);
            uart.puts(" processes\n");
        }

        csr.enableInterrupts();
    }

    // Main scheduler loop - handles all scheduling and idle
    pub fn run() noreturn {
        uart.puts("[SCHED] Scheduler started\n");

        // Find and run the first process
        if (dequeueRunnable()) |proc| {
            proc.state = .RUNNING;
            current_process = proc;

            uart.puts("[SCHED] Running first process, pid=");
            uart.putHex(proc.pid);
            uart.puts("\n");
            uart.puts("  Process context SATP: 0x");
            uart.putHex(proc.context.satp);
            uart.puts("\n");
            uart.puts("  Current SATP: 0x");
            uart.putHex(csr.readSatp());
            uart.puts("\n");

            // Jump to the process entry point
            processEntryPointWithProc(proc);
        }

        // No processes to run - just idle
        uart.puts("[SCHED] No processes to run, entering idle loop\n");
        while (true) {
            csr.enableInterrupts();
            csr.wfi();
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

    // Allocate a process slot from the process table
    fn allocateProcess() ?*Process {
        for (&process_table) |*proc| {
            if (proc.state == .UNUSED) {
                return proc;
            }
        }
        return null;
    }

    // Create a kernel-only process (no user mappings)
    pub fn createKernelProcess() ?*Process {
        const proc = allocateProcess() orelse return null;

        // Set up as kernel process
        proc.pid = next_pid;
        next_pid += 1;
        proc.state = .EMBRYO;
        proc.is_kernel = true;

        // Initialize context for kernel thread
        // Get current SATP (kernel page table)
        const kernel_satp = csr.csrr(csr.CSR.satp);

        proc.context = Context{
            .ra = 0, // Will be set by caller
            .sp = 0, // No stack needed initially
            .s0 = 0,
            .s1 = 0,
            .s2 = 0,
            .s3 = 0,
            .s4 = 0,
            .s5 = 0,
            .s6 = 0,
            .s7 = 0,
            .s8 = 0,
            .s9 = 0,
            .s10 = 0,
            .s11 = 0,
            .satp = kernel_satp, // Use kernel page table
        };

        return proc;
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
        uart.puts("[FORK] WARNING: Child sharing parent's page table\n");
        uart.puts("  Child must call exec() to get proper page table\n");

        // Copy user mode trap frame if it exists
        if (parent.user_frame) |parent_frame| {
            // Allocate independent trap frame for child
            const child_frame = allocateChildTrapFrame() orelse return -1;
            child_frame.* = parent_frame.*;
            child_frame.a0 = 0; // Child returns 0 from fork
            child.user_frame = child_frame;

            // Set up child context - fix critical s0/sp for child
            child.context = parent.context; // Base copy is OK
            child.context.ra = @intFromPtr(&forkedChildReturn);
            child.context.s0 = @intFromPtr(child); // ★ Child's Process*
            child.context.sp = @intFromPtr(child.stack.ptr) + child.stack.len - 16; // ★ Child's kernel stack

            // DEBUG: Log inherited SATP
            uart.puts("[FORK] Child pid=");
            uart.putHex(child.pid);
            uart.puts(" inheriting SATP 0x");
            uart.putHex(child.context.satp);
            uart.puts(" from parent pid=");
            uart.putHex(parent.pid);
            uart.puts("\n");
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
    uart.puts("[PROC] processEntryPointWithProc called for pid=");
    uart.putHex(proc.pid);
    uart.puts(", name='");
    uart.puts(proc.getName());
    uart.puts("'\n");

    // Run process-specific code based on process name
    const name = proc.getName();
    if (std.mem.eql(u8, name, "init")) {
        uart.puts("[PROC] Calling user.initActualUserMode()\n");
        user.initActualUserMode();
        unreachable; // Should not return
    } else if (std.mem.eql(u8, name, "child")) {
        // Child process - return to user mode with saved trap frame
        // This should never actually execute because fork returns directly to syscall handler

        // If we somehow get here, just continue execution in user mode
        // The trap frame should already be set up to return to the correct location
        if (proc.user_frame) |frame| {
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
        // Idle process - jump to idle loop
        uart.puts("[PROC] Starting idle process\n");
        const idleLoop = @import("../core.zig").idleLoop;
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

    uart.puts("[PROC] initProcessContext: Setting SATP to 0x");
    uart.putHex(proc.context.satp);
    uart.puts(" (root_ppn=0x");
    uart.putHex(memory.kernel_page_table.root_ppn);
    uart.puts(")\n");
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
        while (true) {
            csr.wfi();
        }
    };

    // Get the child's trap frame and return to user mode
    const frame = child_proc.user_frame orelse {
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
    // Debug: Check page table before returning to user mode
    const satp_before = csr.readSatp();
    const ppn_before = satp_before & 0xFFFFFFFFFFF;
    uart.puts("[returnToUserMode] SATP before sret: 0x");
    uart.putHex(satp_before);
    uart.puts(" (ppn=0x");
    uart.putHex(ppn_before);
    uart.puts(")\n");

    if (ppn_before == 0x802bf) {
        const root_addr = ppn_before << 12;
        const root_table = @as([*]const u64, @ptrFromInt(root_addr));
        const vpn2 = (0x8021b000 >> 30) & 0x1FF;
        const l2_pte = root_table[vpn2];

        uart.puts("[returnToUserMode] L2 PTE before sret: 0x");
        uart.putHex(l2_pte);
        if (l2_pte == 0) {
            uart.puts(" - ALREADY CORRUPTED!\n");
        } else {
            uart.puts(" - OK\n");
        }
    }

    // Set up RISC-V CSRs for return to user mode
    // SSTATUS: Use RMW to only modify SPP=0, SPIE=1, preserve other flags
    const cur_sstatus = csr.readSstatus();
    const cleared_spp = cur_sstatus & ~(@as(u64, 1) << 8); // SPP=0
    const sstatus_val = cleared_spp | (@as(u64, 1) << 5); // SPIE=1

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

// Execute shell program (replace process image with shell) - noreturn on success
fn execShell(_: *Process) noreturn {
    exec_sequence += 1;

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
