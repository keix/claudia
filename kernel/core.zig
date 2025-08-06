const std = @import("std");
const csr = @import("arch/riscv/csr.zig");
const uart = @import("driver/uart/core.zig");
const proc = @import("process/core.zig");
const file = @import("file/core.zig");
const memory = @import("memory/core.zig");

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

    // Initialize file system
    file.FileTable.init();

    // Initialize process scheduler
    proc.Scheduler.init();

    // Test memory allocator
    testMemorySystem();

    // Test virtual memory system
    testVirtualMemorySystem();

    // Test file system
    testFileSystem();

    // Test process creation
    testProcessSystem();

    // Hand over control to scheduler
    uart.puts("Handing control to scheduler\n");
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
