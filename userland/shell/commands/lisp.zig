// Minimal Lisp interpreter for Claudia
const utils = @import("shell/utils");
const sys = @import("sys");

// Simple fixed-size allocator
var global_buffer: [8192]u8 = undefined;
var global_pos: usize = 0;

fn alloc(size: usize) ?[]u8 {
    if (global_pos + size > global_buffer.len) return null;
    const ptr = global_buffer[global_pos .. global_pos + size];
    global_pos += size;
    return ptr;
}

fn resetAlloc() void {
    global_pos = 0;
}

// Atom types
const Atom = union(enum) {
    Number: i32,
    Symbol: []const u8,
    Boolean: bool,
    String: []const u8,
};

// List structure
const List = struct {
    items: [32]LispValue, // Fixed size
    len: usize,
};

// Lisp value
const LispValue = union(enum) {
    Atom: Atom,
    List: *List,

    fn print(self: LispValue) void {
        switch (self) {
            .Atom => |atom| {
                switch (atom) {
                    .Number => |n| utils.writeStr(utils.intToStr(n)),
                    .Symbol => |s| utils.writeStr(s),
                    .Boolean => |b| utils.writeStr(if (b) "#t" else "#f"),
                    .String => |s| {
                        utils.writeStr("\"");
                        utils.writeStr(s);
                        utils.writeStr("\"");
                    },
                }
            },
            .List => |list| {
                utils.writeStr("(");
                for (0..list.len) |i| {
                    if (i > 0) utils.writeStr(" ");
                    list.items[i].print();
                }
                utils.writeStr(")");
            },
        }
    }
};

// Environment (symbol table)
const MAX_VARS = 32;
var var_names: [MAX_VARS][32]u8 = undefined;
var var_values: [MAX_VARS]LispValue = undefined;
var var_count: usize = 0;

fn setVar(name: []const u8, value: LispValue) void {
    // Check if variable exists
    for (0..var_count) |i| {
        const stored_name = utils.strFromBuf(&var_names[i]);
        if (utils.strEq(stored_name, name)) {
            var_values[i] = value;
            return;
        }
    }

    // Add new variable
    if (var_count < MAX_VARS) {
        utils.strCopy(&var_names[var_count], name);
        var_values[var_count] = value;
        var_count += 1;
    }
}

fn getVar(name: []const u8) ?LispValue {
    for (0..var_count) |i| {
        const stored_name = utils.strFromBuf(&var_names[i]);
        if (utils.strEq(stored_name, name)) {
            return var_values[i];
        }
    }
    return null;
}

// Parser
fn skipSpace(input: []const u8, pos: *usize) void {
    while (pos.* < input.len and (input[pos.*] == ' ' or input[pos.*] == '\t' or input[pos.*] == '\n')) {
        pos.* += 1;
    }
}

fn parseNumber(input: []const u8, pos: *usize) ?i32 {
    var num: i32 = 0;
    var found = false;

    while (pos.* < input.len and input[pos.*] >= '0' and input[pos.*] <= '9') {
        num = num * 10 + @as(i32, input[pos.*] - '0');
        pos.* += 1;
        found = true;
    }

    if (found) return num else return null;
}

fn parseSymbol(input: []const u8, pos: *usize) ?[]const u8 {
    const start = pos.*;
    while (pos.* < input.len and input[pos.*] != ' ' and input[pos.*] != '(' and input[pos.*] != ')' and input[pos.*] != '\n' and input[pos.*] != '"') {
        pos.* += 1;
    }
    if (start == pos.*) return null;
    return input[start..pos.*];
}

