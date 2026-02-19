const Commands = enum {
    clean,
    help,
    run,
    tree,
    version,
};

const main_parsers = .{
    .path = clap.parsers.string,
    .command = clap.parsers.enumeration(Commands),
};

const main_params =
    \\-c, --cwd <path>  Set current working directory
    \\-h, --help        Print help menu and exit
    \\-v, --version     Print version and exit
    \\<command>
;

const main_parsed_params = clap.parseParamsComptime(main_params);

const MainArgs = clap.ResultEx(clap.Help, &main_parsed_params, main_parsers);

pub fn main() !void {
    const is_debug_build = comptime builtin.mode == .Debug;
    var allocator = DebugAllocator(.{}).init;
    defer {
        const check = allocator.deinit();
        if (is_debug_build) {
            assert(check == .ok);
        }
    }
    const gpa = allocator.allocator();

    var env = try process.getEnvMap(gpa);
    const logger = Logger.init(env);
    env.deinit();

    var diag = Diagnostic.init(gpa);
    defer diag.deinit();

    mainCommand(gpa, &diag, logger) catch |err| {
        try diag.reportVoid(err, "unexpected error occurred", .{});

        try logger.stderr.print("{s}{s}error:{s} {s}\n", .{
            logger.stderr.render(.bold),
            logger.stderr.render(.red),
            logger.stderr.render(.reset),
            diag.payload.?,
        });

        if (is_debug_build) {
            return err;
        }
        process.exit(1);
    };
}

// some function that takes a gpa, diag, logger, iter, name, params, parsers, help options,
// whether it takes args, and a function to call that accepts type MainArgs

fn mainCommand(gpa: Allocator, diag: *Diagnostic, logger: Logger) !void {
    var iter = process.args();
    defer iter.deinit();
    const name = iter.next().?;

    var clap_diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_parsed_params, main_parsers, &iter, .{
        .diagnostic = &clap_diag,
        .allocator = gpa,
        .terminating_positional = 0,
    }) catch |err| return reportClapErr(diag, clap_diag, err);
    defer res.deinit();

    const opts = HelpOptions{
        .name = name,
        .description = "High-performance task orchestration system for any codebase",
        .subcommands = StaticStringMap([]const u8).initComptime(.{
            .{ "clean", "Clean the cache" },
            .{ "run", "Run tasks" },
            .{ "tree", "Print the dependency tree" },
            .{ "version", "Print version and exit" },
        }),
    };

    if (res.args.help != 0 or res.positionals[0] == null) {
        return printHelpMenu(gpa, logger, main_params, opts);
    }

    if (res.args.version != 0) {
        return logger.stdout.print("{s}\n", .{build.version});
    }

    const command = res.positionals[0] orelse unreachable;
    return switch (command) {
        .clean => cleanCommand(gpa, diag, logger, &iter),
        .help => printHelpMenu(gpa, logger, main_params, opts),
        .run => try runCommand(gpa, diag, logger, &iter),
        .tree => printHelpMenu(gpa, logger, main_params, opts),
        .version => logger.stdout.print("{s}\n", .{build.version}),
    };
}

fn cleanCommand(gpa: Allocator, diag: *Diagnostic, logger: Logger, iter: *ArgIterator) !void {
    const params = "-h, --help  Print help menu and exit\n";
    const parsed_params = comptime clap.parseParamsComptime(params);

    var clap_diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &parsed_params, clap.parsers.default, iter, .{
        .diagnostic = &clap_diag,
        .allocator = gpa,
    }) catch |err| return reportClapErr(diag, clap_diag, err);
    defer res.deinit();

    if (res.args.help != 0) {
        return printHelpMenu(gpa, logger, params, .{
            .name = "clean",
            .description = "Clean the cache",
        });
    }
}

