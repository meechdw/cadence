const Diagnostic = @This();

pub const max_err_bytes = 512;

gpa: Allocator,
payload: ?[]const u8 = null,

pub fn init(gpa: Allocator) Diagnostic {
    return .{ .gpa = gpa };
}

pub fn deinit(self: Diagnostic) void {
    if (self.payload) |payload| {
        self.gpa.free(payload);
    }
}

/// Records non-clobbering error information. Not clobbering means that we can
/// provide fallback error reporting throughout the codebase, providing the user with
/// nice error messages without requiring us to provide error information for every
/// possible error.
pub fn report(self: *Diagnostic, err: ?anyerror, comptime format: []const u8, args: anytype) anyerror {
    if (self.payload != null) {
        return error.Reported;
    }

    if (err) |e| {
        var buf: [max_err_bytes]u8 = undefined;
        const formatted = bufWriteErr(&buf, e);
        self.payload = try fmt.allocPrint(self.gpa, format ++ ": {s}", args ++ .{formatted});
        return error.Reported;
    }

    self.payload = try fmt.allocPrint(self.gpa, format, args);
    return error.Reported;
}

/// This function is useful for concisely recording errors that do not need to be
/// propogated up the call stack.
pub fn reportVoid(self: *Diagnostic, err: ?anyerror, comptime format: []const u8, args: anytype) !void {
    const recorded = self.report(err, format, args);
    if (recorded == error.OutOfMemory) {
        return recorded;
    }
}

/// Translates an error value into space-separated, lowercase words for nicer error
/// messages. Assumes the error value does not contain uppercase acronyms, which
/// appears to align with the errors from the standard library.
pub fn bufWriteErr(buf: []u8, err: anytype) []const u8 {
    const err_name = @errorName(err);
    const max_write_len = err_name.len * 2 - 1; // e.g. 'ABC' -> 'a b c'
    assert(buf.len >= max_write_len);

    var i: u32 = 0;
    for (err_name) |b| {
        defer i += 1;

        if (i == 0) {
            buf[i] = ascii.toLower(b);
            continue;
        }

        if (ascii.isUpper(b)) {
            buf[i] = ' ';
            buf[i + 1] = ascii.toLower(b);
            i += 1;
            continue;
        }

        buf[i] = b;
    }

    return buf[0..i];
}

test "record()" {
    var diag = Diagnostic.init(testing.allocator);
    defer diag.deinit();

    var err = diag.report(error.TestError, "test {s}", .{"error"});
    try testing.expectEqual(error.Reported, err);

    err = diag.report(error.AnotherTestError, "another test {s}", .{"error"});
    try testing.expectEqual(error.Reported, err);

    try testing.expectEqualStrings("test error: test error", diag.payload.?);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ascii = std.ascii;
const assert = std.debug.assert;
const fmt = std.fmt;
const testing = std.testing;
