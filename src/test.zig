// The following blocks are organized such that each file in a given block depends
// on file(s) from previous blocks.
comptime {
    _ = @import("Diagnostic.zig");
    _ = @import("Logger.zig");
    _ = @import("parse_params.zig");

    _ = @import("Config.zig");

    _ = @import("TreeWalker.zig");
}
