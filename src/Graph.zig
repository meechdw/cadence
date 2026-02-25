const Graph = @This();

gpa: Allocator,
arena: ArenaAllocator,
diag: *Diagnostic,
walker: *TreeWalker,
cwd: Dir,
cwd_path: []const u8,
shell: Shell = Shell.default,
nodes: HashMap(*Node) = .{},

const workspace_dependency_prefix = "#";

pub fn init(gpa: Allocator, diag: *Diagnostic, walker: *TreeWalker, cwd: Dir, cwd_path: []const u8) Graph {
    return .{
        .gpa = gpa,
        .arena = ArenaAllocator.init(gpa),
        .diag = diag,
        .walker = walker,
        .cwd = cwd,
        .cwd_path = cwd_path,
    };
}

pub fn deinit(self: *Graph) void {
    for (self.nodes.values()) |node| {
        node.deinit(self.gpa);
    }
    self.nodes.deinit(self.gpa);
    self.arena.deinit();
}

pub fn populate(
    self: *Graph,
    workspace: []const []const u8,
    task_names: []const []const u8,
    params: []const []const u8,
) !void {
    assert(task_names.len != 0);
    assert(task_names.len >= params.len);

    for (workspace) |sub_path| {
        var stack = try self.walker.walk(sub_path);
        if (stack.configs.len != 0) {
            self.shell = stack.configs[0].shell;
        }

        // We must resolve aliases before the main processing loop because the config files
        // are processed in reverse order of discovery. Otherwise, aliases defined in config
        // files at the bottom of the stack will be missed.
        var aliases = try self.mergeAliases(&stack);
        defer aliases.deinit(self.gpa);
        stack.reset();

        var arena = ArenaAllocator.init(self.gpa);
        defer arena.deinit();

        var parsed_params = HashMap(HashMap([]const u8)){};
        for (params, 0..) |param, i| {
            const real_task_name = realTaskName(aliases, task_names[i]);
            const task_params = try parseParams(arena.allocator(), self.diag, param);
            try parsed_params.putNoClobber(arena.allocator(), real_task_name, task_params);
        }

        for (task_names) |name| {
            const real_task_name = realTaskName(aliases, name);
            try self.populateNode(&stack, parsed_params, sub_path, real_task_name, null);
        }
    }

    if (self.nodes.count() == 0) {
        return self.diag.report(null, "no tasks were found to be executed", .{});
    }
}

/// There is an open issue (https://github.com/ziglang/zig/issues/2971) to support
/// inferred error sets in recursion. Until that issue is closed, we must explicitly
/// provide the complete error set.
const PopulateNodeError = error{
    OutOfMemory,
    SystemResources,
    AccessDenied,
    ProcessNotFound,
    Unexpected,
    PermissionDenied,
    FileNotFound,
    NoDevice,
    NameTooLong,
    InvalidUtf8,
    InvalidWtf8,
    BadPathName,
    NetworkNotFound,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NotDir,
    DeviceBusy,
    Reported,
    Aborted,
};

fn populateNode(
    self: *Graph,
    stack: *TreeWalker.Iterator,
    params: HashMap(HashMap([]const u8)),
    sub_path: []const u8,
    task_name: []const u8,
    prev_node: ?*Node,
) PopulateNodeError!void {
    // Creating the modules before the main processing loop allows us to keep them on
    // the stack.
    var modules = try self.createModules(stack, sub_path);
    defer modules.deinit(self.gpa);
    stack.reset();

    var props = MergedProperties.init;

    while (stack.next()) |config| {
        const task = config.tasks.map.get(task_name) orelse continue;
        try props.mergeTask(self.gpa, task);
        if (props.skip) {
            break;
        }

        var module_types = modules.iterator();
        while (module_types.next()) |entry| {
            const module_type = entry.key_ptr.*;
            const module = entry.value_ptr;
            try module.props.mergeTask(self.gpa, task);

            if (task == .object) if (task.object.modules.map.get(module_type)) |module_task| {
                const patterns = config.modules.map.get(module_type);
                if (try module.isActive(self.gpa, patterns)) {
                    try module.props.mergeTask(self.gpa, module_task);
                }
            };
        }
    }

    // The `skip` attribute used at the project level should also skip the tasks for all
    // modules.
    if (props.skip) {
        props.deinit(self.gpa);
        var iter = modules.iterator();
        while (iter.next()) |entry| {
            const module = entry.value_ptr;
            module.deinit(self.gpa);
        }
        return;
    }

    try self.addNode(stack, params, sub_path, task_name, &props, null, prev_node);

    var iter = modules.iterator();
    while (iter.next()) |entry| {
        const module_type = entry.key_ptr.*;
        const module = entry.value_ptr;
        try self.addNode(stack, params, sub_path, task_name, &module.props, module_type, prev_node);
    }
}

