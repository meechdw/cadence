pub const Command = enum {
    run,
    tree,
};

pub fn run(
    gpa: Allocator,
    diag: *Diagnostic,
    logger: Logger,
    cwd: Dir,
    cwd_path: []const u8,
    cmd: Command,
    task_names: []const []const u8,
    params: []const []const u8,
) !void {
    var parser = Config.Parser.init(gpa, diag, cwd);
    defer parser.deinit();

    var walker = TreeWalker.init(gpa, &parser, cwd_path);
    defer walker.deinit();

    var graph = Graph.init(gpa, diag, &walker, cwd, cwd_path);
    defer graph.deinit();

    var arena = ArenaAllocator.init(gpa);
    defer arena.deinit();
    const workspace = try getWorkspace(arena.allocator(), diag, &parser, cwd);

    try graph.populate(workspace, task_names, params);

    if (cmd == .tree) {
        const tree = try formatTree(gpa, arena.allocator(), graph.nodes);
        return logger.stdout.print("{f}\n", .{json.fmt(tree, .{ .whitespace = .indent_2 })});
    }

    return diag.report(null, "not implemented", .{});
}

fn getWorkspace(arena: Allocator, diag: *Diagnostic, parser: *Config.Parser, cwd: Dir) ![]const []const u8 {
    var workspace = ArrayList([]const u8){};

    if (try fsx.exists(cwd, Config.filename)) {
        const config = try parser.getOrParse(".");
        if (config.workspace) |sub_paths| {
            for (sub_paths) |sub_path| {
                var dir = cwd.openDir(sub_path, .{}) catch |err| {
                    return diag.report(err, "failed to resolve workspace directory '{s}'", .{sub_path});
                };
                dir.close();
                try workspace.append(arena, sub_path);
            }
        }
    }

    if (workspace.items.len == 0) {
        try workspace.append(arena, ".");
    }

    return workspace.toOwnedSlice(arena);
}

const Config = @import("Config.zig");
const Diagnostic = @import("Diagnostic.zig");
const Graph = @import("Graph.zig");
const fsx = @import("fsx.zig");
const Logger = @import("Logger.zig");
const TreeWalker = @import("TreeWalker.zig");
const formatTree = @import("format_tree.zig").formatTree;
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const fs = std.fs;
const Dir = fs.Dir;
const json = std.json;
