// Minimal fork test - avoids utils.intToStr completely
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Starting minimal fork test\n");

    const pid = sys.fork() catch {
        utils.writeStr("Fork failed!\n");
        return;
    };

    if (pid == 0) {
        // Child process - minimal work
        utils.writeStr("C\n");
        sys.exit(0);
    } else {
        // Parent process
        utils.writeStr("P\n");

        // Small delay to let child finish
        for (0..1000000) |_| {
            asm volatile ("nop");
        }
    }

    utils.writeStr("Done\n");
}