fn runCommand(gpa: Allocator, diag: *Diagnostic, logger: Logger, iter: *ArgIterator) !void {
    const params =
        \\-f, --fail             Exit the process after the first task failure
        \\-h, --help             Print help menu and exit
        \\-j, --jobs <int>       The maximum number of parallel tasks (default: processors + 1)
        \\-m, --minimal-logs     Print task logs only, skip titles and summary
        \\-n, --no-cache         Skip reading and writing the cache
        \\-p, --params <params>  Parameters to pass to tasks
        \\-q, --quiet            Only print output from failed tasks
        \\-w, --watch            Rerun tasks when files matching the pattern change
        \\<task>...
    ;

    const parsed_params = comptime clap.parseParamsComptime(params);

    const parsers = .{
        .int = clap.parsers.int(u32, 10),
        .params = clap.parsers.string,
        .task = clap.parsers.string,
    };

    var clap_diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &parsed_params, parsers, iter, .{
        .diagnostic = &clap_diag,
        .allocator = gpa,
    }) catch |err| return reportClapErr(diag, clap_diag, err);
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0].len == 0) {
        return printHelpMenu(gpa, logger, params, .{
            .name = "run",
            .description = "Run tasks",
            .arguments = "<task>...",
        });
    }
}

fn treeCommand(gpa: Allocator, diag: *Diagnostic, logger: Logger, iter: *ArgIterator) !void {
    const params = "-h, --help  Print help menu and exit\n";
    const parsed_params = comptime clap.parseParamsComptime(params);

    var clap_diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &parsed_params, clap.parsers.default, iter, .{
        .diagnostic = &clap_diag,
        .allocator = gpa,
    }) catch |err| return reportClapErr(diag, clap_diag, err);
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0].len == 0) {
        return printHelpMenu(gpa, logger, params, .{
            .name = "tree",
            .description = "Print the dependency tree",
        });
    }
}

fn reportClapErr(diag: *Diagnostic, clap_diag: clap.Diagnostic, err: anyerror) anyerror {
    var longest = clap_diag.name.longest();
    if (longest.kind == .positional) {
        longest.name = clap_diag.arg;
    }

    return switch (err) {
        clap.streaming.Error.DoesntTakeValue => diag.report(
            null,
            "the argument '{s}{s}' does not take a value",
            .{ longest.kind.prefix(), longest.name },
        ),
        clap.streaming.Error.MissingValue => diag.report(
            null,
            "the argument '{s}{s}' requires a value but none was supplied",
            .{ longest.kind.prefix(), longest.name },
        ),
        clap.streaming.Error.InvalidArgument => diag.report(null, "invalid argument '{s}{s}'", .{
            longest.kind.prefix(), longest.name,
        }),
        else => diag.report(err, "failed to parse arguments", .{}),
    };
}

const HelpOptions = struct {
    name: []const u8,
    description: []const u8,
    arguments: []const u8 = "",
    subcommands: StaticStringMap([]const u8) = .{},
};

fn printHelpMenu(gpa: Allocator, logger: Logger, comptime params: []const u8, opts: HelpOptions) !void {
    try logger.stdout.print("{s}\n\n", .{opts.description});

    try logger.stdout.print("{s}{s}Usage:{s} {s} [options] {s}\n\n", .{
        logger.stdout.render(.bold),
        logger.stdout.render(.yellow),
        logger.stdout.render(.reset),
        opts.name,
        opts.arguments,
    });

    if (opts.subcommands.keys().len > 0) {
        try printHelpMenuSubcommands(gpa, logger, opts.subcommands);
    }

    try logger.stdout.print("{s}{s}Options:{s}\n", .{
        logger.stdout.render(.bold),
        logger.stdout.render(.yellow),
        logger.stdout.render(.reset),
    });

    var lines = mem.splitScalar(u8, params, '\n');
    while (lines.next()) |line| {
        if (lines.peek() == null) {
            break;
        }
        try printHelpMenuOption(logger, line);
    }

    const prefix = "Learn more:";
    const padding = comptime calcOptionDescriptionAlignment(params);
    assert(padding > prefix.len + 1);
    const spacer = try repeatString(gpa, " ", padding - prefix.len);
    defer gpa.free(spacer);

    try logger.stdout.print("\n{s}{s}{s}{s}{s}https://github.com/meechdw/cadence\n", .{
        logger.stdout.render(.bold),
        logger.stdout.render(.magenta),
        prefix,
        logger.stdout.render(.reset),
        spacer,
    });
}

