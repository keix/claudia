// kernel/fs/vfs.zig - Virtual File System layer
const std = @import("std");
const defs = @import("abi");

// VFS node types
pub const NodeType = enum(u8) {
    FILE = 1,
    DIRECTORY = 2,
    DEVICE = 3,
};

// VFS node structure
pub const VNode = struct {
    name: [256]u8 = undefined,
    name_len: usize = 0,
    node_type: NodeType,
    size: usize = 0,
    parent: ?*VNode = null,

    // For directories
    children: ?*VNode = null,
    next_sibling: ?*VNode = null,

    // For files - simple fixed-size buffer
    data: [1024]u8 = undefined,
    data_size: usize = 0,

    // Reference counting
    ref_count: usize = 0,

    pub fn init(node_type: NodeType, name: []const u8) VNode {
        var node = VNode{
            .node_type = node_type,
            .ref_count = 1,
        };

        // Copy name
        const copy_len = @min(name.len, node.name.len - 1);
        @memcpy(node.name[0..copy_len], name[0..copy_len]);
        node.name[copy_len] = 0;
        node.name_len = copy_len;

        return node;
    }

    pub fn getName(self: *const VNode) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn addChild(self: *VNode, child: *VNode) void {
        if (self.node_type != .DIRECTORY) return;

        child.parent = self;
        child.next_sibling = self.children;
        self.children = child;
    }

    pub fn findChild(self: *VNode, name: []const u8) ?*VNode {
        if (self.node_type != .DIRECTORY) return null;

        var current = self.children;
        while (current) |node| {
            if (std.mem.eql(u8, node.getName(), name)) {
                return node;
            }
            current = node.next_sibling;
        }
        return null;
    }

    pub fn getChildren(self: *VNode) ?*VNode {
        if (self.node_type != .DIRECTORY) return null;
        return self.children;
    }

    pub fn addRef(self: *VNode) void {
        self.ref_count += 1;
    }

    pub fn release(self: *VNode) void {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
        }
        // TODO: Free node when ref_count reaches 0
    }
};

// Simple path parser
pub const PathIterator = struct {
    path: []const u8,
    index: usize = 0,

    pub fn init(path: []const u8) PathIterator {
        return .{ .path = path };
    }

    pub fn next(self: *PathIterator) ?[]const u8 {
        // Skip leading slashes
        while (self.index < self.path.len and self.path[self.index] == '/') {
            self.index += 1;
        }

        if (self.index >= self.path.len) return null;

        const start = self.index;

        // Find next slash or end of path
        while (self.index < self.path.len and self.path[self.index] != '/') {
            self.index += 1;
        }

        return self.path[start..self.index];
    }
};

// Global VFS state
var root_node: VNode = undefined;
var dev_node: VNode = undefined;
var console_node: VNode = undefined;
var tty_node: VNode = undefined;
var null_node: VNode = undefined;
var ramdisk_node: VNode = undefined;
var initialized = false;

// Initialize VFS with basic structure
pub fn init() void {
    if (initialized) return;

    // Create root directory
    root_node = VNode.init(.DIRECTORY, "/");

    // Create /dev directory
    dev_node = VNode.init(.DIRECTORY, "dev");
    root_node.addChild(&dev_node);

    // Create /dev/console
    console_node = VNode.init(.DEVICE, "console");
    dev_node.addChild(&console_node);

    // Create /dev/tty
    tty_node = VNode.init(.DEVICE, "tty");
    dev_node.addChild(&tty_node);

    // Create /dev/null
    null_node = VNode.init(.DEVICE, "null");
    dev_node.addChild(&null_node);

    // Create /dev/ramdisk
    ramdisk_node = VNode.init(.DEVICE, "ramdisk");
    dev_node.addChild(&ramdisk_node);

    initialized = true;
}

// Resolve a path to a VNode
pub fn resolvePath(path: []const u8) ?*VNode {
    if (!initialized) init();

    // Handle root
    if (path.len == 0 or (path.len == 1 and path[0] == '/')) {
        return &root_node;
    }

    var iter = PathIterator.init(path);
    var current = &root_node;

    while (iter.next()) |component| {
        if (current.findChild(component)) |child| {
            current = child;
        } else {
            return null;
        }
    }

    return current;
}

// Debug: Print VFS tree for debugging
pub fn debugPrintTree() void {
    const uart = @import("../driver/uart/core.zig");
    uart.puts("\nVFS Tree:\n");
    debugPrintNodeWithUart(&root_node, 0);
}

fn debugPrintNodeWithUart(node: *VNode, depth: usize) void {
    const uart = @import("../driver/uart/core.zig");

    // Print indentation
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        uart.puts("  ");
    }

    // Print node info
    uart.puts(node.getName());
    uart.puts(" (");
    uart.puts(switch (node.node_type) {
        .FILE => "FILE",
        .DIRECTORY => "DIR",
        .DEVICE => "DEV",
    });
    uart.puts(")\n");

    // Print children
    if (node.node_type == .DIRECTORY) {
        var child = node.children;
        while (child) |c| {
            debugPrintNodeWithUart(c, depth + 1);
            child = c.next_sibling;
        }
    }
}

// Create a new directory node
pub fn createDirectory(parent_path: []const u8, name: []const u8) ?*VNode {
    const parent = resolvePath(parent_path) orelse return null;
    if (parent.node_type != .DIRECTORY) return null;

    // Check if directory already exists
    if (parent.findChild(name) != null) return null;

    // For now, we'll use a static allocation (not ideal, but simple)
    // In a real implementation, this would use a proper allocator
    const node_storage = struct {
        var nodes: [100]VNode = undefined;
        var next_idx: usize = 0;
    };

    if (node_storage.next_idx >= node_storage.nodes.len) return null;

    const new_node = &node_storage.nodes[node_storage.next_idx];
    node_storage.next_idx += 1;

    new_node.* = VNode.init(.DIRECTORY, name);
    parent.addChild(new_node);

    return new_node;
}

// Create a new file node (in memory only for now)
pub fn createFile(parent_path: []const u8, name: []const u8) ?*VNode {
    const parent = resolvePath(parent_path) orelse return null;
    if (parent.node_type != .DIRECTORY) return null;

    // Check if file already exists
    if (parent.findChild(name) != null) return null;

    // For now, we'll use a static allocation (not ideal, but simple)
    // In a real implementation, this would use a proper allocator
    const node_storage = struct {
        var nodes: [100]VNode = undefined;
        var next_idx: usize = 0;
    };

    if (node_storage.next_idx >= node_storage.nodes.len) return null;

    const new_node = &node_storage.nodes[node_storage.next_idx];
    node_storage.next_idx += 1;

    new_node.* = VNode.init(.FILE, name);
    parent.addChild(new_node);

    return new_node;
}

// Debug function to print VFS tree
pub fn debugPrint() void {
    if (!initialized) return;
    debugPrintNode(&root_node, 0);
}

fn debugPrintNode(node: *VNode, depth: usize) void {
    // Print indentation
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("  ", .{});
    }

    // Print node info
    std.debug.print("{s} ({s})\n", .{ node.getName(), @tagName(node.node_type) });

    // Print children
    if (node.node_type == .DIRECTORY) {
        var child = node.children;
        while (child) |c| {
            debugPrintNode(c, depth + 1);
            child = c.next_sibling;
        }
    }
}
