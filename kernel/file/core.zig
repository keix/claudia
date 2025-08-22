// File abstraction for Claudia kernel
// Provides POSIX-like file interface with device drivers

const std = @import("std");
const uart = @import("../driver/uart/core.zig");
const defs = @import("abi");
const proc = @import("../process/core.zig");

// Import submodules
pub const types = @import("types.zig");
const inode = @import("inode.zig");

// Re-export common types
pub const FD = types.FD;
pub const FileType = types.FileType;
pub const Inode = inode.Inode;
pub const InodeOperations = inode.InodeOperations;

// File operations function pointers
pub const FileOperations = struct {
    read: *const fn (*File, []u8) isize,
    write: *const fn (*File, []const u8) isize,
    close: *const fn (*File) void,
};

// File structure
pub const File = struct {
    type: types.FileType,
    operations: *const FileOperations,
    ref_count: u32,
    flags: u32,

    // Device-specific data
    device_data: ?*anyopaque,

    // Associated inode (optional for device files)
    inode: ?*Inode,

    pub fn init(file_type: types.FileType, ops: *const FileOperations) File {
        return File{
            .type = file_type,
            .operations = ops,
            .ref_count = 1,
            .flags = 0,
            .device_data = null,
            .inode = null,
        };
    }

    pub fn initWithInode(inode_ptr: *Inode, ops: *const FileOperations) File {
        return File{
            .type = inode_ptr.type,
            .operations = ops,
            .ref_count = 1,
            .flags = 0,
            .device_data = null,
            .inode = inode_ptr,
        };
    }

    pub fn read(self: *File, buffer: []u8) isize {
        return self.operations.read(self, buffer);
    }

    pub fn write(self: *File, data: []const u8) isize {
        return self.operations.write(self, data);
    }

    pub fn close(self: *File) void {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
            if (self.ref_count == 0) {
                self.operations.close(self);
            }
        }
    }

    pub fn addRef(self: *File) void {
        self.ref_count += 1;
    }
};

// Line buffer for canonical mode
const LineBuffer = struct {
    buffer: [256]u8,
    len: usize,

    fn init() LineBuffer {
        return LineBuffer{
            .buffer = std.mem.zeroes([256]u8),
            .len = 0,
        };
    }

    fn reset(self: *LineBuffer) void {
        self.len = 0;
    }

    fn append(self: *LineBuffer, ch: u8) bool {
        if (self.len >= self.buffer.len - 1) return false; // Leave room for null terminator
        self.buffer[self.len] = ch;
        self.len += 1;
        return true;
    }

    fn backspace(self: *LineBuffer) bool {
        if (self.len > 0) {
            self.len -= 1;
            return true;
        }
        return false;
    }

    fn getLine(self: *const LineBuffer) []const u8 {
        return self.buffer[0..self.len];
    }
};

// TTY structure with input buffer and wait queue
const RingBuffer = struct {
    buffer: [256]u8,
    head: usize,
    tail: usize,

    fn init() RingBuffer {
        return RingBuffer{
            .buffer = std.mem.zeroes([256]u8),
            .head = 0,
            .tail = 0,
        };
    }

    fn isEmpty(self: *const RingBuffer) bool {
        return self.head == self.tail;
    }

    fn isFull(self: *const RingBuffer) bool {
        return (self.head + 1) % self.buffer.len == self.tail;
    }

    fn put(self: *RingBuffer, ch: u8) bool {
        if (self.isFull()) return false;
        self.buffer[self.head] = ch;
        self.head = (self.head + 1) % self.buffer.len;
        return true;
    }

    fn get(self: *RingBuffer) ?u8 {
        if (self.isEmpty()) return null;
        const ch = self.buffer[self.tail];
        self.tail = (self.tail + 1) % self.buffer.len;
        return ch;
    }
};

const TTY = struct {
    input_buffer: RingBuffer,
    line_buffer: LineBuffer,
    canonical_mode: bool,
    echo_enabled: bool,
    read_wait: proc.WaitQ,
    magic: u32, // Magic number for corruption detection

    fn init() TTY {
        return TTY{
            .input_buffer = RingBuffer.init(),
            .line_buffer = LineBuffer.init(),
            .canonical_mode = true, // Default to canonical mode
            .echo_enabled = true, // Default to echo enabled
            .read_wait = proc.WaitQ.init(),
            .magic = 0xDEADBEEF,
        };
    }

    fn putChar(self: *TTY, ch: u8) void {
        if (self.input_buffer.put(ch)) {
            // Wake up any processes waiting for input
            proc.Scheduler.wakeAll(&self.read_wait);
        }
    }

    fn getChar(self: *TTY) ?u8 {
        return self.input_buffer.get();
    }

    fn getCharAtomic(self: *TTY) ?u8 {
        const csr = @import("../arch/riscv/csr.zig");
        
        // Validate TTY structure to detect corruption
        if (self.magic != 0xDEADBEEF) {
            uart.puts("[PANIC] TTY structure corrupted in getCharAtomic!\n");
            @panic("TTY structure corrupted!");
        }
        
        // Save current interrupt state and disable interrupts
        const saved_sstatus = csr.csrrc(csr.CSR.sstatus, csr.SSTATUS.SIE);
        defer {
            // Restore interrupts if they were previously enabled
            if ((saved_sstatus & csr.SSTATUS.SIE) != 0) {
                csr.enableInterrupts();
            }
        }
        return self.input_buffer.get();
    }

    fn putCharAtomic(self: *TTY, ch: u8) bool {
        const csr = @import("../arch/riscv/csr.zig");
        // Save current interrupt state and disable interrupts
        const saved_sstatus = csr.csrrc(csr.CSR.sstatus, csr.SSTATUS.SIE);
        defer {
            // Restore interrupts if they were previously enabled
            if ((saved_sstatus & csr.SSTATUS.SIE) != 0) {
                csr.enableInterrupts();
            }
        }
        return self.input_buffer.put(ch);
    }
};

