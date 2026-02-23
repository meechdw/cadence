const Config = @This();

pub const filename = "cadence.json";

dependencies: []const []const u8 = &.{},
modules: json.ArrayHashMap([]const []const u8) = .{},
root: bool = false,
shell: Shell = .sh,
tasks: json.ArrayHashMap(Task) = .{},
workspace: ?[]const []const u8 = null,

pub const Shell = enum {
    ash,
    bash,
    powershell,
    sh,
    zsh,
};

pub const Task = union(enum) {
    string: []const u8,
    array: []const []const u8,
    object: ObjectTask,

    pub fn jsonParse(gpa: Allocator, source: anytype, options: json.ParseOptions) !Task {
        return switch (try source.peekNextTokenType()) {
            .string => .{ .string = try json.innerParse([]const u8, gpa, source, options) },
            .array_begin => .{ .array = try json.innerParse([]const []const u8, gpa, source, options) },
            .object_begin => .{ .object = try json.innerParse(ObjectTask, gpa, source, options) },
            else => error.UnexpectedToken,
        };
    }
};

pub const ObjectTask = struct {
    aliases: []const []const u8 = &.{},
    cache: ?struct {
        inputs: []const []const u8 = &.{},
        outputs: []const []const u8 = &.{},
    } = null,
    cmd: ?Command = null,
    depends_on: []const []const u8 = &.{},
    env: json.ArrayHashMap([]const u8) = .{},
    modules: json.ArrayHashMap(Task) = .{},
    params: json.ArrayHashMap(Parameter) = .{},
    skip: bool = false,
    watch: []const []const u8 = &.{},
};

pub const Command = union(enum) {
    string: []const u8,
    array: []const []const u8,

    pub fn jsonParse(gpa: Allocator, source: anytype, options: json.ParseOptions) !Command {
        return switch (try source.peekNextTokenType()) {
            .string => .{ .string = try json.innerParse([]const u8, gpa, source, options) },
            .array_begin => .{ .array = try json.innerParse([]const []const u8, gpa, source, options) },
            else => error.UnexpectedToken,
        };
    }
};

pub const Parameter = union(enum) {
    string: []const u8,
    object: ObjectParameter,

    pub fn jsonParse(gpa: Allocator, source: anytype, options: json.ParseOptions) !Parameter {
        return switch (try source.peekNextTokenType()) {
            .string => .{ .string = try json.innerParse([]const u8, gpa, source, options) },
            .object_begin => .{ .object = try json.innerParse(ObjectParameter, gpa, source, options) },
            else => error.UnexpectedToken,
        };
    }
};

pub const ObjectParameter = struct {
    value: []const u8 = "",
    pass_to: []const []const u8 = &.{},
};

pub const Parser = struct {
    gpa: Allocator,
    arena: ArenaAllocator,
    diag: *Diagnostic,
    file_buf: [max_file_bytes]u8 = undefined,
    cache: HashMap(*const json.Parsed(Config)) = .{},

    const max_file_bytes = 4096;

    pub fn init(gpa: Allocator, diag: *Diagnostic) Parser {
        return .{
            .gpa = gpa,
            .arena = ArenaAllocator.init(gpa),
            .diag = diag,
        };
    }

    pub fn deinit(self: Parser) void {
        self.arena.deinit();
    }

    pub fn getOrParse(self: *Parser, absolute_path: []const u8) !*const Config {
        if (self.cache.get(absolute_path)) |config| {
            return &config.value;
        }

        var contents_arena = ArenaAllocator.init(self.gpa);
        defer contents_arena.deinit();
        const contents = self.readFileSmart(contents_arena.allocator(), absolute_path) catch |err| {
            return self.diag.report(err, "failed to read '{f}'", .{
                fs.path.fmtJoin(&.{ absolute_path, filename }),
            });
        };

        var scanner = json.Scanner.initCompleteInput(self.gpa, contents);
        defer scanner.deinit();
        var jd = json.Diagnostics{};
        scanner.enableDiagnostics(&jd);

        const arena = self.arena.allocator();
        const config = try arena.create(json.Parsed(Config));
        config.* = json.parseFromTokenSource(Config, arena, &scanner, .{}) catch |err| {
            return self.diag.report(err, "failed to parse '{f}', line {d} column {d}", .{
                fs.path.fmtJoin(&.{ absolute_path, filename }), jd.getLine(), jd.getColumn(),
            });
        };

        const key = try arena.dupe(u8, absolute_path);
        try self.cache.putNoClobber(arena, key, config);

        return &config.value;
    }

    fn readFileSmart(self: *Parser, arena: Allocator, absolute_path: []const u8) ![]const u8 {
        var dir = try fs.openDirAbsolute(absolute_path, .{});
        defer dir.close();

        const file = try dir.openFile(filename, .{});
        defer file.close();

        const stat = try file.stat();
        if (stat.size > max_file_bytes) {
            var reader = file.reader(&.{});
            return reader.interface.allocRemaining(arena, .unlimited);
        }

        const bytes_read = try file.read(&self.file_buf);
        assert(bytes_read == stat.size);
        return self.file_buf[0..bytes_read];
    }
};

test "Parser.getOrParse(): should parse the same file faster the second time" {
    const gpa = testing.allocator;

    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var parser = Parser.init(testing.allocator, &diag);
    defer parser.deinit();

    const cwd = try process.getCwdAlloc(gpa);
    defer gpa.free(cwd);

    const test_dir = try fs.path.join(gpa, &.{ cwd, "testdata/Config" });
    defer gpa.free(test_dir);

    const start = time.nanoTimestamp();
    _ = try parser.getOrParse(test_dir);
    const elapsed = time.nanoTimestamp() - start;

    const cached_start = time.nanoTimestamp();
    _ = try parser.getOrParse(test_dir);
    const cached_elapsed = time.nanoTimestamp() - cached_start;

    try testing.expect(cached_elapsed < elapsed);
}

const Diagnostic = @import("Diagnostic.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const HashMap = std.StringArrayHashMapUnmanaged;
const assert = std.debug.assert;
const fs = std.fs;
const json = std.json;
const process = std.process;
const testing = std.testing;
const time = std.time;
