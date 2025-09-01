// Minimal Lisp interpreter for Claudia
const utils = @import("shell/utils");
const sys = @import("sys");

// Simple fixed-size allocator
var global_buffer: [32768]u8 = undefined;
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

// Align forward to the next boundary
inline fn alignForward(p: usize, a: usize) usize {
    const mask = a - 1;
    return (p + mask) & ~mask;
}

// Allocate with proper alignment
fn allocAligned(comptime T: type) ?*T {
    const a = @alignOf(T);
    const s = @sizeOf(T);
    const start = alignForward(global_pos, a);
    if (start + s > global_buffer.len) return null;
    const ptr = &global_buffer[start];
    global_pos = start + s;
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

// Atom types
const Atom = union(enum) {
    Number: i32,
    Symbol: []const u8,
    Boolean: bool,
    String: []const u8,
    Nil: void, // Explicit nil type
};

// Cons cell structure
const Cons = struct {
    car: LispValue,
    cdr: LispValue,
};

// List structure (for compatibility, will be phased out)
const List = struct {
    items: [32]LispValue, // Fixed size
    len: usize,
};

// Function structure
const Function = struct {
    params: *List, // Parameter names (list of symbols)
    body: LispValue, // Function body expression
};

// Lisp value
const LispValue = union(enum) {
    Atom: Atom,
    Cons: *Cons,
    List: *List,
    Function: *Function,

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
                    .Nil => utils.writeStr("nil"),
                }
            },
            .Cons => |cons_cell| {
                utils.writeStr("(");
                printConsCell(cons_cell);
                utils.writeStr(")");
            },
            .List => |list| {
                utils.writeStr("(");
                for (0..list.len) |i| {
                    if (i > 0) utils.writeStr(" ");
                    list.items[i].print();
                }
                utils.writeStr(")");
            },
            .Function => |_| {
                utils.writeStr("#<function>");
            },
        }
    }
};

// Helper function to print cons cells with proper formatting
fn printConsCell(cons_cell: *Cons) void {
    cons_cell.car.print();

    // Check cdr
    switch (cons_cell.cdr) {
        .Atom => |atom| {
            switch (atom) {
                .Nil => {}, // Don't print anything for nil terminator
                else => {
                    utils.writeStr(" . ");
                    cons_cell.cdr.print();
                },
            }
        },
        .Cons => |next| {
            utils.writeStr(" ");
            printConsCell(next);
        },
        else => {
            utils.writeStr(" . ");
            cons_cell.cdr.print();
        },
    }
}

// Cons cell operations
fn cons(car_val: LispValue, cdr_val: LispValue) ?LispValue {
    const cell = allocAligned(Cons) orelse return null;
    cell.car = car_val;
    cell.cdr = cdr_val;
    return LispValue{ .Cons = cell };
}

fn car(value: LispValue) ?LispValue {
    switch (value) {
        .Cons => |cell| return cell.car,
        .List => |list| {
            if (list.len == 0) return null;
            return list.items[0];
        },
        else => return null, // Error: not a list or cons cell
    }
}

fn cdr(value: LispValue) ?LispValue {
    switch (value) {
        .Cons => |cell| return cell.cdr,
        .List => |list| {
            if (list.len <= 1) return makeNil();
            // Create a new list with remaining elements
            const new_list = allocAligned(List) orelse return null;
            new_list.len = list.len - 1;
            for (1..list.len) |i| {
                new_list.items[i - 1] = list.items[i];
            }
            return LispValue{ .List = new_list };
        },
        else => return null, // Error: not a list or cons cell
    }
}

// Create a nil value
fn makeNil() LispValue {
    return LispValue{ .Atom = .{ .Nil = {} } };
}