fn parse(input: []const u8, pos: *usize) ?LispValue {
    skipSpace(input, pos);
    if (pos.* >= input.len) return null;

    if (input[pos.*] == '"') {
        // Parse string literal
        pos.* += 1; // Skip opening quote
        const start = pos.*;
        while (pos.* < input.len and input[pos.*] != '"') {
            pos.* += 1;
        }
        if (pos.* >= input.len) return null; // Unclosed string
        const str = input[start..pos.*];
        pos.* += 1; // Skip closing quote

        // Process escape sequences and store string
        var actual_len: usize = 0;
        var i: usize = 0;
        while (i < str.len) : (i += 1) {
            if (str[i] == '\\' and i + 1 < str.len) {
                i += 1; // Skip backslash
            }
            actual_len += 1;
        }

        const str_copy = alloc(actual_len) orelse return null;
        var j: usize = 0;
        i = 0;
        while (i < str.len) : (i += 1) {
            if (str[i] == '\\' and i + 1 < str.len) {
                i += 1;
                str_copy[j] = switch (str[i]) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    else => str[i], // Unknown escape, keep as-is
                };
            } else {
                str_copy[j] = str[i];
            }
            j += 1;
        }
        return LispValue{ .Atom = Atom{ .String = str_copy[0..actual_len] } };
    } else if (input[pos.*] == '(') {
        // Parse list
        pos.* += 1; // Skip '('
        const list_ptr = @as(*List, @ptrCast(@alignCast(alloc(@sizeOf(List)) orelse return null)));
        list_ptr.len = 0;

        while (true) {
            skipSpace(input, pos);
            if (pos.* >= input.len) return null;
            if (input[pos.*] == ')') {
                pos.* += 1; // Skip ')'
                return LispValue{ .List = list_ptr };
            }

            if (list_ptr.len >= list_ptr.items.len) return null; // List full

            const elem = parse(input, pos) orelse return null;
            list_ptr.items[list_ptr.len] = elem;
            list_ptr.len += 1;
        }
    } else if (input[pos.*] >= '0' and input[pos.*] <= '9') {
        // Parse number
        if (parseNumber(input, pos)) |num| {
            return LispValue{ .Atom = Atom{ .Number = num } };
        }
    } else {
        // Parse symbol
        if (parseSymbol(input, pos)) |sym| {
            // Check for boolean literals
            if (utils.strEq(sym, "#t")) {
                return LispValue{ .Atom = Atom{ .Boolean = true } };
            } else if (utils.strEq(sym, "#f")) {
                return LispValue{ .Atom = Atom{ .Boolean = false } };
            }

            // Store symbol string
            const sym_copy = alloc(sym.len) orelse return null;
            for (sym, 0..) |ch, i| {
                sym_copy[i] = ch;
            }
            return LispValue{ .Atom = Atom{ .Symbol = sym_copy } };
        }
    }

    return null;
}

// Built-in operation types for better organization
const BuiltinOp = enum {
    And,
    Concat,
    Print,
    Define,
    If,
    Quote,
    Syscall,
    Unknown,

    fn fromSymbol(sym: []const u8) BuiltinOp {
        if (utils.strEq(sym, "and")) return .And;
        if (utils.strEq(sym, "concat")) return .Concat;
        if (utils.strEq(sym, "print")) return .Print;
        if (utils.strEq(sym, "define")) return .Define;
        if (utils.strEq(sym, "if")) return .If;
        if (utils.strEq(sym, "quote")) return .Quote;
        if (utils.strEq(sym, "syscall")) return .Syscall;
        return .Unknown;
    }
};

// Arithmetic operation types
const ArithOp = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Equal,
    LessEqual,
    Greater,
    Mod,
    Unknown,

    fn fromSymbol(sym: []const u8) ArithOp {
        if (sym.len == 1) {
            return switch (sym[0]) {
                '+' => .Add,
                '-' => .Subtract,
                '*' => .Multiply,
                '/' => .Divide,
                else => .Unknown,
            };
        }
        if (utils.strEq(sym, "=")) return .Equal;
        if (utils.strEq(sym, "<=")) return .LessEqual;
        if (utils.strEq(sym, ">")) return .Greater;
        if (utils.strEq(sym, "mod")) return .Mod;
        return .Unknown;
    }

    fn isVariadic(self: ArithOp) bool {
        return self == .Add or self == .Multiply;
    }
};

