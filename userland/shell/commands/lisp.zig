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
    while (pos.* < input.len and input[pos.*] != ' ' and input[pos.*] != '(' and input[pos.*] != ')' and input[pos.*] != '\n') {
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
        
        // Store string
        const str_copy = alloc(str.len) orelse return null;
        for (str, 0..) |ch, i| {
            str_copy[i] = ch;
        }
        return LispValue{ .Atom = Atom{ .String = str_copy } };
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

// Helper functions for operations
fn evalArithmetic(list: *List, op: u8) ?LispValue {
    if (list.len < 3) return null;
    
    if (op == '+') {
        var sum: i32 = 0;
        for (1..list.len) |i| {
            const arg = eval(list.items[i]) orelse return null;
            if (arg != .Atom or arg.Atom != .Number) return null;
            sum += arg.Atom.Number;
        }
        return LispValue{ .Atom = Atom{ .Number = sum } };
    } else if (op == '*') {
        var prod: i32 = 1;
        for (1..list.len) |i| {
            const arg = eval(list.items[i]) orelse return null;
            if (arg != .Atom or arg.Atom != .Number) return null;
            prod *= arg.Atom.Number;
        }
        return LispValue{ .Atom = Atom{ .Number = prod } };
    }
    
    // Binary operations
    if (list.len != 3) return null;
    const a = eval(list.items[1]) orelse return null;
    const b = eval(list.items[2]) orelse return null;
    if (a != .Atom or a.Atom != .Number or b != .Atom or b.Atom != .Number) return null;
    
    return switch (op) {
        '-' => LispValue{ .Atom = Atom{ .Number = a.Atom.Number - b.Atom.Number } },
        '/' => blk: {
            if (b.Atom.Number == 0) break :blk null;
            break :blk LispValue{ .Atom = Atom{ .Number = @divFloor(a.Atom.Number, b.Atom.Number) } };
        },
        '=' => LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number == b.Atom.Number } },
        '<' => LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number <= b.Atom.Number } },
        '>' => LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number > b.Atom.Number } },
        else => null,
    };
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

            // Arithmetic operations
            if (op.len == 1) {
                const ch = op[0];
                if (ch == '+' or ch == '-' or ch == '*') {
                    return evalArithmetic(list, ch);
                }
            } else if (utils.strEq(op, "=")) {
                return evalArithmetic(list, '=');
            } else if (utils.strEq(op, "<=")) {
                return evalArithmetic(list, '<');
            } else if (utils.strEq(op, "mod")) {
                if (list.len != 3) return null;
                const a = eval(list.items[1]) orelse return null;
                const b = eval(list.items[2]) orelse return null;
                if (a != .Atom or a.Atom != .Number or b != .Atom or b.Atom != .Number) return null;
                if (b.Atom.Number == 0) return null;
                return LispValue{ .Atom = Atom{ .Number = @mod(a.Atom.Number, b.Atom.Number) } };
            } else if (utils.strEq(op, "and")) {
                if (list.len != 3) return null;
                const a = eval(list.items[1]) orelse return null;
                const b = eval(list.items[2]) orelse return null;
                if (a != .Atom or a.Atom != .Boolean or b != .Atom or b.Atom != .Boolean) return null;
                return LispValue{ .Atom = Atom{ .Boolean = a.Atom.Boolean and b.Atom.Boolean } };
            } else if (utils.strEq(op, "concat")) {
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
            } else if (utils.strEq(op, "print")) {
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
            } else if (utils.strEq(op, "define")) {
                if (list.len != 3) return null;
                if (list.items[1] != .Atom or list.items[1].Atom != .Symbol) return null;
                const name = list.items[1].Atom.Symbol;
                const val = eval(list.items[2]) orelse return null;
                setVar(name, val);
                return val;
            } else if (utils.strEq(op, "if")) {
                if (list.len != 4) return null;
                const cond = eval(list.items[1]) orelse return null;
                if (cond != .Atom or cond.Atom != .Boolean) return null;
                return if (cond.Atom.Boolean) eval(list.items[2]) else eval(list.items[3]);
            } else if (utils.strEq(op, "quote")) {
                if (list.len != 2) return null;
                return list.items[1];
            }

            return null;
        },
    }
}

// Helper to execute Lisp code from a string
fn executeLisp(code: []const u8) void {
    // Reset allocator
    resetAlloc();

    // Parse and evaluate each expression
    var pos: usize = 0;
    while (pos < code.len) {
        skipSpace(code, &pos);
        if (pos >= code.len) break;

        if (parse(code, &pos)) |expr| {
            if (eval(expr)) |result_val| {
                result_val.print();
                utils.writeStr("\n");
            } else {
                utils.writeStr("Error: evaluation failed\n");
                break;
            }
        } else {
            utils.writeStr("Error: parse failed\n");
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
    @memcpy(cmd_buffer[pos..pos + filename.len], filename);
    pos += filename.len;

    // Send command to prepare file read
    const result = sys.write(@intCast(fd), @ptrCast(&cmd_buffer), pos);
    if (result < 0) return null;

    // Now read the actual file content
    const bytes_read = sys.read(@intCast(fd), buffer.ptr, buffer.len);
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
        utils.writeStr("Executing Lisp file: ");
        utils.writeStr(filename);
        utils.writeStr("\n");

        // Try to read from SimpleFS
        var file_buffer: [4096]u8 = undefined;
        if (readFileFromSimpleFS(filename, &file_buffer)) |size| {
            executeLisp(file_buffer[0..size]);
        } else {
            // Try reading as a regular file
            const fd = sys.open(@ptrCast(filename.ptr), sys.abi.O_RDONLY, 0);
            if (fd < 0) {
                utils.writeStr("Error: Cannot open file ");
                utils.writeStr(filename);
                utils.writeStr("\n");
                return;
            }
            defer _ = sys.close(@intCast(fd));

            const bytes_read = sys.read(@intCast(fd), &file_buffer, file_buffer.len);
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
    utils.writeStr("Commands: +, -, *, =, <=, mod, and, print, concat, define, if, quote\n");
    utils.writeStr("Strings: (print \"Hello, World!\")\n");
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