// Convert cons cells to List for compatibility
fn consToList(cons_val: LispValue) ?*List {
    const list_ptr = allocAligned(List) orelse return null;
    list_ptr.len = 0;

    var current = cons_val;
    while (true) {
        switch (current) {
            .Cons => |cons_cell| {
                if (list_ptr.len >= list_ptr.items.len) return null; // List full
                list_ptr.items[list_ptr.len] = cons_cell.car;
                list_ptr.len += 1;
                current = cons_cell.cdr;
            },
            .Atom => |atom| {
                switch (atom) {
                    .Nil => return list_ptr, // Proper list termination
                    else => {
                        // Improper list (dotted pair)
                        if (list_ptr.len >= list_ptr.items.len) return null;
                        list_ptr.items[list_ptr.len] = current;
                        list_ptr.len += 1;
                        return list_ptr;
                    },
                }
            },
            else => return null,
        }
    }
}

// Environment (symbol table)
const MAX_VARS = 32;
var var_names: [MAX_VARS][32]u8 = undefined;
var var_values: [MAX_VARS]LispValue = undefined;
var var_count: usize = 0;

// Initialize var_names at startup
fn initVarNames() void {
    for (0..MAX_VARS) |i| {
        for (0..32) |j| {
            var_names[i][j] = 0;
        }
    }
}

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
    while (pos.* < input.len) {
        if (input[pos.*] == ' ' or input[pos.*] == '\t' or input[pos.*] == '\n' or input[pos.*] == '\r') {
            pos.* += 1;
        } else if (input[pos.*] == ';') {
            // Skip comment until end of line
            pos.* += 1;
            while (pos.* < input.len and input[pos.*] != '\n') {
                pos.* += 1;
            }
            // Skip the newline if present
            if (pos.* < input.len and input[pos.*] == '\n') {
                pos.* += 1;
            }
        } else {
            break;
        }
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

        const list_ptr = allocAligned(List) orelse return null;
        list_ptr.len = 0;

        while (true) {
            skipSpace(input, pos);
            if (pos.* >= input.len) return null;
            if (input[pos.*] == ')') {
                pos.* += 1; // Skip ')'
                return LispValue{ .List = list_ptr };
            }

            if (list_ptr.len >= list_ptr.items.len) return null; // List too long
            const item = parse(input, pos) orelse return null;
            list_ptr.items[list_ptr.len] = item;
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
            // Check for special literals
            if (utils.strEq(sym, "#t")) {
                return LispValue{ .Atom = Atom{ .Boolean = true } };
            } else if (utils.strEq(sym, "#f")) {
                return LispValue{ .Atom = Atom{ .Boolean = false } };
            } else if (utils.strEq(sym, "nil")) {
                return makeNil();
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
    While,
    Cond,
    Set,
    Load,
    Lambda,
    Defun,
    Cons,
    Car,
    Cdr,
    Unknown,

    fn fromSymbol(sym: []const u8) BuiltinOp {
        if (utils.strEq(sym, "and")) return .And;
        if (utils.strEq(sym, "concat")) return .Concat;
        if (utils.strEq(sym, "print")) return .Print;
        if (utils.strEq(sym, "define")) return .Define;
        if (utils.strEq(sym, "if")) return .If;
        if (utils.strEq(sym, "quote")) return .Quote;
        if (utils.strEq(sym, "syscall")) return .Syscall;
        if (utils.strEq(sym, "while")) return .While;
        if (utils.strEq(sym, "cond")) return .Cond;
        if (utils.strEq(sym, "set")) return .Set;
        if (utils.strEq(sym, "load")) return .Load;
        if (utils.strEq(sym, "lambda")) return .Lambda;
        if (utils.strEq(sym, "defun")) return .Defun;
        if (utils.strEq(sym, "cons")) return .Cons;
        if (utils.strEq(sym, "car")) return .Car;
        if (utils.strEq(sym, "cdr")) return .Cdr;
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
                '=' => .Equal,
                '>' => .Greater,
                else => .Unknown,
            };
        }
        if (utils.strEq(sym, "<=")) return .LessEqual;
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
            .Write => 4, // (syscall "write" fd data)
            .Open => 5, // (syscall "open" filename flags mode)
            .Close => 3, // (syscall "close" fd)
            .Read => 5, // (syscall "read" fd buffer size)
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

fn evalWhile(list: *List) ?LispValue {
    if (list.len < 3) return null;

    // (while condition body...)
    var last_result: ?LispValue = null;
    while (true) {
        const cond = eval(list.items[1]) orelse return null;
        if (cond != .Atom or cond.Atom != .Boolean) return null;
        if (!cond.Atom.Boolean) break;

        // Execute body
        for (2..list.len) |i| {
            last_result = eval(list.items[i]);
        }
    }

    return last_result orelse LispValue{ .Atom = Atom{ .Symbol = "nil" } };
}

fn evalCond(list: *List) ?LispValue {
    if (list.len < 2) return null;

    // (cond (test1 expr1...) (test2 expr2...) ...)
    for (1..list.len) |i| {
        const clause = list.items[i];
        if (clause != .List or clause.List.len < 2) return null;

        const test_val = eval(clause.List.items[0]) orelse return null;

        // Check if test is true
        const is_true = switch (test_val) {
            .Atom => |atom| switch (atom) {
                .Boolean => atom.Boolean,
                .Symbol => utils.strEq(atom.Symbol, "#t"),
                else => false,
            },
            else => false,
        };

        if (is_true) {
            // Execute the expressions in this clause
            var result: ?LispValue = null;
            for (1..clause.List.len) |j| {
                result = eval(clause.List.items[j]);
            }
            return result;
        }
    }

    return LispValue{ .Atom = Atom{ .Symbol = "nil" } };
}

fn evalSet(list: *List) ?LispValue {
    if (list.len != 3) return null;
    if (list.items[1] != .Atom or list.items[1].Atom != .Symbol) return null;

    const name = list.items[1].Atom.Symbol;
    const value = eval(list.items[2]) orelse return null;

    // Check if variable exists
    if (getVar(name) == null) return null;

    setVar(name, value);
    return value;
}

fn evalLoad(list: *List) ?LispValue {
    if (list.len != 2) return null;

    // Get filename argument
    const filename_val = eval(list.items[1]) orelse return null;
    if (filename_val != .Atom or filename_val.Atom != .String) return null;
    const filename = filename_val.Atom.String;

    // Save filename in a local buffer since it might be in the allocator
    var filename_copy: [256]u8 = undefined;
    if (filename.len >= filename_copy.len) return null;
    @memcpy(filename_copy[0..filename.len], filename);
    const saved_filename = filename_copy[0..filename.len];

    // Try to read from SimpleFS first
    var file_buffer: [4096]u8 = undefined;
    var size: ?usize = null;

    // Try SimpleFS
    size = readFileFromSimpleFS(saved_filename, &file_buffer);

    if (size == null) {
        // Try regular file system
        var filename_buf: [256]u8 = undefined;
        if (saved_filename.len >= filename_buf.len) {
            return null;
        }
        @memcpy(filename_buf[0..saved_filename.len], saved_filename);
        filename_buf[saved_filename.len] = 0;

        const fd = sys.open(@ptrCast(&filename_buf), sys.abi.O_RDONLY, 0);
        if (fd < 0) {
            return null;
        }
        defer _ = sys.close(@intCast(fd));

        const bytes_read = sys.read(@intCast(fd), @ptrCast(&file_buffer), file_buffer.len);
        if (bytes_read > 0) {
            size = @intCast(bytes_read);
        }
    }

    if (size) |actual_size| {
        // Don't save/restore allocator position - let it grow
        // This allows multiple file loads to work

        // Parse and evaluate the loaded code
        var pos: usize = 0;
        var last_result: ?LispValue = null;

        while (pos < actual_size) {
            skipSpace(file_buffer[0..actual_size], &pos);
            if (pos >= actual_size) break;

            if (parse(file_buffer[0..actual_size], &pos)) |expr| {
                last_result = eval(expr);
                if (last_result == null) {
                    // Don't restore allocator - continue with other definitions
                    return null;
                }
            } else {
                // Parse error - but don't restore allocator
                return null;
            }
        }

        // Return last evaluated expression or symbol indicating success
        return last_result orelse LispValue{ .Atom = Atom{ .Symbol = "ok" } };
    }

    return null;
}

fn evalLambda(list: *List) ?LispValue {
    if (list.len != 3) return null;

    // (lambda (params...) body)
    const params = list.items[1];
    if (params != .List) return null;

    // Validate all parameters are symbols
    for (0..params.List.len) |i| {
        if (params.List.items[i] != .Atom or params.List.items[i].Atom != .Symbol) {
            return null;
        }
    }

    // Create function
    const func_ptr = allocAligned(Function) orelse return null;
    func_ptr.params = params.List;
    func_ptr.body = list.items[2];

    return LispValue{ .Function = func_ptr };
}

fn evalDefun(list: *List) ?LispValue {
    if (list.len != 4) return null;

    // (defun name (params...) body)
    if (list.items[1] != .Atom or list.items[1].Atom != .Symbol) return null;
    const name = list.items[1].Atom.Symbol;

    const params = list.items[2];
    if (params != .List) return null;

    // Validate all parameters are symbols
    for (0..params.List.len) |i| {
        if (params.List.items[i] != .Atom or params.List.items[i].Atom != .Symbol) {
            return null;
        }
    }

    // Create function
    const func_ptr = allocAligned(Function) orelse return null;
    func_ptr.params = params.List;
    func_ptr.body = list.items[3];

    const func_val = LispValue{ .Function = func_ptr };
    setVar(name, func_val);

    return func_val;
}

// Cons operations
fn evalCons(list: *List) ?LispValue {
    if (list.len != 3) return null;

    const car_val = eval(list.items[1]) orelse return null;
    const cdr_val = eval(list.items[2]) orelse return null;

    return cons(car_val, cdr_val);
}

fn evalCar(list: *List) ?LispValue {
    if (list.len != 2) return null;

    const val = eval(list.items[1]) orelse return null;
    return car(val);
}

fn evalCdr(list: *List) ?LispValue {
    if (list.len != 2) return null;

    const val = eval(list.items[1]) orelse return null;
    return cdr(val);
}

// Apply a function with arguments
fn applyFunction(func: *Function, args: []LispValue) ?LispValue {
    // Check argument count
    if (args.len != func.params.len) return null;

    // Save current variable state
    const saved_count = var_count;
    var saved_values: [MAX_VARS]LispValue = undefined;
    for (0..saved_count) |i| {
        saved_values[i] = var_values[i];
    }

    // Bind parameters
    for (0..func.params.len) |i| {
        // Check parameter is a symbol
        if (func.params.items[i] != .Atom or func.params.items[i].Atom != .Symbol) {
            // Restore on error
            var_count = saved_count;
            for (0..saved_count) |j| {
                var_values[j] = saved_values[j];
            }
            return null;
        }

        const param_name = func.params.items[i].Atom.Symbol;
        const arg_val = eval(args[i]) orelse {
            // Restore on error
            var_count = saved_count;
            for (0..saved_count) |j| {
                var_values[j] = saved_values[j];
            }
            return null;
        };
        setVar(param_name, arg_val);
    }

    // Evaluate function body
    const result = eval(func.body);

    // Restore variable state
    var_count = saved_count;
    for (0..saved_count) |i| {
        var_values[i] = saved_values[i];
    }

    return result;
}

// Evaluator
fn eval(value: LispValue) ?LispValue {
    switch (value) {
        .Atom => |atom| {
            switch (atom) {
                .Number, .Boolean, .String, .Nil => return value,
                .Symbol => |name| {
                    return getVar(name);
                },
            }
        },
        .List => |list| {
            if (list.len == 0) return null;

            const first = list.items[0];

            // Check if first element is a symbol (for built-in ops and function names)
            if (first == .Atom and first.Atom == .Symbol) {
                const op = first.Atom.Symbol;

                // Try arithmetic operations first
                const arith_op = ArithOp.fromSymbol(op);
                if (arith_op != .Unknown) {
                    return evalArithmetic(list, arith_op);
                }

                // Try other built-in operations
                const builtin = BuiltinOp.fromSymbol(op);
                if (builtin != .Unknown) {
                    return switch (builtin) {
                        .And => evalAnd(list),
                        .Concat => evalConcat(list),
                        .Print => evalPrint(list),
                        .Define => evalDefine(list),
                        .If => evalIf(list),
                        .Quote => evalQuote(list),
                        .Syscall => evalSyscall(list),
                        .While => evalWhile(list),
                        .Cond => evalCond(list),
                        .Set => evalSet(list),
                        .Load => evalLoad(list),
                        .Lambda => evalLambda(list),
                        .Defun => evalDefun(list),
                        .Cons => evalCons(list),
                        .Car => evalCar(list),
                        .Cdr => evalCdr(list),
                        .Unknown => unreachable,
                    };
                }

                // Try function application - lookup symbol as a function
                if (getVar(op)) |func_val| {
                    if (func_val == .Function) {
                        // Collect arguments (skip function name)
                        var args: [32]LispValue = undefined;
                        const arg_count = list.len - 1;
                        if (arg_count > args.len) return null;

                        for (1..list.len) |i| {
                            args[i - 1] = list.items[i];
                        }

                        return applyFunction(func_val.Function, args[0..arg_count]);
                    }
                }

                return null;
            }

            // First element is not a symbol - try to evaluate it to a function
            const func_val = eval(first) orelse return null;
            if (func_val == .Function) {
                // Collect arguments
                var args: [32]LispValue = undefined;
                const arg_count = list.len - 1;
                if (arg_count > args.len) return null;

                for (1..list.len) |i| {
                    args[i - 1] = list.items[i];
                }

                return applyFunction(func_val.Function, args[0..arg_count]);
            }

            return null;
        },
        .Function => |_| {
            // Functions evaluate to themselves
            return value;
        },
        .Cons => {
            // Convert cons to list for evaluation
            const list = consToList(value) orelse return null;
            if (list.len == 0) return makeNil();

            const first = list.items[0];

            // Check if first element is a symbol (for built-in ops and function names)
            if (first == .Atom and first.Atom == .Symbol) {
                const op = first.Atom.Symbol;

                // Try arithmetic operations first
                const arith_op = ArithOp.fromSymbol(op);
                if (arith_op != .Unknown) {
                    return evalArithmetic(list, arith_op);
                }

                // Try other built-in operations
                const builtin = BuiltinOp.fromSymbol(op);
                if (builtin != .Unknown) {
                    return switch (builtin) {
                        .And => evalAnd(list),
                        .Concat => evalConcat(list),
                        .Print => evalPrint(list),
                        .Define => evalDefine(list),
                        .If => evalIf(list),
                        .Quote => evalQuote(list),
                        .Syscall => evalSyscall(list),
                        .While => evalWhile(list),
                        .Cond => evalCond(list),
                        .Set => evalSet(list),
                        .Load => evalLoad(list),
                        .Lambda => evalLambda(list),
                        .Defun => evalDefun(list),
                        .Cons => evalCons(list),
                        .Car => evalCar(list),
                        .Cdr => evalCdr(list),
                        .Unknown => unreachable,
                    };
                }

                // Try function application - lookup symbol as a function
                if (getVar(op)) |func_val| {
                    if (func_val == .Function) {
                        // Collect arguments (skip function name)
                        var args: [32]LispValue = undefined;
                        const arg_count = list.len - 1;
                        if (arg_count > args.len) return null;

                        for (1..list.len) |i| {
                            args[i - 1] = list.items[i];
                        }

                        return applyFunction(func_val.Function, args[0..arg_count]);
                    }
                }

                return null;
            }

            // First element is not a symbol - try to evaluate it to a function
            const func_val = eval(first) orelse return null;
            if (func_val == .Function) {
                // Collect arguments
                var args: [32]LispValue = undefined;
                const arg_count = list.len - 1;
                if (arg_count > args.len) return null;

                for (1..list.len) |i| {
                    args[i - 1] = list.items[i];
                }

                return applyFunction(func_val.Function, args[0..arg_count]);
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
            if (pos < code.len) {
                utils.writeStr(" (near '");
                // Show up to 10 characters from error position
                var end = pos + 10;
                if (end > code.len) end = code.len;
                utils.writeStr(code[pos..end]);
                utils.writeStr("')\n");
            } else {
                utils.writeStr("\n");
            }
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
    // Initialize variable name storage
    initVarNames();

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