fn createModules(self: *Graph, stack: *TreeWalker.Iterator, sub_path: []const u8) !HashMap(Module) {
    var modules = HashMap(Module){};
    while (stack.next()) |config| {
        for (config.modules.map.keys()) |module_type| {
            if (!modules.contains(module_type)) {
                const module = Module.init(self.cwd_path, sub_path);
                try modules.putNoClobber(self.gpa, module_type, module);
            }
        }
    }
    return modules;
}

fn mergeAliases(self: *Graph, stack: *TreeWalker.Iterator) !HashMap([]const []const u8) {
    var aliases = HashMap([]const []const u8){};
    while (stack.next()) |config| {
        var tasks = config.tasks.map.iterator();
        while (tasks.next()) |entry| {
            const task_name = entry.key_ptr.*;
            const task = entry.value_ptr.*;
            if (task == .object) {
                try aliases.put(self.gpa, task_name, task.object.aliases);
            }
        }
    }
    return aliases;
}

fn realTaskName(aliases: HashMap([]const []const u8), task_name: []const u8) []const u8 {
    var iter = aliases.iterator();
    while (iter.next()) |entry| {
        const real_task_name = entry.key_ptr.*;
        const scoped_aliases = entry.value_ptr.*;
        for (scoped_aliases) |alias| {
            if (mem.eql(u8, task_name, alias)) {
                return real_task_name;
            }
        }
    }
    return task_name;
}

