// File abstraction for Claudia kernel
// Provides POSIX-like file interface with device drivers

const std = @import("std");
const uart = @import("../driver/uart/core.zig");
const defs = @import("abi");
const proc = @import("../process/core.zig");
const vfs = @import("../fs/vfs.zig");

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
    lseek: ?*const fn (*File, i64, u32) isize = null,
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

    pub fn lseek(self: *File, offset: i64, whence: u32) isize {
        if (self.operations.lseek) |lseek_fn| {
            return lseek_fn(self, offset, whence);
        }
        return defs.ESPIPE; // Illegal seek (not seekable)
    }

    pub fn addRef(self: *File) void {
        self.ref_count += 1;
    }
};

// Buffer size constants
const RING_BUFFER_SIZE: usize = 256;
const LINE_BUFFER_SIZE: usize = 256;
const TTY_MAGIC: u32 = 0xDEADBEEF;

// Line buffer for canonical mode
const LineBuffer = struct {
    buffer: [LINE_BUFFER_SIZE]u8,
    len: usize,

    fn init() LineBuffer {
        return LineBuffer{
            .buffer = std.mem.zeroes([LINE_BUFFER_SIZE]u8),
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
    buffer: [RING_BUFFER_SIZE]u8,
    head: usize,
    tail: usize,

    fn init() RingBuffer {
        return RingBuffer{
            .buffer = std.mem.zeroes([RING_BUFFER_SIZE]u8),
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
            .magic = TTY_MAGIC,
        };
    }

    fn getCharAtomic(self: *TTY) ?u8 {
        const csr = @import("../arch/riscv/csr.zig");

        // Validate TTY structure to detect corruption
        if (self.magic != TTY_MAGIC) {
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

            // Echo immediately if echo is enabled and in canonical mode
            if (console_tty.echo_enabled and console_tty.canonical_mode) {
                if (ch == '\n' or ch == '\r') {
                    uart.putc('\n');
                } else if (ch == 0x08 or ch == 0x7F) { // Backspace or DEL
                    // Don't echo backspace here - the read handler needs to check
                    // if there's actually something to delete in the line buffer
                } else if (ch >= 32 and ch <= 126) { // Printable character
                    uart.putc(ch);
                }
            }
        } else {
            // Ring buffer full - character dropped
            // TODO: Add debug logging when available
        }
    }

    // Wake readers based on mode
    if (chars_received) {
        if (!console_tty.canonical_mode) {
            // Raw mode: wake on any character
            proc.Scheduler.wakeAll(&console_tty.read_wait);
        } else {
            // Canonical mode: wake on every character to process echo/backspace
            // This ensures immediate response for line editing
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
    const csr = @import("../arch/riscv/csr.zig");

    // Handle canonical vs raw mode
    // Validate TTY before accessing it
    if (console_tty.magic != TTY_MAGIC) {
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
                    // sleepOn now handles interrupt enabling internally
                    proc.Scheduler.sleepOn(&console_tty.read_wait, current);
                }
            } else {
                // Boot context without process - use WFI
                csr.enableInterrupts();
                csr.wfi();
            }
        }
    }
}

// Canonical mode read - process line buffering
fn consoleReadCanonical(buffer: []u8, user_addr: usize) isize {
    const copy = @import("../user/copy.zig");
    const csr = @import("../arch/riscv/csr.zig");

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
            @panic("Invalid TTY pointer");
        }
        ch = tty_ptr.getCharAtomic();

        if (ch) |c| {
            // Process the character
            if (c == '\n' or c == '\r') {
                // End of line - newline already echoed by ISR

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
                    // Character already echoed by ISR
                } else {
                    // Line buffer full - beep or ignore
                    if (console_tty.echo_enabled) {
                        uart.putc(0x07); // BEL character
                    }
                }
            }
            // Ignore other control characters for now
        } else {
            // No data → 待機
            if (proc.Scheduler.getCurrentProcess()) |current| {
                // sleepOn now handles interrupt enabling internally
                proc.Scheduler.sleepOn(&console_tty.read_wait, current);
            } else {
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

// File descriptor constants
const MAX_FDS = 256;
const STDIN_FD = 0;
const STDOUT_FD = 1;
const STDERR_FD = 2;
var file_table: [MAX_FDS]?*File = [_]?*File{null} ** MAX_FDS;

// Console file instances
var console_file = File.init(.DEVICE, &ConsoleOperations);

// Null device operations
const NullOperations = FileOperations{
    .read = nullRead,
    .write = nullWrite,
    .close = nullClose,
};

fn nullRead(file: *File, buffer: []u8) isize {
    _ = file;
    _ = buffer;
    // /dev/null always returns EOF (0 bytes)
    return 0;
}

fn nullWrite(file: *File, data: []const u8) isize {
    _ = file;
    // /dev/null discards all data but reports success
    return @as(isize, @intCast(data.len));
}

fn nullClose(file: *File) void {
    _ = file;
    // Nothing to clean up
}

// Null device file instance
var null_file = File.init(.DEVICE, &NullOperations);

// File descriptor management
pub const FileTable = struct {
    pub fn init() void {

        // Initialize standard file descriptors
        // fd 0: stdin -> console (UART input)
        file_table[STDIN_FD] = &console_file;
        console_file.addRef(); // Add reference for stdin

        // fd 1: stdout -> console (UART)
        file_table[STDOUT_FD] = &console_file;

        // fd 2: stderr -> console (UART)
        file_table[STDERR_FD] = &console_file;
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
                // Don't add reference here - the file already has ref_count = 1 from creation
                // file.addRef();
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
        if (fd <= STDERR_FD) {
            return defs.EBUSY;
        }

        closeFd(fd);
        return 0;
    }

    pub fn sysLseek(fd: FD, offset: i64, whence: u32) isize {
        if (getFile(fd)) |file| {
            return file.lseek(offset, whence);
        }
        return defs.EBADF;
    }

    pub fn sysOpen(path: []const u8, flags: u32, mode: u16) isize {
        _ = mode; // Ignore mode for now

        // Build absolute path if needed
        var abs_path_buf: [256]u8 = undefined;
        var abs_path: []const u8 = undefined;

        if (path.len > 0 and path[0] == '/') {
            // Already absolute
            abs_path = path;
        } else if (path.len == 1 and path[0] == '.') {
            // Current directory
            const process = proc.current_process orelse return defs.ESRCH;
            abs_path = process.cwd[0..process.cwd_len];
        } else {
            // Relative path - prepend current directory
            const process = proc.current_process orelse return defs.ESRCH;
            const cwd_len = process.cwd_len;

            // Check buffer size
            if (cwd_len + 1 + path.len >= abs_path_buf.len) {
                return defs.ENAMETOOLONG;
            }

            // Build absolute path
            @memcpy(abs_path_buf[0..cwd_len], process.cwd[0..cwd_len]);
            var pos = cwd_len;

            // Add separator if needed
            if (cwd_len > 1 and process.cwd[cwd_len - 1] != '/') {
                abs_path_buf[pos] = '/';
                pos += 1;
            }

            // Add relative path
            @memcpy(abs_path_buf[pos .. pos + path.len], path);
            pos += path.len;

            abs_path = abs_path_buf[0..pos];
        }

        // Use VFS to resolve the absolute path
        var node = vfs.resolvePath(abs_path);

        // Handle file creation if O_CREAT is set
        if (node == null and (flags & defs.O_CREAT) != 0) {
            // Extract directory and filename from absolute path
            var last_slash: ?usize = null;
            for (abs_path, 0..) |ch, i| {
                if (ch == '/') last_slash = i;
            }

            if (last_slash) |slash_pos| {
                const dir_path = if (slash_pos == 0) "/" else abs_path[0..slash_pos];
                const filename = abs_path[slash_pos + 1 ..];

                // Create the file
                if (vfs.createFile(dir_path, filename)) |new_node| {
                    node = new_node;
                } else {
                    return defs.ENOSPC; // No space or other error
                }
            } else {
                // No directory specified, use current directory
                const process = proc.current_process orelse return defs.ESRCH;
                const cwd = process.cwd[0..process.cwd_len];
                if (vfs.createFile(cwd, abs_path)) |new_node| {
                    node = new_node;
                } else {
                    return defs.ENOSPC;
                }
            }
        }

        const vnode = node orelse {
            return defs.ENOENT;
        };

        // Handle different node types
        switch (vnode.node_type) {
            .DEVICE => {
                // For device files, check which device it is
                if (std.mem.eql(u8, vnode.getName(), "console") or
                    std.mem.eql(u8, vnode.getName(), "tty"))
                {
                    // Allocate a new fd for console
                    if (allocFd(&console_file)) |fd| {
                        return @as(isize, @intCast(fd));
                    }
                    return defs.EMFILE; // Too many open files
                } else if (std.mem.eql(u8, vnode.getName(), "null")) {
                    // Allocate a new fd for /dev/null
                    if (allocFd(&null_file)) |fd| {
                        return @as(isize, @intCast(fd));
                    }
                    return defs.EMFILE; // Too many open files
                } else if (std.mem.eql(u8, vnode.getName(), "ramdisk")) {
                    // Allocate a new fd for /dev/ramdisk
                    const blockfile = @import("blockfile.zig");
                    if (blockfile.getRamdiskFile()) |bf| {
                        if (allocFd(&bf.file)) |fd| {
                            return @as(isize, @intCast(fd));
                        }
                        return defs.EMFILE; // Too many open files
                    }
                    return defs.ENODEV;
                }
                return defs.ENODEV; // Device not supported
            },
            .FILE => {
                // Regular file support using memory files
                const memfile = @import("memfile.zig");
                if (memfile.allocMemFile(vnode)) |mf| {
                    if (allocFd(&mf.file)) |fd| {
                        return @as(isize, @intCast(fd));
                    }
                    // Failed to allocate fd, free the memfile
                    memfile.freeMemFile(mf);
                    return defs.EMFILE;
                }
                return defs.ENOMEM; // No memory for file structure
            },
            .DIRECTORY => {
                // Check if O_DIRECTORY flag is set or if opening for read-only
                if ((flags & defs.O_DIRECTORY) != 0 or flags == defs.O_RDONLY) {
                    // Create a directory file descriptor
                    const dirfile = @import("dirfile.zig");
                    if (dirfile.allocDirFile(vnode)) |df| {
                        if (allocFd(&df.file)) |fd| {
                            return @as(isize, @intCast(fd));
                        }
                        // Failed to allocate fd, free the dirfile
                        dirfile.freeDirFile(df);
                        return defs.EMFILE;
                    }
                    return defs.ENOMEM;
                }
                return defs.EISDIR;
            },
        }
    }
};

// Inode management API
pub const allocInode = inode.alloc;
pub const freeInode = inode.free;
