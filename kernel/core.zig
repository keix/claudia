const std = @import("std");
const csr = @import("arch/riscv/csr.zig");
const uart = @import("driver/uart/core.zig");
const proc = @import("process/core.zig");
const file = @import("file/core.zig");
const memory = @import("memory/core.zig");
const trap = @import("trap/core.zig");
const user = @import("user/core.zig");

// Simple stack allocator for testing
var stack_memory: [4096 * 4]u8 = undefined;
var stack_offset: usize = 0;

fn allocStack(size: usize) []u8 {
    const aligned_size = (size + 7) & ~@as(usize, 7); // 8-byte align
    if (stack_offset + aligned_size > stack_memory.len) {
        return &[_]u8{}; // Out of memory
    }

    const stack = stack_memory[stack_offset .. stack_offset + aligned_size];
    stack_offset += aligned_size;
    return stack;
}

pub fn init() noreturn {
    uart.init();
    uart.puts("Hello Claudia!!\n");

    // Initialize memory subsystem
    memory.init();

    // Initialize virtual memory
    memory.initVirtual() catch |err| {
        uart.puts("Failed to initialize virtual memory: ");
        uart.putHex(@intFromError(err));
        uart.puts("\n");
        while (true) {}
    };

    // Initialize kernel heap before enabling MMU
    const kalloc = @import("memory/kalloc.zig");
    kalloc.init() catch |err| {
        uart.puts("Failed to initialize kernel heap: ");
        uart.putHex(@intFromError(err));
        uart.puts("\n");
        while (true) {}
    };

    // Initialize file system
    file.FileTable.init();

    // Initialize process scheduler
    proc.Scheduler.init();

    // Initialize trap handling
    trap.init();

    // Enable supervisor external interrupts for UART
    csr.enableInterrupts();

    // Enable external interrupts in SIE
    csr.csrs(csr.CSR.sie, 1 << 9); // SEIE bit

    // Initialize PLIC for UART interrupts
    initPLIC();

    // Initialize user subsystem
    user.init();

    // Test memory allocator
    testMemorySystem();

    // Test virtual memory system
    testVirtualMemorySystem();

    // Test file system
    testFileSystem();

    // Test user mode system calls
    testUserMode();

    // Create and start initial user process (init)
    createInitProcess();

    // Start the process scheduler - this will handle all process scheduling
    uart.puts("Starting process scheduler\n");
    proc.Scheduler.run();
}

fn testProcessSystem() void {
    uart.puts("Testing process system...\n");

    // Allocate some test processes
    const stack1 = allocStack(1024);
    const stack2 = allocStack(1024);
    const stack3 = allocStack(1024);

    if (stack1.len == 0 or stack2.len == 0 or stack3.len == 0) {
        uart.puts("Failed to allocate stacks\n");
        return;
    }

    // Create test processes
    if (proc.Scheduler.allocProcess("init", stack1)) |p1| {
        proc.Scheduler.makeRunnable(p1);
    }

    if (proc.Scheduler.allocProcess("shell", stack2)) |p2| {
        proc.Scheduler.makeRunnable(p2);
    }

    if (proc.Scheduler.allocProcess("worker", stack3)) |p3| {
        proc.Scheduler.makeRunnable(p3);
    }

    // Test scheduling
    uart.puts("Running scheduler test...\n");
    for (0..5) |i| {
        uart.puts("Schedule iteration ");
        uart.putHex(i);
        uart.puts("\n");
        const next_proc = proc.Scheduler.schedule();
        if (next_proc) |p| {
            uart.puts("  -> Scheduled process: ");
            uart.puts(p.getName());
            uart.puts(" (PID ");
            uart.putHex(p.pid);
            uart.puts(")\n");
        } else {
            uart.puts("  -> No process scheduled (idle)\n");
        }
    }

    uart.puts("Process system test completed\n");
}

