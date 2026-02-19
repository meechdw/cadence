pub fn main() !void {
    const is_debug = comptime builtin.mode == .Debug;
    var allocator = DebugAllocator(.{}).init;
    defer {
        const check = allocator.deinit();
        if (is_debug) {
            assert(check == .ok);
        }
    }
    const gpa = allocator.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Print help and exit
        \\-v, --version          Print version and exit
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, .{}, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .assignment_separators = "=:",
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        std.debug.print("--help\n", .{});
    }
    if (res.args.version != 0) {
        std.debug.print("{s}\n", .{build.version});
    }
}

const clap = @import("clap");
const build = @import("build");
const builtin = @import("builtin");
const std = @import("std");
const DebugAllocator = std.heap.DebugAllocator;
const assert = std.debug.assert;