var console_tty = TTY.init();

// Ensure console_tty is in data section and properly aligned
comptime {
    _ = &console_tty;
}

// Global counters for lost-wakeup debugging

// UART interrupt handler to feed TTY - drain FIFO completely
pub fn uartIsr() void {
    var chars_received = false;
    var char_count: u32 = 0;
    var has_newline = false;

    // Drain RX FIFO completely - critical for preventing lost chars
    while (uart.getc()) |ch| {
        // Feed directly to TTY ring buffer with atomic access
        if (console_tty.putCharAtomic(ch)) {
            chars_received = true;
            char_count += 1;
            if (ch == '\n' or ch == '\r') {
                has_newline = true;
            }
        }
        // If ring buffer full, drop character (could log this)
    }


    // Wake readers based on mode
    if (chars_received) {
        if (!console_tty.canonical_mode) {
            // Raw mode: wake on any character
            proc.Scheduler.wakeAll(&console_tty.read_wait);
        } else if (has_newline) {
            // Canonical mode: wake only on newline
            proc.Scheduler.wakeAll(&console_tty.read_wait);
        }
    }
}

// Console device operations (stdout/stderr)
const ConsoleOperations = FileOperations{
    .read = consoleRead,
    .write = consoleWrite,
    .close = consoleClose,
};

fn consoleRead(file: *File, buffer: []u8) isize {
    _ = file;

    if (buffer.len == 0) return 0;

    const copy = @import("../user/copy.zig");
    const user_addr = @intFromPtr(buffer.ptr);

    // Handle canonical vs raw mode
    // Validate TTY before accessing it
    if (console_tty.magic != 0xDEADBEEF) {
        uart.puts("[PANIC] TTY not initialized or corrupted in consoleRead\n");
        return 5; // EIO
    }
    
    if (console_tty.canonical_mode) {
        // Canonical mode: read a complete line
        return consoleReadCanonical(buffer, user_addr);
    } else {
        // Raw mode: read single characters (existing behavior)
        while (true) {
            // Check TTY ring buffer first with atomic access
            if (console_tty.getCharAtomic()) |ch| {
                const char_buf = [1]u8{ch};
                _ = copy.copyout(user_addr, &char_buf) catch return defs.EFAULT;
                return 1;
            }


            // No data available - wait for input
            if (proc.Scheduler.getCurrentProcess()) |current| {
                // Conditional sleep: only sleep if buffer is empty (spurious wakeup protection)
                if (console_tty.input_buffer.isEmpty()) {
                    proc.Scheduler.sleepOn(&console_tty.read_wait, current);
                }
            } else {
                // Boot context without process - use WFI
                const csr = @import("../arch/riscv/csr.zig");
                csr.enableInterrupts();
                csr.wfi();
            }
        }
    }
}