fn testMemorySystem() void {
    uart.puts("Testing memory system...\n");

    // Get initial memory info
    const info1 = memory.getMemoryInfo();
    uart.puts("Initial memory: ");
    uart.putHex(info1.free);
    uart.puts(" bytes free\n");

    // Test allocation
    const page1 = memory.allocFrame();
    const page2 = memory.allocFrame();
    const page3 = memory.allocFrame();

    if (page1) |p1| {
        uart.puts("Allocated page1 at: ");
        uart.putHex(p1);
        uart.puts("\n");
    }

    if (page2) |p2| {
        uart.puts("Allocated page2 at: ");
        uart.putHex(p2);
        uart.puts("\n");
    }

    if (page3) |p3| {
        uart.puts("Allocated page3 at: ");
        uart.putHex(p3);
        uart.puts("\n");
    }

    // Check memory after allocation
    const info2 = memory.getMemoryInfo();
    uart.puts("After allocation: ");
    uart.putHex(info2.free);
    uart.puts(" bytes free\n");

    // Test free
    if (page2) |p2| {
        memory.freeFrame(p2);
        uart.puts("Freed page2\n");
    }

    // Check memory after free
    const info3 = memory.getMemoryInfo();
    uart.puts("After free: ");
    uart.putHex(info3.free);
    uart.puts(" bytes free\n");

    uart.puts("Memory system test completed\n");
}

fn testVirtualMemorySystem() void {
    uart.puts("Testing virtual memory system...\n");

    // Test address translation before MMU
    const page_table = memory.virtual.getCurrentPageTable();

    // Test translation for kernel memory
    const test_vaddr: usize = 0x80200000; // Kernel start
    if (page_table.translate(test_vaddr)) |paddr| {
        uart.puts("Translation test: ");
        uart.putHex(test_vaddr);
        uart.puts(" -> ");
        uart.putHex(paddr);
        uart.puts("\n");
    } else {
        uart.puts("Translation failed for kernel address\n");
    }

    // Enable MMU
    uart.puts("Enabling MMU...\n");
    memory.enableMMU();

    // Test that we can still access memory after MMU
    uart.puts("MMU enabled successfully - kernel still accessible\n");

    // Test UART access after MMU
    uart.puts("UART still working after MMU enablement\n");

    uart.puts("Virtual memory system test completed\n");
}

fn testFileSystem() void {
    uart.puts("Testing file system...\n");

    // Test inode allocation with reference counting
    const TestInodeOps = struct {
        fn read(inode: *file.Inode, buffer: []u8, offset: u64) isize {
            _ = inode;
            _ = buffer;
            _ = offset;
            return 0;
        }

        fn write(inode: *file.Inode, data: []const u8, offset: u64) isize {
            _ = inode;
            _ = offset;
            return @intCast(data.len);
        }

        fn truncate(inode: *file.Inode, size: u64) !void {
            _ = inode;
            _ = size;
        }

        const ops = file.InodeOperations{
            .read = read,
            .write = write,
            .truncate = truncate,
            .lookup = null,
        };
    };

    // Test inode allocation
    const inode1 = file.allocInode(.REGULAR, &TestInodeOps.ops);
    if (inode1) |i| {
        uart.puts("Allocated inode ");
        uart.putHex(i.inum);
        uart.puts(" with ref_count=");
        uart.putHex(i.ref_count);
        uart.puts("\n");

        // Test reference counting
        i.ref();
        uart.puts("After ref(): ref_count=");
        uart.putHex(i.ref_count);
        uart.puts("\n");

        // Release one reference
        i.unref();
        uart.puts("After unref(): ref_count=");
        uart.putHex(i.ref_count);
        uart.puts("\n");

        // Release final reference (should auto-free)
        file.freeInode(i);
        uart.puts("Inode freed\n");
    }

    uart.puts("File system test completed\n");
}