// Helper functions for operations
fn evalArithmetic(list: *List, op: ArithOp) ?LispValue {
    if (list.len < 2) return null;

    // Variadic operations
    if (op.isVariadic()) {
        if (list.len < 3) return null;
        return switch (op) {
            .Add => {
                var sum: i32 = 0;
                for (1..list.len) |i| {
                    const arg = eval(list.items[i]) orelse return null;
                    if (arg != .Atom or arg.Atom != .Number) return null;
                    sum += arg.Atom.Number;
                }
                return LispValue{ .Atom = Atom{ .Number = sum } };
            },
            .Multiply => {
                var prod: i32 = 1;
                for (1..list.len) |i| {
                    const arg = eval(list.items[i]) orelse return null;
                    if (arg != .Atom or arg.Atom != .Number) return null;
                    prod *= arg.Atom.Number;
                }
                return LispValue{ .Atom = Atom{ .Number = prod } };
            },
            else => null,
        };
    }

    // Binary operations
    if (list.len != 3) return null;
    const a = eval(list.items[1]) orelse return null;
    const b = eval(list.items[2]) orelse return null;
    if (a != .Atom or a.Atom != .Number or b != .Atom or b.Atom != .Number) return null;

    return switch (op) {
        .Subtract => LispValue{ .Atom = Atom{ .Number = a.Atom.Number - b.Atom.Number } },
        .Divide => if (b.Atom.Number == 0) null else LispValue{ .Atom = Atom{ .Number = @divFloor(a.Atom.Number, b.Atom.Number) } },
        .Equal => LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number == b.Atom.Number } },
        .LessEqual => LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number <= b.Atom.Number } },
        .Greater => LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number > b.Atom.Number } },
        .Mod => if (b.Atom.Number == 0) null else LispValue{ .Atom = Atom{ .Number = @mod(a.Atom.Number, b.Atom.Number) } },
        else => null,
    };
}

// Evaluator
// Syscall types
const SyscallType = enum {
    Write,
    Open,
    Close,
    Read,
    Unknown,

    fn fromString(name: []const u8) SyscallType {
        if (utils.strEq(name, "write")) return .Write;
        if (utils.strEq(name, "open")) return .Open;
        if (utils.strEq(name, "close")) return .Close;
        if (utils.strEq(name, "read")) return .Read;
        return .Unknown;
    }

    fn expectedArgCount(self: SyscallType) usize {
        return switch (self) {
            .Write => 4,  // (syscall "write" fd data)
            .Open => 5,   // (syscall "open" filename flags mode)
            .Close => 3,  // (syscall "close" fd)
            .Read => 5,   // (syscall "read" fd buffer size)
            .Unknown => 0,
        };
    }
};

// Syscall evaluation helper
fn evalSyscall(list: *List) ?LispValue {
    if (list.len < 2) return null;

    const name_val = eval(list.items[1]) orelse return null;
    if (name_val != .Atom or name_val.Atom != .String) return null;
    
    const syscall_type = SyscallType.fromString(name_val.Atom.String);
    if (syscall_type == .Unknown) return null;
    
    if (list.len != syscall_type.expectedArgCount()) return null;

    return switch (syscall_type) {
        .Write => syscallWrite(list),
        .Open => syscallOpen(list),
        .Close => syscallClose(list),
        .Read => syscallRead(list),
        .Unknown => null,
    };
}

// Helper to extract number argument
fn getNumberArg(list: *List, index: usize) ?i32 {
    if (index >= list.len) return null;
    const val = eval(list.items[index]) orelse return null;
    if (val != .Atom or val.Atom != .Number) return null;
    return val.Atom.Number;
}

// Helper to extract string argument
fn getStringArg(list: *List, index: usize) ?[]const u8 {
    if (index >= list.len) return null;
    const val = eval(list.items[index]) orelse return null;
    if (val != .Atom or val.Atom != .String) return null;
    return val.Atom.String;
}

fn syscallWrite(list: *List) ?LispValue {
    const fd = getNumberArg(list, 2) orelse return null;
    const data = getStringArg(list, 3) orelse return null;
    const result = sys.write(@intCast(fd), @ptrCast(data.ptr), data.len);
    return LispValue{ .Atom = Atom{ .Number = @intCast(result) } };
}

fn syscallOpen(list: *List) ?LispValue {
    const filename = getStringArg(list, 2) orelse return null;
    const flags = getNumberArg(list, 3) orelse return null;
    const mode = getNumberArg(list, 4) orelse return null;

    var path_buf: [256]u8 = undefined;
    if (filename.len >= path_buf.len) return null;
    @memcpy(path_buf[0..filename.len], filename);
    path_buf[filename.len] = 0;

    const result = sys.open(@ptrCast(&path_buf), @as(u32, @intCast(flags)), @as(u32, @intCast(mode)));
    return LispValue{ .Atom = Atom{ .Number = @intCast(result) } };
}

fn syscallClose(list: *List) ?LispValue {
    const fd = getNumberArg(list, 2) orelse return null;
    const result = sys.close(@intCast(fd));
    return LispValue{ .Atom = Atom{ .Number = @intCast(result) } };
}