fn printHelpMenuSubcommands(gpa: Allocator, logger: Logger, subcommands: StaticStringMap([]const u8)) !void {
    var max_key_len: usize = 0;
    for (subcommands.keys()) |key| {
        if (key.len > max_key_len) max_key_len = key.len;
    }

    try logger.stdout.print("{s}{s}Commands:{s}\n", .{
        logger.stdout.render(.bold),
        logger.stdout.render(.yellow),
        logger.stdout.render(.reset),
    });

    for (subcommands.keys()) |key| {
        const pad = try repeatString(gpa, " ", max_key_len - key.len + 2);
        defer gpa.free(pad);
        try logger.stdout.print("  {s}{s}{s}{s}{s}\n", .{
            logger.stdout.render(.green),
            key,
            logger.stdout.render(.reset),
            pad,
            subcommands.get(key).?,
        });
    }

    try logger.stdout.print("\n", .{});
}

fn printHelpMenuOption(logger: Logger, line: []const u8) !void {
    const double_space_index = mem.lastIndexOf(u8, line, "  ").?;
    const description = line[double_space_index..];

    var name = line[0..double_space_index];
    var parameter: []const u8 = "";
    if (mem.indexOfScalar(u8, name, '<')) |less_than_index| {
        if (mem.indexOfScalar(u8, name, '>')) |greater_than_index| {
            if (less_than_index < greater_than_index) {
                name = line[0..less_than_index];
                parameter = line[name.len..double_space_index];
            }
        }
    }

    if (mem.indexOf(u8, name, ",")) |comma_index| {
        const short_name = name[0..comma_index];
        const long_name = name[comma_index + 1 ..];

        try logger.stdout.print("  {s}{s}{s},{s}{s}{s}{s}{s}{s}{s}\n", .{
            logger.stdout.render(.green),
            short_name,
            logger.stdout.render(.reset),
            logger.stdout.render(.green),
            long_name,
            logger.stdout.render(.reset),
            logger.stdout.render(.cyan),
            parameter,
            logger.stdout.render(.reset),
            description,
        });

        return;
    }

    const name_padding = 2;
    const description_padding = 2;
    const padding = comptime name_padding + description_padding;

    try logger.stdout.print("      {s}{s}{s}{s}\n", .{
        logger.stdout.render(.cyan),
        name[0 .. name.len - padding],
        logger.stdout.render(.reset),
        description,
    });
}

fn calcOptionDescriptionAlignment(comptime params: []const u8) usize {
    const indentation_level = comptime 4;
    const first_line = params[0..mem.indexOfScalar(u8, params, '\n').?];
    return mem.lastIndexOf(u8, first_line, "  ").? + indentation_level;
}

fn repeatString(gpa: Allocator, str: []const u8, count: usize) ![]const u8 {
    const result = try gpa.alloc(u8, str.len * count);
    for (0..count) |i| {
        @memcpy(result[i * str.len .. (i + 1) * str.len], str);
    }
    return result;
}

const clap = @import("clap");
const Diagnostic = @import("Diagnostic.zig");
const Logger = @import("Logger.zig");
const build = @import("build");
const builtin = @import("builtin");
const std = @import("std");
const DebugAllocator = std.heap.DebugAllocator;
const StaticStringMap = std.StaticStringMap;
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;
const process = std.process;
const ArgIterator = process.ArgIterator;
