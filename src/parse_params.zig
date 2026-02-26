const State = enum {
    default,
    in_key,
    in_double_quote,
    in_single_quote,
};

pub fn parseParams(gpa: Allocator, diag: *Diagnostic, str: []const u8) !HashMap([]const u8) {
    var params = HashMap([]const u8){};
    errdefer params.deinit(gpa);

    var state = State.in_key;
    var key_name: []const u8 = "";
    var key_start: usize = 0;
    var value_start: usize = 0;

    for (str, 0..) |b, i| {
        switch (state) {
            .in_key => {
                if (b == '=') {
                    key_name = str[key_start..i];
                    value_start = i + 1;
                    state = .default;
                    continue;
                }
                if (b == ' ') {
                    key_start = i + 1;
                }
            },
            .in_double_quote => {
                if (b == '"') {
                    try params.put(gpa, key_name, str[value_start..i]);
                    key_start = i + 1;
                    state = .in_key;
                }
            },
            .in_single_quote => {
                if (b == '\'') {
                    try params.put(gpa, key_name, str[value_start..i]);
                    key_start = i + 1;
                    state = .in_key;
                }
            },
            .default => {
                if (b == '"') {
                    value_start = i + 1;
                    state = .in_double_quote;
                    continue;
                }
                if (b == '\'') {
                    value_start = i + 1;
                    state = .in_single_quote;
                    continue;
                }
                if (b == ' ') {
                    try params.put(gpa, key_name, str[value_start..i]);
                    key_start = i + 1;
                    state = .in_key;
                }
            },
        }
    }

    if (state == .in_double_quote or state == .in_single_quote) {
        return diag.report(null, "failed to parse parameters, unterminated quote", .{});
    }

    if (state == .default) {
        try params.put(gpa, key_name, str[value_start..]);
    }

    return params;
}

test "parseParams(): should parse single unquoted parameter" {
    const gpa = testing.allocator;
    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var params = try parseParams(gpa, &diag, "timeout=3000");
    defer params.deinit(gpa);

    try testing.expectEqual(1, params.count());
    try testing.expectEqualStrings("3000", params.get("timeout").?);
}

test "parseParams(): should parse single quoted parameter with space" {
    const gpa = testing.allocator;
    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var params = try parseParams(gpa, &diag, "opts=\"--timeout 3000\"");
    defer params.deinit(gpa);

    try testing.expectEqual(1, params.count());
    try testing.expectEqualStrings("--timeout 3000", params.get("opts").?);
}

test "parseParams(): should parse multiple quoted parameters with spaces" {
    const gpa = testing.allocator;
    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var params = try parseParams(gpa, &diag, "timeout=5000 opts='--coverage --randomize'");
    defer params.deinit(gpa);

    try testing.expectEqual(2, params.count());
    try testing.expectEqualStrings("5000", params.get("timeout").?);
    try testing.expectEqualStrings("--coverage --randomize", params.get("opts").?);
}

test "parseParams(): should parse quoted parameter followed by unquoted parameter" {
    const gpa = testing.allocator;
    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    var params = try parseParams(gpa, &diag, "bun_opts='--cwd src' test_opts=--coverage");
    defer params.deinit(gpa);

    try testing.expectEqual(2, params.count());
    try testing.expectEqualStrings("--cwd src", params.get("bun_opts").?);
    try testing.expectEqualStrings("--coverage", params.get("test_opts").?);
}

test "parseParams(): should error given unterminated quotes" {
    const gpa = testing.allocator;
    var diag = Diagnostic.init(gpa);
    defer diag.deinit();
    try testing.expectError(error.Reported, parseParams(gpa, &diag, "opts=\"--coverage"));
}

const Diagnostic = @import("Diagnostic.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringArrayHashMapUnmanaged;
const testing = std.testing;
