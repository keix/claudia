// Simple fork test - parent and child both print messages
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Before fork\n");

    const pid = sys.fork() catch {
        utils.writeStr("Fork failed!\n");
        return;
    };

    if (pid == 0) {
        // Child process
        utils.writeStr("Child: Hello from child!\n");
        utils.writeStr("Child: PID = ");
        const child_pid = sys.getpid();
        utils.writeStr(utils.intToStr(@intCast(child_pid)));
        utils.writeStr("\n");
        utils.writeStr("Child: Exiting\n");
        sys.exit(0);
    } else {
        // Parent process
        utils.writeStr("Parent: Fork returned PID = ");
        utils.writeStr(utils.intToStr(@intCast(pid)));
        utils.writeStr("\n");
        utils.writeStr("Parent: Continuing\n");
    }

    utils.writeStr("After fork (only parent should see this)\n");
}