fn syscallRead(list: *List) ?LispValue {
    const fd = getNumberArg(list, 2) orelse return null;
    const size = getNumberArg(list, 4) orelse return null;

    const buffer = alloc(@as(usize, @intCast(size))) orelse return null;
    const result = sys.read(@intCast(fd), @ptrCast(buffer.ptr), @as(usize, @intCast(size)));

    if (result > 0) {
        return LispValue{ .Atom = Atom{ .String = buffer[0..@intCast(result)] } };
    } else {
        return LispValue{ .Atom = Atom{ .Number = @intCast(result) } };
    }
}

// Individual evaluation functions for built-in operations
fn evalAnd(list: *List) ?LispValue {
    if (list.len != 3) return null;
    const a = eval(list.items[1]) orelse return null;
    const b = eval(list.items[2]) orelse return null;
    if (a != .Atom or a.Atom != .Boolean or b != .Atom or b.Atom != .Boolean) return null;
    return LispValue{ .Atom = Atom{ .Boolean = a.Atom.Boolean and b.Atom.Boolean } };
}

fn evalConcat(list: *List) ?LispValue {
    if (list.len < 2) return null;
    var total_len: usize = 0;

    // First pass: calculate total length
    for (1..list.len) |i| {
        const val = eval(list.items[i]) orelse return null;
        if (val != .Atom or val.Atom != .String) return null;
        total_len += val.Atom.String.len;
    }

    // Allocate result string
    const result = alloc(total_len) orelse return null;
    var pos: usize = 0;

    // Second pass: concatenate strings
    for (1..list.len) |i| {
        const val = eval(list.items[i]) orelse return null;
        const str = val.Atom.String;
        for (str) |ch| {
            result[pos] = ch;
            pos += 1;
        }
    }

    return LispValue{ .Atom = Atom{ .String = result[0..total_len] } };
}

fn evalPrint(list: *List) ?LispValue {
    if (list.len < 2) return null;
    for (1..list.len) |i| {
        if (i > 1) utils.writeStr(" ");
        const val = eval(list.items[i]) orelse return null;
        // For strings, print without quotes
        if (val == .Atom and val.Atom == .String) {
            utils.writeStr(val.Atom.String);
        } else {
            val.print();
        }
    }
    utils.writeStr("\n");
    return LispValue{ .Atom = Atom{ .Symbol = "ok" } };
}

fn evalDefine(list: *List) ?LispValue {
    if (list.len != 3) return null;
    if (list.items[1] != .Atom or list.items[1].Atom != .Symbol) return null;
    const name = list.items[1].Atom.Symbol;
    const val = eval(list.items[2]) orelse return null;
    setVar(name, val);
    return val;
}

fn evalIf(list: *List) ?LispValue {
    if (list.len != 4) return null;
    const cond = eval(list.items[1]) orelse return null;
    if (cond != .Atom or cond.Atom != .Boolean) return null;
    return if (cond.Atom.Boolean) eval(list.items[2]) else eval(list.items[3]);
}

fn evalQuote(list: *List) ?LispValue {
    if (list.len != 2) return null;
    return list.items[1];
}

// Evaluator
fn eval(value: LispValue) ?LispValue {
    switch (value) {
        .Atom => |atom| {
            switch (atom) {
                .Number, .Boolean, .String => return value,
                .Symbol => |name| {
                    return getVar(name);
                },
            }
        },
        .List => |list| {
            if (list.len == 0) return null;

            const first = list.items[0];
            if (first != .Atom or first.Atom != .Symbol) return null;

            const op = first.Atom.Symbol;

            // Try arithmetic operations first
            const arith_op = ArithOp.fromSymbol(op);
            if (arith_op != .Unknown) {
                return evalArithmetic(list, arith_op);
            }

            // Try other built-in operations
            const builtin = BuiltinOp.fromSymbol(op);
            return switch (builtin) {
                .And => evalAnd(list),
                .Concat => evalConcat(list),
                .Print => evalPrint(list),
                .Define => evalDefine(list),
                .If => evalIf(list),
                .Quote => evalQuote(list),
                .Syscall => evalSyscall(list),
                .Unknown => null,
            };
        },
    }
}

