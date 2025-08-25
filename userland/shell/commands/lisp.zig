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

    if (input[pos.*] == '(') {
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

// Evaluator
fn eval(value: LispValue) ?LispValue {
    switch (value) {
        .Atom => |atom| {
            switch (atom) {
                .Number, .Boolean => return value,
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

            // Built-in operations
            if (utils.strEq(op, "+")) {
                if (list.len < 3) return null;
                var sum: i32 = 0;
                for (1..list.len) |i| {
                    const arg = eval(list.items[i]) orelse return null;
                    if (arg != .Atom or arg.Atom != .Number) return null;
                    sum += arg.Atom.Number;
                }
                return LispValue{ .Atom = Atom{ .Number = sum } };
            } else if (utils.strEq(op, "-")) {
                if (list.len != 3) return null;
                const a = eval(list.items[1]) orelse return null;
                const b = eval(list.items[2]) orelse return null;
                if (a != .Atom or a.Atom != .Number or b != .Atom or b.Atom != .Number) return null;
                return LispValue{ .Atom = Atom{ .Number = a.Atom.Number - b.Atom.Number } };
            } else if (utils.strEq(op, "*")) {
                if (list.len < 3) return null;
                var prod: i32 = 1;
                for (1..list.len) |i| {
                    const arg = eval(list.items[i]) orelse return null;
                    if (arg != .Atom or arg.Atom != .Number) return null;
                    prod *= arg.Atom.Number;
                }
                return LispValue{ .Atom = Atom{ .Number = prod } };
            } else if (utils.strEq(op, "=")) {
                if (list.len != 3) return null;
                const a = eval(list.items[1]) orelse return null;
                const b = eval(list.items[2]) orelse return null;
                if (a != .Atom or a.Atom != .Number or b != .Atom or b.Atom != .Number) return null;
                return LispValue{ .Atom = Atom{ .Boolean = a.Atom.Number == b.Atom.Number } };
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
                if (cond.Atom.Boolean) {
                    return eval(list.items[2]);
                } else {
                    return eval(list.items[3]);
                }
            } else if (utils.strEq(op, "quote")) {
                if (list.len != 2) return null;
                return list.items[1];
            }

            return null;
        },
    }
}

// Main command entry point
pub fn main(args: *const utils.Args) void {
    _ = args;

    utils.writeStr("Minimal Lisp REPL for Claudia\n");
    utils.writeStr("Commands: +, -, *, =, define, if, quote\n");
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

        // Reset allocator for each expression
        resetAlloc();

        // Parse and evaluate
        var pos: usize = 0;
        if (parse(input, &pos)) |expr| {
            if (eval(expr)) |result_val| {
                result_val.print();
                utils.writeStr("\n");
            } else {
                utils.writeStr("Error: evaluation failed\n");
            }
        } else {
            utils.writeStr("Error: parse failed\n");
        }
    }
}