fn testUserMode() void {
    uart.puts("Testing user mode system calls...\n");

    // Simple test: make a write syscall from kernel mode
    // This tests the syscall mechanism without actual user mode switch
    const test_msg = "Hello from syscall!\n";

    // Simulate syscall by calling trap handler directly
    var frame = std.mem.zeroes(trap.TrapFrame);

    // Set only the required fields for this test
    frame.a0 = 1; // stdout
    frame.a1 = @intFromPtr(test_msg.ptr);
    frame.a2 = test_msg.len;
    frame.a7 = 64; // sys_write
    frame.scause = 8; // EcallFromUMode

    trap.trapHandler(&frame);

    if (frame.a0 == test_msg.len) {
        uart.puts("System call test passed! (bytes written: ");
        uart.putHex(frame.a0);
        uart.puts(")\n");
    } else {
        uart.puts("System call test failed! (result: ");
        uart.putHex(frame.a0);
        uart.puts(")\n");
    }

    uart.puts("User mode test completed\n");
}

fn createInitProcess() void {
    uart.puts("Creating init process...\n");

    // Allocate kernel stack for the process
    const kernel_stack = allocStack(4096);
    if (kernel_stack.len == 0) {
        uart.puts("Failed to allocate kernel stack for init\n");
        while (true) {
            csr.wfi();
        }
    }

    // Create the init process
    if (proc.Scheduler.allocProcess("init", kernel_stack)) |init_proc| {
        // Set up process to run user mode shell
        setupUserProcess(init_proc);

        // Make the process runnable
        proc.Scheduler.makeRunnable(init_proc);
        uart.puts("Init process created and made runnable\n");
    } else {
        uart.puts("Failed to allocate init process\n");
        while (true) {
            csr.wfi();
        }
    }
}

fn setupUserProcess(process: *proc.Process) void {
    // This function will set up the process context to run the user shell
    // For now, we'll set up a basic context that will be used when the process
    // is scheduled to run

    // Get the init program code
    const _user_shell_start = @extern([*]const u8, .{ .name = "_user_shell_start" });
    const _user_shell_end = @extern([*]const u8, .{ .name = "_user_shell_end" });

    const start_addr = @intFromPtr(_user_shell_start);
    const end_addr = @intFromPtr(_user_shell_end);
    const code_size = end_addr - start_addr;

    uart.puts("Setting up user process with binary size: ");
    uart.putHex(code_size);
    uart.puts("\n");

    // Store user program entry point in process context
    // This will be used when the process is scheduled
    process.context.sepc = 0x1001474; // Entry point from ELF header

    // Set up user stack pointer
    const mtypes = @import("memory/types.zig");
    process.context.sp = mtypes.USER_STACK_BASE + mtypes.USER_STACK_SIZE - 16;

    // Set up sstatus for user mode
    process.context.sstatus = csr.SSTATUS.SPIE; // Enable interrupts when returning to user

    uart.puts("User process context setup complete\n");
}

// Initialize PLIC for UART interrupts
fn initPLIC() void {
    uart.puts("Initializing PLIC for UART interrupts\n");

    // PLIC addresses for RISC-V virt machine
    const PLIC_BASE: u64 = 0x0c000000;
    const PLIC_PRIORITY = PLIC_BASE + 0x000000; // Interrupt source priority
    const PLIC_ENABLE = PLIC_BASE + 0x002000; // Interrupt enable bits
    const PLIC_THRESHOLD = PLIC_BASE + 0x200000; // Priority threshold

    // UART0 is interrupt source 10 in QEMU virt machine
    const UART_IRQ: u32 = 10;

    // Set UART interrupt priority to 1 (non-zero enables it)
    const priority_addr = @as(*volatile u32, @ptrFromInt(PLIC_PRIORITY + UART_IRQ * 4));
    priority_addr.* = 1;

    // Enable UART interrupt for hart 0, context 1 (supervisor mode)
    const enable_addr = @as(*volatile u32, @ptrFromInt(PLIC_ENABLE + 0x80)); // Hart 0, context 1
    enable_addr.* = 1 << UART_IRQ;

    // Set priority threshold to 0 (accept all priorities)
    const threshold_addr = @as(*volatile u32, @ptrFromInt(PLIC_THRESHOLD));
    threshold_addr.* = 0;

    uart.puts("PLIC initialized: UART IRQ enabled\n");
}
