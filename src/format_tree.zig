pub fn formatTree(gpa: Allocator, arena: Allocator, nodes: HashMap(*Graph.Node)) !json.Value {
    var tree = json.ObjectMap.init(arena);
    for (nodes.values()) |node| {
        var sub_tree = json.ObjectMap.init(arena);
        try buildSubTree(arena, &sub_tree, node.dependencies.depends_on.items);
        try tree.put(node.id, .{ .object = sub_tree });
    }

    var depths = HashMap(usize){};
    defer depths.deinit(gpa);
    try computeBranchDepths(gpa, tree, &depths, 0);
    try pruneDependencyTree(gpa, &tree, depths, 0);

    return .{ .object = tree };
}

fn buildSubTree(arena: Allocator, tree: *json.ObjectMap, depends_on: []*Graph.Node) Allocator.Error!void {
    for (depends_on) |node| {
        var sub_tree = json.ObjectMap.init(arena);
        try buildSubTree(arena, &sub_tree, node.dependencies.depends_on.items);
        try tree.put(node.id, .{ .object = sub_tree });
    }
}

fn computeBranchDepths(
    gpa: Allocator,
    tree: json.ObjectMap,
    depths: *HashMap(usize),
    depth: usize,
) Allocator.Error!void {
    var iter = tree.iterator();
    while (iter.next()) |entry| {
        if (depth > (depths.get(entry.key_ptr.*) orelse 0)) {
            try depths.put(gpa, entry.key_ptr.*, depth);
        }
        try computeBranchDepths(gpa, entry.value_ptr.object, depths, depth + 1);
    }
}

fn pruneDependencyTree(
    gpa: Allocator,
    tree: *json.ObjectMap,
    depths: HashMap(usize),
    depth: usize,
) Allocator.Error!void {
    var to_remove = ArrayList([]const u8){};
    defer to_remove.deinit(gpa);

    var iter = tree.iterator();
    while (iter.next()) |entry| {
        if (depth != (depths.get(entry.key_ptr.*) orelse 0)) {
            try to_remove.append(gpa, entry.key_ptr.*);
        }
    }

    for (to_remove.items) |key| {
        assert(tree.orderedRemove(key));
    }

    var prune_iter = tree.iterator();
    while (prune_iter.next()) |entry| {
        try pruneDependencyTree(gpa, &entry.value_ptr.object, depths, depth + 1);
    }
}

const Golden = struct {
    cwd: []const u8 = ".",
    task_names: []const []const u8,
    expected_tree: json.Value,
};

test "formatTree(): should return the dependency tree" {
    const gpa = testing.allocator;

    const cwd = try process.getCwdAlloc(gpa);
    defer gpa.free(cwd);

    const file = try fs.cwd().openFile("testdata/tree/golden.json", .{});
    defer file.close();

    var reader = file.reader(&.{});
    const contents = try reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(contents);

    const golden = try json.parseFromSlice(Golden, gpa, contents, .{ .allocate = .alloc_always });
    defer golden.deinit();

    var dir = try fs.cwd().openDir("testdata/tree", .{});
    defer dir.close();

    var sub_dir = try dir.openDir(golden.value.cwd, .{});
    defer sub_dir.close();

    const sub_path = try fs.path.resolve(gpa, &.{
        cwd, "testdata/tree", golden.value.cwd,
    });
    defer gpa.free(sub_path);

    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var parser = Config.Parser.init(gpa, &diag, sub_dir);
    defer parser.deinit();

    var walker = TreeWalker.init(gpa, &parser, sub_path);
    defer walker.deinit();

    var graph = Graph.init(gpa, &diag, &walker, sub_dir, sub_path);
    defer graph.deinit();

    try graph.populate(&.{"."}, golden.value.task_names, &.{});

    var arena = ArenaAllocator.init(gpa);
    defer arena.deinit();
    const tree = try formatTree(gpa, arena.allocator(), graph.nodes);

    try expectEqualTrees(golden.value.expected_tree.object, tree.object);
}

fn expectEqualTrees(expected_tree: json.ObjectMap, actual_tree: json.ObjectMap) !void {
    try testing.expectEqual(expected_tree.count(), actual_tree.count());
    var iter = expected_tree.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const expected_value = entry.value_ptr.object;
        const actual_value = actual_tree.get(key).?.object;
        try expectEqualTrees(expected_value, actual_value);
    }
}

const Config = @import("Config.zig");
const Diagnostic = @import("Diagnostic.zig");
const Graph = @import("Graph.zig");
const TreeWalker = @import("TreeWalker.zig");
const std = @import("std");
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const HashMap = std.StringArrayHashMapUnmanaged;
const assert = std.debug.assert;
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;
const process = std.process;
const testing = std.testing;
