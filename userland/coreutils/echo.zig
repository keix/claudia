const write = @import("syscalls/io/write").write;
const exit = @import("syscalls/proc/exit").exit;

const STDOUT: usize = 1;

// Custom Kernel ABI Design:
// Arguments passed via fixed memory region with TLV format
const ARGS_BASE_ADDR: usize = 0x80800000;

const ArgsHeader = struct {
    magic: u32, // 0xABCD1234 - validation magic
    argc: u32, // argument count
    total_size: u32, // total size of args region
    reserved: u32, // alignment/future use
};

const ArgEntry = struct {
    len: u32, // length of this argument
    data: [*]u8, // pointer to argument data
};

// For demonstration, we'll simulate kernel-provided arguments
const SimulatedArgs = struct {
    header: ArgsHeader,
    prog_name: [4]u8 = "echo".*,
    arg1: [5]u8 = "hello".*,
    arg2: [5]u8 = "world".*,
};

var simulated_args = SimulatedArgs{
    .header = ArgsHeader{
        .magic = 0xABCD1234,
        .argc = 3,
        .total_size = @sizeOf(SimulatedArgs),
        .reserved = 0,
    },
};

fn parseCustomABI() void {
    // Try to read from actual kernel-provided location
    const args_ptr = @as(*ArgsHeader, @ptrFromInt(ARGS_BASE_ADDR));

    // Check if kernel provided valid arguments
    if (args_ptr.magic == 0xABCD1234 and args_ptr.argc > 0) {
        // Real kernel arguments found
        const msg = "Real kernel args found!\n";
        _ = write(STDOUT, @ptrCast(msg.ptr), msg.len);

        for (1..args_ptr.argc) |i| {
            if (i > 1) {
                const space = " ";
                _ = write(STDOUT, @ptrCast(space.ptr), space.len);
            }
            // Parse actual TLV arguments here
        }
    } else {
        // Fall back to simulated args for demo
        const demo_msg = "Using simulated args (kernel not ready): ";
        _ = write(STDOUT, @ptrCast(demo_msg.ptr), demo_msg.len);

        _ = write(STDOUT, @ptrCast(&simulated_args.arg1), 5);
        const space = " ";
        _ = write(STDOUT, @ptrCast(space.ptr), space.len);
        _ = write(STDOUT, @ptrCast(&simulated_args.arg2), 5);
    }

    const newline = "\n";
    _ = write(STDOUT, @ptrCast(newline.ptr), newline.len);
}

// Linux ABI compatibility version (commented for comparison)
fn parseLinuxABI() void {
    // Linux ABI expects argc at SP+0, argv at SP+8
    // This approach requires kernel to setup stack like Linux

    // asm volatile (
    //     "mv %[argc_out], sp"
    //     : [argc_out] "=r" (argc_ptr)
    //     :
    //     : "memory"
    // );
    // const argc = @as(*u64, @ptrFromInt(argc_ptr)).*;
    // const argv = @as(*[*]*u8, @ptrFromInt(argc_ptr + 8)).*;
}

export fn _start() noreturn {
    const header_msg = "Custom Kernel ABI Echo Demo\n";
    _ = write(STDOUT, @ptrCast(header_msg.ptr), header_msg.len);

    parseCustomABI();

    exit(0);
}
