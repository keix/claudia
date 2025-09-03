// Test dup/dup2 system calls
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Testing dup/dup2 system calls...\n");

    // Test 1: Basic dup - duplicate stdout
    utils.writeStr("\nTest 1: Duplicating stdout with dup()\n");
    const new_fd = sys.dup(1) catch |err| {
        utils.writeStr("dup(1) failed: ");
        utils.writeStr(@errorName(err));
        utils.writeStr("\n");
        return;
    };

    utils.writeStr("dup(1) returned fd: ");
    utils.writeStr(utils.intToStr(new_fd));
    utils.writeStr("\n");

    // Write to the new fd
    const msg1 = "Hello from duplicated fd!\n";
    _ = sys.write(@intCast(new_fd), &msg1[0], msg1.len);

    // Close the duplicated fd
    _ = sys.close(@intCast(new_fd));
    utils.writeStr("Closed duplicated fd\n");

    // Test 2: dup2 - duplicate stdout to specific fd
    utils.writeStr("\nTest 2: Duplicating stdout to fd 10 with dup2()\n");
    const target_fd = sys.dup2(1, 10) catch |err| {
        utils.writeStr("dup2(1, 10) failed: ");
        utils.writeStr(@errorName(err));
        utils.writeStr("\n");
        return;
    };

    utils.writeStr("dup2(1, 10) returned fd: ");
    utils.writeStr(utils.intToStr(target_fd));
    utils.writeStr("\n");

    // Write to fd 10
    const msg2 = "Hello from fd 10!\n";
    _ = sys.write(10, &msg2[0], msg2.len);

    // Test 3: dup2 with same fd
    utils.writeStr("\nTest 3: dup2 with same fd\n");
    const same_fd = sys.dup2(1, 1) catch |err| {
        utils.writeStr("dup2(1, 1) failed: ");
        utils.writeStr(@errorName(err));
        utils.writeStr("\n");
        return;
    };
    utils.writeStr("dup2(1, 1) returned: ");
    utils.writeStr(utils.intToStr(same_fd));
    utils.writeStr("\n");

    // Test 4: Test with file
    utils.writeStr("\nTest 4: dup with file\n");
    const path = "test_dup.txt";
    const fd = sys.open(&path[0], sys.abi.O_CREAT | sys.abi.O_WRONLY | sys.abi.O_TRUNC, 0o666);
    if (fd < 0) {
        utils.writeStr("open failed\n");
        return;
    }

    const dup_fd = sys.dup(@intCast(fd)) catch |err| {
        utils.writeStr("dup(file) failed: ");
        utils.writeStr(@errorName(err));
        utils.writeStr("\n");
        _ = sys.close(@intCast(fd));
        return;
    };

    utils.writeStr("File fd: ");
    utils.writeStr(utils.intToStr(@intCast(fd)));
    utils.writeStr(", duplicated fd: ");
    utils.writeStr(utils.intToStr(dup_fd));
    utils.writeStr("\n");

    // Write to both fds
    const msg3 = "Original fd\n";
    const msg4 = "Duplicated fd\n";
    _ = sys.write(@intCast(fd), &msg3[0], msg3.len);
    _ = sys.write(@intCast(dup_fd), &msg4[0], msg4.len);

    // Close both
    _ = sys.close(@intCast(fd));
    _ = sys.close(@intCast(dup_fd));

    utils.writeStr("\nAll dup/dup2 tests completed!\n");
}