// Helper to execute Lisp code from a string
fn executeLisp(code: []const u8) void {
    // Reset allocator
    resetAlloc();

    // Parse and evaluate each expression
    var pos: usize = 0;
    var expr_count: usize = 0;
    while (pos < code.len) {
        skipSpace(code, &pos);
        if (pos >= code.len) break;
        expr_count += 1;

        if (parse(code, &pos)) |expr| {
            if (eval(expr)) |result_val| {
                result_val.print();
                utils.writeStr("\n");
            } else {
                utils.writeStr("Error: evaluation failed at position ");
                utils.writeStr(utils.intToStr(@intCast(pos)));
                utils.writeStr("\n");
                break;
            }
        } else {
            utils.writeStr("Error: parse failed at position ");
            utils.writeStr(utils.intToStr(@intCast(pos)));
            utils.writeStr(" of ");
            utils.writeStr(utils.intToStr(@intCast(code.len)));
            utils.writeStr("\n");
            break;
        }
    }
}

// Read file from SimpleFS
fn readFileFromSimpleFS(filename: []const u8, buffer: []u8) ?usize {
    // Open /dev/ramdisk for reading
    const path = "/dev/ramdisk";
    const fd = sys.open(@ptrCast(path.ptr), sys.abi.O_RDWR, 0);
    if (fd < 0) return null;
    defer _ = sys.close(@intCast(fd));

    // Try to read from SimpleFS
    var cmd_buffer: [256]u8 = undefined;
    var pos: usize = 0;

    // Command: Read file (0x02)
    cmd_buffer[pos] = 0x02;
    pos += 1;

    // Filename length and filename
    cmd_buffer[pos] = @intCast(filename.len);
    pos += 1;
    @memcpy(cmd_buffer[pos .. pos + filename.len], filename);
    pos += filename.len;

    // Send command to prepare file read
    const result = sys.write(@intCast(fd), @ptrCast(&cmd_buffer), pos);
    if (result < 0) return null;

    // Now read the actual file content
    const bytes_read = sys.read(@intCast(fd), @ptrCast(buffer.ptr), buffer.len);
    if (bytes_read > 0) {
        return @intCast(bytes_read);
    }

    return null;
}

// Main command entry point
pub fn main(args: *const utils.Args) void {
    // Check if a filename was provided
    if (args.argc > 1) {
        // Execute file mode
        const filename = args.argv[1];

        // Try to read from SimpleFS
        var file_buffer: [4096]u8 = undefined;
        if (readFileFromSimpleFS(filename, &file_buffer)) |size| {
            executeLisp(file_buffer[0..size]);
        } else {
            // Try reading as a regular file
            // Create null-terminated filename
            var filename_buf: [256]u8 = undefined;
            if (filename.len >= filename_buf.len) {
                utils.writeStr("Error: Filename too long\n");
                return;
            }
            @memcpy(filename_buf[0..filename.len], filename);
            filename_buf[filename.len] = 0;

            const fd = sys.open(@ptrCast(&filename_buf), sys.abi.O_RDONLY, 0);
            if (fd < 0) {
                utils.writeStr("Error: Cannot open file ");
                utils.writeStr(filename);
                utils.writeStr("\n");
                return;
            }
            const bytes_read = sys.read(@intCast(fd), @ptrCast(&file_buffer), file_buffer.len);
            _ = sys.close(@intCast(fd)); // Close immediately after reading

            if (bytes_read < 0) {
                utils.writeStr("Error: Cannot read file\n");
                return;
            }

            if (bytes_read > 0) {
                executeLisp(file_buffer[0..@intCast(bytes_read)]);
            }
        }
        return;
    }

    // REPL mode
    utils.writeStr("Minimal Lisp REPL for Claudia\n");
    utils.writeStr("Type 'quit' to exit\n\n");

    var input_buffer: [256]u8 = undefined;

    while (true) {
        utils.writeStr("> ");

        const result = utils.readLine(&input_buffer);
        if (result <= 0) break;

        const len = @as(usize, @intCast(result));

        // Remove newline
        var input_len = len;
        if (input_len > 0 and (input_buffer[input_len - 1] == '\n' or input_buffer[input_len - 1] == '\r')) {
            input_len -= 1;
        }

        if (input_len == 0) continue;

        // Check for quit
        const input = input_buffer[0..input_len];
        if (utils.strEq(input, "quit")) break;

        // Execute the expression
        executeLisp(input);
    }
}
