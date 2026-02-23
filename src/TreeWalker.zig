const TreeWalker = @This();

gpa: Allocator,
arena: ArenaAllocator,
parser: *Config.Parser,
cache: HashMap([]*const Config) = .{},

pub fn init(gpa: Allocator, parser: *Config.Parser) TreeWalker {
    return .{
        .gpa = gpa,
        .arena = ArenaAllocator.init(gpa),
        .parser = parser,
    };
}

pub fn deinit(self: TreeWalker) void {
    self.arena.deinit();
}

/// Walks up the file system and parses config files as they are encountered. The
/// return value is an iterator that can be used to process the files in reverse
/// order of discovery to properly merge task definitions.
pub fn walk(self: *TreeWalker, absolute_path: []const u8) !Iterator {
    if (self.cache.get(absolute_path)) |configs| {
        return Iterator.init(configs);
    }

    const arena = self.arena.allocator();
    var configs = ArrayList(*const Config){};
    var mut_absolute_path = absolute_path;
    var dir = try fs.openDirAbsolute(mut_absolute_path, .{});
    defer dir.close();

    while (true) {
        if (try dirContainsConfig(dir)) {
            const config = try self.parser.getOrParse(mut_absolute_path);
            try configs.append(arena, config);
            if (config.root or config.workspace != null) {
                break;
            }
        }

        // `dirname()` returns `null` if the resulting path is the root directory, in which
        // case we are done walking.
        mut_absolute_path = fs.path.dirname(mut_absolute_path) orelse break;
        dir.close();
        dir = try fs.openDirAbsolute(mut_absolute_path, .{});
    }

    const key = try arena.dupe(u8, absolute_path);
    const owned_configs = try configs.toOwnedSlice(arena);
    try self.cache.putNoClobber(arena, key, owned_configs);

    return Iterator.init(owned_configs);
}

fn dirContainsConfig(dir: Dir) !bool {
    dir.access(Config.filename, .{}) catch |err| {
        if (err == Dir.AccessError.FileNotFound) {
            return false;
        }
        return err;
    };
    return true;
}

pub const Iterator = struct {
    configs: []*const Config,
    index: usize = 0,

    pub fn init(configs: []*const Config) Iterator {
        return .{
            .configs = configs,
            .index = configs.len,
        };
    }

    pub fn next(self: *Iterator) ?*const Config {
        if (self.index > 0) {
            defer self.index -= 1;
            return self.configs[self.index - 1];
        }
        return null;
    }

    pub fn reset(self: *Iterator) void {
        self.index = self.configs.len;
    }
};

test "walk(): should parse config files until the root config file is reached" {
    const gpa = testing.allocator;
    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var parser = Config.Parser.init(gpa, &diag);
    defer parser.deinit();

    var walker = TreeWalker.init(gpa, &parser);
    defer walker.deinit();

    const cwd = try process.getCwdAlloc(gpa);
    defer gpa.free(cwd);
    const test_dir = try fs.path.join(gpa, &.{ cwd, "testdata/TreeWalker/workspace/packages/shared" });
    defer gpa.free(test_dir);

    const iter = try walker.walk(test_dir);
    try testing.expectEqual(2, iter.configs.len);
}

const Config = @import("Config.zig");
const Diagnostic = @import("Diagnostic.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const HashMap = std.StringHashMapUnmanaged;
const fs = std.fs;
const Dir = fs.Dir;
const process = std.process;
const testing = std.testing;
