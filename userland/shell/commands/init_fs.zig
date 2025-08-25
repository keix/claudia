// init_fs - Initialize filesystem with fizzbuzz.lisp
const sys = @import("sys");
const utils = @import("shell/utils");

// FizzBuzz Lisp script content
const FIZZBUZZ_CONTENT =
    "(define i 1)\n" ++
    "(while (<= i 100)\n" ++
    "    (cond \n" ++
    "        ((and (= (mod i 3) 0) (= (mod i 5) 0)) (print \"FizzBuzz\"))\n" ++
    "        ((= (mod i 3) 0)                       (print \"Fizz\"))\n" ++
    "        ((= (mod i 5) 0)                       (print \"Buzz\"))\n" ++
    "        (#t                                    (print i)))\n" ++
    "    (set! i (+ i 1)))";

pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Initializing filesystem with fizzbuzz.lisp...\n");
    utils.writeStr("Note: This is a demonstration of what would be done.\n");
    utils.writeStr("\nFizzBuzz script content:\n");
    utils.writeStr("------------------------\n");
    utils.writeStr(FIZZBUZZ_CONTENT);
    utils.writeStr("\n------------------------\n");
    utils.writeStr("\nTo use: lisp fizzbuzz.lisp\n");
}
