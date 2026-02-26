/// Normalizes a native path to POSIX separators. On Windows, replaces backslashes
/// with forward slashes. On other platforms, returns the path as-is. Caller must
/// free the result on Windows.
pub fn normalize(gpa: Allocator, path: []const u8) Allocator.Error![]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return mem.replaceOwned(u8, gpa, path, fs.path.sep_str_windows, fs.path.sep_str_posix);
    }
    return path;
}

const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;
