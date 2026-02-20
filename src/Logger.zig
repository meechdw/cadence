const Logger = @This();

stdout: Stream,
stderr: Stream,

pub fn init(env: EnvMap) Logger {
    const stdout = File.stdout();
    const stderr = File.stderr();

    if (envSupportsColor(env)) |is_supported| {
        return .{
            .stdout = Stream.init(stdout, is_supported),
            .stderr = Stream.init(stderr, is_supported),
        };
    }

    const stdout_supports_color = stdout.getOrEnableAnsiEscapeSupport();
    const stderr_supports_color = stderr.getOrEnableAnsiEscapeSupport();

    return .{
        .stdout = Stream.init(stdout, stdout_supports_color),
        .stderr = Stream.init(stderr, stderr_supports_color),
    };
}

fn envSupportsColor(env: EnvMap) ?bool {
    if (env.get("NO_COLOR") != null) {
        return false;
    }
    if (env.get("CLICOLOR_FORCE") != null) {
        return true;
    }
    if (env.get("CLICOLOR")) |clicolor| {
        return !mem.eql(u8, clicolor, "0");
    }
    return null;
}

pub const Color = enum {
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    bold,
    reset,
};

const codes = EnumArray(Color, []const u8).init(.{
    .red = "\x1b[31m",
    .green = "\x1b[32m",
    .yellow = "\x1b[33m",
    .blue = "\x1b[34m",
    .magenta = "\x1b[35m",
    .cyan = "\x1b[36m",
    .bold = "\x1b[1m",
    .reset = "\x1b[0m",
});

pub const Stream = struct {
    file: File,
    is_color_supported: bool,

    fn init(file: File, is_color_supported: bool) Stream {
        return .{
            .file = file,
            .is_color_supported = is_color_supported,
        };
    }

    pub fn print(self: Stream, comptime fmt: []const u8, args: anytype) !void {
        var writer = self.file.writer(&.{});
        const interface = &writer.interface;
        try interface.print(fmt, args);
    }

    pub fn render(self: Stream, color: Color) []const u8 {
        if (self.is_color_supported) {
            return codes.get(color);
        }
        return "";
    }
};

test "init(): should not support color when 'NO_COLOR' is set" {
    var env = try process.getEnvMap(testing.allocator);
    defer env.deinit();

    env.remove("CLICOLOR");
    env.remove("CLICOLOR_FORCE");
    try env.put("NO_COLOR", "1");

    const logger = init(env);
    try testing.expect(!logger.stdout.is_color_supported);
    try testing.expect(!logger.stderr.is_color_supported);
}

test "init(): should support color when 'CLICOLOR_FORCE' is set" {
    var env = try process.getEnvMap(testing.allocator);
    defer env.deinit();

    env.remove("NO_COLOR");
    env.remove("CLICOLOR");
    try env.put("CLICOLOR_FORCE", "1");

    const logger = init(env);
    try testing.expect(logger.stdout.is_color_supported);
    try testing.expect(logger.stderr.is_color_supported);
}

test "init(): should not support color when 'CLICOLOR' is set to '0'" {
    var env = try process.getEnvMap(testing.allocator);
    defer env.deinit();

    env.remove("NO_COLOR");
    env.remove("CLICOLOR_FORCE");
    try env.put("CLICOLOR", "0");

    const logger = init(env);
    try testing.expect(!logger.stdout.is_color_supported);
    try testing.expect(!logger.stderr.is_color_supported);
}

test "init(): should support color when 'CLICOLOR' is set to anything other than '0'" {
    var env = try process.getEnvMap(testing.allocator);
    defer env.deinit();

    env.remove("NO_COLOR");
    env.remove("CLICOLOR_FORCE");
    try env.put("CLICOLOR", "1");

    const logger = init(env);
    try testing.expect(logger.stdout.is_color_supported);
    try testing.expect(logger.stderr.is_color_supported);
}

const std = @import("std");
const EnumArray = std.enums.EnumArray;
const EnvMap = std.process.EnvMap;
const File = std.fs.File;
const mem = std.mem;
const process = std.process;
const testing = std.testing;