// Canonical mode read - process line buffering
fn consoleReadCanonical(buffer: []u8, user_addr: usize) isize {
    const copy = @import("../user/copy.zig");
    
    // Note: We're already in kernel mode if this function is executing.
    // SPP bit tells us where we came FROM on the last trap, not where we ARE now.

    // Build a line in the kernel's line buffer
    while (true) {
        // Try to get a character
        var ch: ?u8 = null;

        // Critical section: get character atomically
        // Validate pointer before calling method
        const tty_ptr = &console_tty;
        if (@intFromPtr(tty_ptr) == 0 or @intFromPtr(tty_ptr) > 0xFFFFFFFFFFFFFFFF) {
            uart.puts("[PANIC] Invalid TTY pointer in consoleReadCanonical\n");
            @panic("Invalid TTY pointer");
        }
        ch = tty_ptr.getCharAtomic();

        if (ch) |c| {
            // Process the character
            if (c == '\n' or c == '\r') {
                // End of line - echo newline if echo is enabled
                if (console_tty.echo_enabled) {
                    uart.putc('\n');
                }

                // Copy the line to user buffer
                const line = console_tty.line_buffer.getLine();
                const copy_len = @min(line.len, buffer.len - 1); // Leave room for newline

                if (copy_len > 0) {
                    _ = copy.copyout(user_addr, line[0..copy_len]) catch return defs.EFAULT;
                }

                // Add newline to the output
                const nl_buf = [1]u8{'\n'};
                _ = copy.copyout(user_addr + copy_len, &nl_buf) catch return defs.EFAULT;

                // Reset line buffer for next line
                console_tty.line_buffer.reset();

                return @intCast(copy_len + 1); // Include the newline
            } else if (c == 0x08 or c == 0x7F) { // Backspace or DEL
                if (console_tty.line_buffer.backspace()) {
                    // Echo backspace sequence if echo is enabled
                    if (console_tty.echo_enabled) {
                        uart.putc(0x08); // Move cursor back
                        uart.putc(' '); // Overwrite with space
                        uart.putc(0x08); // Move cursor back again
                    }
                }
            } else if (c >= 32 and c <= 126) { // Printable character
                if (console_tty.line_buffer.append(c)) {
                    // Echo the character if echo is enabled
                    if (console_tty.echo_enabled) {
                        uart.putc(c);
                    }
                } else {
                    // Line buffer full - beep or ignore
                    if (console_tty.echo_enabled) {
                        uart.putc(0x07); // BEL character
                    }
                }
            }
            // Ignore other control characters for now
        } else {
            // No data available - wait for input
            // Get current process and sleep on wait queue
            if (proc.Scheduler.getCurrentProcess()) |current| {
                proc.Scheduler.sleepOn(&console_tty.read_wait, current);
            } else {
                // No current process, fall back to polling
                const csr = @import("../arch/riscv/csr.zig");
                csr.enableInterrupts();
                csr.wfi();
            }
        }
    }
}

fn consoleWrite(file: *File, data: []const u8) isize {
    _ = file;
    // Write to UART console
    for (data) |byte| {
        uart.putc(byte);
    }
    return @as(isize, @intCast(data.len));
}

fn consoleClose(file: *File) void {
    _ = file;
    // Console files don't need cleanup
}

// Standard file descriptors
const MAX_FDS = 256;
var file_table: [MAX_FDS]?*File = [_]?*File{null} ** MAX_FDS;

// Console file instances
var console_file = File.init(.DEVICE, &ConsoleOperations);

// File descriptor management
pub const FileTable = struct {
    pub fn init() void {

        // Initialize standard file descriptors
        // fd 0: stdin -> console (UART input)
        file_table[0] = &console_file;
        console_file.addRef(); // Add reference for stdin

        // fd 1: stdout -> console (UART)
        file_table[1] = &console_file;

        // fd 2: stderr -> console (UART)
        file_table[2] = &console_file;
        console_file.addRef(); // Add reference for stdout
        console_file.addRef(); // Add reference for stderr

    }

    pub fn getFile(fd: FD) ?*File {
        if (fd < 0 or fd >= MAX_FDS) {
            return null;
        }
        return file_table[@as(usize, @intCast(fd))];
    }

    pub fn allocFd(file: *File) ?FD {
        // Start from 3 (after stdin/stdout/stderr)
        for (3..MAX_FDS) |i| {
            if (file_table[i] == null) {
                file_table[i] = file;
                file.addRef();
                return @as(FD, @intCast(i));
            }
        }
        return null; // No free file descriptors
    }

    pub fn closeFd(fd: FD) void {
        if (fd < 0 or fd >= MAX_FDS) {
            return;
        }

        const idx = @as(usize, @intCast(fd));
        if (file_table[idx]) |file| {
            file.close();
            file_table[idx] = null;
        }
    }

    // System call implementations
    pub fn sysRead(fd: FD, buffer: []u8) isize {
        if (getFile(fd)) |file| {
            return file.read(buffer);
        }
        return defs.EBADF;
    }

    pub fn sysWrite(fd: FD, data: []const u8) isize {
        if (getFile(fd)) |file| {
            return file.write(data);
        }
        return defs.EBADF;
    }

    pub fn sysClose(fd: FD) isize {
        if (fd < 0 or fd >= MAX_FDS) {
            return defs.EBADF;
        }

        // Don't allow closing standard descriptors
        if (fd <= 2) {
            return defs.EBUSY;
        }

        closeFd(fd);
        return 0;
    }
};

// Inode management API
pub const allocInode = inode.alloc;
pub const freeInode = inode.free;

// Integrated file creation
pub fn createFile(file_type: types.FileType, inode_ops: *const InodeOperations, file_ops: *const FileOperations) ?*File {
    _ = file_ops; // TODO: Use this parameter
    const new_inode = allocInode(file_type, inode_ops) orelse return null;
    _ = new_inode; // TODO: Use this to create actual file
    // This would need integration with FileTable for actual file creation
    return null; // Placeholder - would return allocated File
}