fn addNode(
    self: *Graph,
    stack: *TreeWalker.Iterator,
    params: HashMap(HashMap([]const u8)),
    sub_path: []const u8,
    task_name: []const u8,
    props: *MergedProperties,
    module: ?[]const u8,
    prev_node: ?*Node,
) !void {
    if (props.skip or props.cmd == null) {
        props.deinit(self.gpa);
        return;
    }

    const id = try Node.createId(self.gpa, sub_path, task_name, module);
    if (self.nodes.get(id)) |node| {
        // It is both possible and acceptable for a node to already exist, however it will
        // always be the case that it's dependents have not been updated. Consider the
        // scenario where `build` depends on `test` and `test` was added before `build`. At
        // the time of adding the node for `test`, there was no way to know that it is a
        // dependent of `build`.
        if (prev_node) |prev| {
            self.updateDependencies(prev, node) catch |err| {
                self.gpa.free(id);
                return err;
            };
            try self.mergeObjectParams(prev, node);
        }
        props.deinit(self.gpa);
        self.gpa.free(id);
        return;
    }

    // We cannot just use the map from `params` directly, because we may need to merge
    // other parameters; calling `deinit()` on the map will result in an invalid free.
    var cli_params = HashMap([]const u8){};
    if (params.get(task_name)) |task_params| {
        var iter = task_params.iterator();
        while (iter.next()) |entry| {
            try cli_params.put(self.gpa, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    const sub_path_copy = try self.gpa.dupe(u8, sub_path);
    const node = try self.arena.allocator().create(Node);
    node.* = try Node.init(.{
        .id = id,
        .sub_path = sub_path_copy,
        .task_name = task_name,
        .module = module,
        .cli_params = cli_params,
        .props = props.*,
    });
    try self.nodes.put(self.gpa, node.id, node);

    if (prev_node) |prev| {
        try self.updateDependencies(prev, node);
        try self.mergeObjectParams(prev, node);
    }

    if (props.depends_on) |depends_on| {
        for (depends_on) |name| {
            try self.populateDependencyNodes(stack, params, node, name);
        }
    }

    return;
}

fn updateDependencies(self: *Graph, prev_node: *Node, curr_node: *Node) !void {
    try prev_node.*.dependencies.depends_on.append(self.gpa, curr_node);
    try curr_node.*.dependencies.dependents.append(self.gpa, prev_node);
    prev_node.*.indegree += 1;
    try self.detectCircularDependencies(prev_node, prev_node.*.dependencies.depends_on.items);
}

fn detectCircularDependencies(self: *Graph, node: *Node, depends_on: []*Node) !void {
    for (depends_on) |dep| {
        if (dep == node) {
            return self.diag.report(null, "circular dependency detected in task '{s}'", .{
                node.task_name,
            });
        }
        try self.detectCircularDependencies(node, dep.dependencies.depends_on.items);
    }
}

fn mergeObjectParams(self: *Graph, prev_node: *Node, curr_node: *Node) !void {
    var params = prev_node.params.iterator();
    const is_workspace_dependency = !mem.eql(u8, prev_node.sub_path, curr_node.sub_path);

    while (params.next()) |entry| {
        const name = entry.key_ptr.*;
        const param = entry.value_ptr.*;
        if (param == .string or param.object.value == null) {
            continue;
        }

        for (param.object.pass_to) |pass_to| {
            if (!shouldPassParam(pass_to, curr_node, is_workspace_dependency)) {
                continue;
            }

            if (prev_node.cli_params.get(name)) |value| {
                try curr_node.cli_params.put(self.gpa, name, value);
            }

            if (curr_node.params.get(name)) |kind| if (kind == .object) {
                try curr_node.*.params.put(self.gpa, name, .{
                    .object = .{
                        .value = param.object.value,
                        .pass_to = kind.object.pass_to,
                    },
                });
                continue;
            };

            try curr_node.*.params.put(self.gpa, name, param);
        }
    }
}

fn shouldPassParam(pass_to: []const u8, curr_node: *const Node, is_workspace_dependency: bool) bool {
    if (is_workspace_dependency) {
        return pass_to.len > 1 and
            pass_to[0] == workspace_dependency_prefix[0] and
            mem.eql(u8, pass_to[1..], curr_node.task_name);
    }
    return mem.eql(u8, pass_to, curr_node.task_name);
}

fn populateDependencyNodes(
    self: *Graph,
    stack: *TreeWalker.Iterator,
    params: HashMap(HashMap([]const u8)),
    node: *Node,
    task_name: []const u8,
) !void {
    const is_workspace_dependency = mem.startsWith(
        u8,
        task_name,
        workspace_dependency_prefix,
    ) and task_name.len > 1;

    if (is_workspace_dependency) {
        const real_task_name = task_name[1..];
        const config = self.walker.parser.getValue(node.sub_path) orelse return;

        for (config.dependencies) |sub_path| {
            const resolved = try fs.path.resolvePosix(self.gpa, &.{ node.sub_path, sub_path });
            const openable = if (resolved.len == 0) "." else resolved;
            defer self.gpa.free(resolved);

            var dir = self.cwd.openDir(openable, .{}) catch |err| {
                return self.diag.report(err, "failed to resolve dependency directory '{s}'", .{sub_path});
            };
            dir.close();

            try self.populateNode(stack, params, resolved, real_task_name, node);
        }

        return;
    }

    try self.populateNode(stack, params, node.sub_path, task_name, node);
}

fn normalizeSubpaths(self: *Graph, paths: []const []const u8) ![]const u8 {
    const resolved = try fs.path.resolvePosix(self.gpa, paths);
    const sub_path = if (resolved.len == 0) "." else resolved;

    var dir = self.cwd.openDir(sub_path, .{}) catch |err| {
        defer self.gpa.free(resolved);
        return self.diag.report(err, "dependency directory resolved to '{s}'", .{sub_path});
    };
    dir.close();

    return resolved;
}

pub const Node = struct {
    id: []const u8,
    sub_path: []const u8,
    task_name: []const u8,
    module: ?[]const u8,
    cmd: Command,
    params: HashMap(Parameter),
    cli_params: HashMap([]const u8),
    cache: ?Cache = null,
    env: HashMap([]const u8),
    dependencies: struct {
        depends_on: ArrayList(*Node) = .{},
        dependents: ArrayList(*Node) = .{},
    } = .{},
    /// The number of unprocessed nodes that this node depends on.
    indegree: u32 = 0,

    const RequiredProps = struct {
        id: []const u8,
        sub_path: []const u8,
        task_name: []const u8,
        module: ?[]const u8 = null,
        cli_params: HashMap([]const u8),
        props: MergedProperties,
    };

    fn init(req: RequiredProps) !Node {
        return Node{
            .id = req.id,
            .sub_path = req.sub_path,
            .task_name = req.task_name,
            .module = req.module,
            .cli_params = req.cli_params,
            .cmd = req.props.cmd.?,
            .cache = req.props.cache,
            .params = req.props.params,
            .env = req.props.env,
        };
    }

    fn deinit(self: *Node, gpa: Allocator) void {
        gpa.free(self.id);
        gpa.free(self.sub_path);
        self.params.deinit(gpa);
        self.cli_params.deinit(gpa);
        self.env.deinit(gpa);
        self.dependencies.depends_on.deinit(gpa);
        self.dependencies.dependents.deinit(gpa);
    }

    fn createId(
        gpa: Allocator,
        sub_path: []const u8,
        task_name: []const u8,
        module: ?[]const u8,
    ) ![]const u8 {
        const is_workspace_root = mem.eql(u8, sub_path, ".");

        return fmt.allocPrint(gpa, "{s}{s}{s}{s}{s}", .{
            if (is_workspace_root) "" else sub_path,
            if (is_workspace_root) "" else ":",
            task_name,
            if (module != null) ":" else "",
            if (module) |m| m else "",
        });
    }
};

const MergedProperties = struct {
    skip: bool = false,
    cmd: ?Command = null,
    depends_on: ?[]const []const u8 = null,
    cache: ?Cache = null,
    params: HashMap(Parameter) = .{},
    env: HashMap([]const u8) = .{},

    const init = MergedProperties{};

    fn deinit(self: *MergedProperties, gpa: Allocator) void {
        self.params.deinit(gpa);
        self.env.deinit(gpa);
    }

    fn mergeTask(self: *MergedProperties, gpa: Allocator, task: Task) !void {
        switch (task) {
            .string => |t| self.cmd = .{ .string = t },
            .array => |t| self.cmd = .{ .array = t },
            .object => |t| {
                if (t.skip) {
                    self.skip = true;
                    return;
                }
                if (t.cmd) |cmd| {
                    self.cmd = cmd;
                }
                if (t.depends_on) |depends_on| {
                    self.depends_on = depends_on;
                }
                if (t.cache) |cache| {
                    self.cache = cache;
                }
                try mergeEnv(gpa, t.env.map, &self.env);
                try mergeParams(gpa, t.params.map, &self.params);
            },
        }
    }

    fn mergeEnv(gpa: Allocator, src: HashMap([]const u8), dst: *HashMap([]const u8)) !void {
        var iter = src.iterator();
        while (iter.next()) |entry| {
            try dst.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    fn mergeParams(gpa: Allocator, src: HashMap(Parameter), dst: *HashMap(Parameter)) !void {
        var iter = src.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const param = entry.value_ptr.*;

            // It is important not to overwrite any existing `pass_to` values from previous
            // config files.
            if (param == .string) if (dst.get(name)) |kind| if (kind == .object) {
                try dst.put(gpa, name, .{
                    .object = .{
                        .value = param.string,
                        .pass_to = kind.object.pass_to,
                    },
                });
                continue;
            };

            try dst.put(gpa, name, param);
        }
    }
};

const Module = struct {
    cwd: []const u8,
    sub_path: []const u8,
    props: MergedProperties = .{},
    is_active: bool = false,

    fn init(cwd: []const u8, sub_path: []const u8) Module {
        return .{
            .cwd = cwd,
            .sub_path = sub_path,
        };
    }

    fn deinit(self: *Module, gpa: Allocator) void {
        self.props.deinit(gpa);
    }

    fn isActive(self: *Module, gpa: Allocator, patterns: ?[]const []const u8) !bool {
        const active_patterns = patterns orelse return self.is_active;
        self.is_active = try self.dirHasMatches(gpa, active_patterns);
        return self.is_active;
    }

    fn dirHasMatches(self: Module, gpa: Allocator, patterns: []const []const u8) !bool {
        for (patterns) |pattern| {
            const joined = try fs.path.resolvePosix(gpa, &.{ self.cwd, self.sub_path, pattern });
            defer gpa.free(joined);

            var results = try zlob.match(gpa, joined, ZlobFlags{
                .nosort = true,
                .brace = true,
                .gitignore = true,
                .doublestar_recursive = true,
                .extglob = true,
            }) orelse continue;
            defer results.deinit();

            if (results.len() > 0) {
                return true;
            }
        }

        return false;
    }
};

const Golden = struct {
    cwd: []const u8 = ".",
    workspace: []const []const u8 = &.{"."},
    task_names: []const []const u8,
    params: []const []const u8 = &.{},
    expected_nodes: ExpectedNodes = .{},
    expected_error: ?[]const u8 = null,

    const ExpectedNodes = json.ArrayHashMap(struct {
        sub_path: []const u8,
        task_name: []const u8,
        cmd: Command,
        module: ?[]const u8 = null,
        env: json.ArrayHashMap([]const u8) = .{},
        params: json.ArrayHashMap(Parameter) = .{},
        cli_params: json.ArrayHashMap([]const u8) = .{},
        dependencies: struct {
            depends_on: []const []const u8 = &.{},
            dependents: []const []const u8 = &.{},
        } = .{},
    });
};

fn expectEqualGraph(actual_nodes: HashMap(*Node), expected_nodes: Golden.ExpectedNodes) !void {
    try testing.expectEqual(expected_nodes.map.count(), actual_nodes.count());

    var iter = expected_nodes.map.iterator();
    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const expected_node = entry.value_ptr.*;
        const actual_node = actual_nodes.get(id).?;

        try testing.expectEqualStrings(expected_node.sub_path, actual_node.sub_path);
        try testing.expectEqualStrings(expected_node.task_name, actual_node.task_name);
        try testing.expectEqualDeep(expected_node.cmd, actual_node.cmd);
        try testing.expectEqualDeep(expected_node.module, actual_node.module);

        try expectEqualHashMaps(Parameter, expected_node.params.map, actual_node.params);
        try expectEqualHashMaps([]const u8, expected_node.cli_params.map, actual_node.cli_params);
        try expectEqualHashMaps([]const u8, expected_node.env.map, actual_node.env);

        try testing.expectEqual(expected_node.dependencies.depends_on.len, actual_node.indegree);
        try expectEqualDependencies(
            expected_node.dependencies.dependents,
            actual_node.dependencies.dependents.items,
        );
        try expectEqualDependencies(
            expected_node.dependencies.depends_on,
            actual_node.dependencies.depends_on.items,
        );
    }
}

fn expectEqualHashMaps(comptime T: type, expected_map: HashMap(T), actual_map: HashMap(T)) !void {
    try testing.expectEqual(expected_map.count(), actual_map.count());
    var iter = expected_map.iterator();
    while (iter.next()) |entry| {
        const expected_key = entry.key_ptr.*;
        const expected_value = entry.value_ptr.*;
        const actual_value = actual_map.get(expected_key).?;
        try testing.expectEqualDeep(expected_value, actual_value);
    }
}

fn expectEqualDependencies(expected_ids: []const []const u8, actual_nodes: []const (*Node)) !void {
    try testing.expectEqual(expected_ids.len, actual_nodes.len);
    blk: for (expected_ids) |id| {
        for (actual_nodes) |node| {
            if (mem.eql(u8, id, node.id)) {
                continue :blk;
            }
        }
        return error.TestExpectedEqual;
    }
}

test "populate(): should populate the graph with the expected nodes and dependencies" {
    const gpa = testing.allocator;

    const cwd = try process.getCwdAlloc(gpa);
    defer gpa.free(cwd);

    var dir = try fs.cwd().openDir("testdata/Graph", .{ .iterate = true });
    var iter = dir.iterate();
    defer dir.close();

    while (try iter.next()) |entry| {
        assert(entry.kind == .directory);

        var test_dir = try dir.openDir(entry.name, .{});
        defer test_dir.close();

        const file = try test_dir.openFile("golden.json", .{});
        defer file.close();

        var reader = file.reader(&.{});
        const contents = try reader.interface.allocRemaining(gpa, .unlimited);
        defer gpa.free(contents);

        const golden = try json.parseFromSlice(Golden, gpa, contents, .{ .allocate = .alloc_always });
        defer golden.deinit();

        var sub_dir = try test_dir.openDir(golden.value.cwd, .{});
        defer sub_dir.close();

        const sub_path = try fs.path.resolvePosix(gpa, &.{
            cwd, "testdata/Graph", entry.name, golden.value.cwd,
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

        const res = graph.populate(
            golden.value.workspace,
            golden.value.task_names,
            golden.value.params,
        );

        if (golden.value.expected_error) |err| {
            try testing.expectError(error.Reported, res);
            try testing.expect(mem.indexOf(u8, diag.payload.?, err) != null);
            return;
        }

        try res;
        try expectEqualGraph(graph.nodes, golden.value.expected_nodes);
    }
}

const zlob = @import("zlob");
const ZlobFlags = zlob.ZlobFlags;
const Config = @import("Config.zig");
const Cache = Config.Cache;
const Command = Config.Command;
const Parameter = Config.Parameter;
const Task = Config.Task;
const Shell = Config.Shell;
const Diagnostic = @import("Diagnostic.zig");
const TreeWalker = @import("TreeWalker.zig");
const parseParams = @import("parse_params.zig").parseParams;
const std = @import("std");
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const HashMap = std.StringArrayHashMapUnmanaged;
const assert = std.debug.assert;
const fmt = std.fmt;
const fs = std.fs;
const Dir = fs.Dir;
const json = std.json;
const mem = std.mem;
const Allocator = mem.Allocator;
const process = std.process;
const testing = std.testing;
