const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const CatdError = error{InvalidAllowList};

fn getFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, 50 * 1024 * 1024);
}

fn walkProvidedPaths(allocator: std.mem.Allocator, paths_to_walk: []const []const u8) !std.ArrayList([]const u8) {
    var all_found_files = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (all_found_files.items) |p| allocator.free(p);
        all_found_files.deinit();
    }

    for (paths_to_walk) |start_path| {
        const stat = std.fs.cwd().statFile(start_path) catch |err| {
            std.debug.print("Error accessing path '{s}': {s}\n", .{ start_path, @errorName(err) });
            continue;
        };

        if (stat.kind == .directory) {
            var dir = try std.fs.cwd().openDir(start_path, .{ .iterate = true });
            defer dir.close();

            var dirWalker = try dir.walk(allocator);
            defer dirWalker.deinit();

            while (try dirWalker.next()) |entry| {
                if (entry.kind == .file) {
                    const full_path = try std.fs.path.join(allocator, &.{ start_path, entry.path });
                    try all_found_files.append(full_path);
                }
            }
        } else if (stat.kind == .file) {
            const dupe_path = try allocator.dupe(u8, start_path);
            try all_found_files.append(dupe_path);
        }
    }

    return all_found_files;
}

fn write(data: []const u8, extra: []const u8) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}{s}", .{ data, extra });
    try bw.flush();
}

fn omitPathsWithPrefix(allocator: std.mem.Allocator, paths_list: *std.ArrayList([]const u8), unneeded_prefixes: []const []const u8) void {
    var i: usize = 0;
    while (i < paths_list.items.len) {
        const current_path_string = paths_list.items[i];
        var should_remove = false;
        for (unneeded_prefixes) |prefix| {
            if (std.mem.startsWith(u8, current_path_string, prefix)) {
                should_remove = true;
                break;
            }
        }

        if (should_remove) {
            const removed_path_slice = paths_list.orderedRemove(i);
            allocator.free(removed_path_slice);
        } else {
            i += 1;
        }
    }
}

fn keepOnlyAllowedPaths(allocator: std.mem.Allocator, master_list: *std.ArrayList([]const u8), allowlist: []const []const u8) void {
    var i: usize = 0;
    while (i < master_list.items.len) {
        const current_path = master_list.items[i];
        var should_keep = false;
        for (allowlist) |allowed_prefix| {
            if (std.mem.startsWith(u8, current_path, allowed_prefix)) {
                should_keep = true;
                break;
            }
        }

        if (should_keep) {
            i += 1;
        } else {
            const removed_path = master_list.orderedRemove(i);
            allocator.free(removed_path);
        }
    }
}

fn getAndParseInputFromSlice(args: []const []const u8) !struct { flag_type: []const u8, list: []const []const u8 } {
    if (args.len <= 1) {
        std.debug.print("Error, flag not found. Try --help\n", .{});
        return std.process.exit(0);
    } else if (false == (std.mem.eql(u8, args[1], "-a") or std.mem.eql(u8, args[1], "--allowlist")) and (false == std.mem.eql(u8, args[1], "-o") or std.mem.eql(u8, args[1], "--omitlist")) and (false == (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")))) {
        std.debug.print("Error, valid flag not found. Try --help\n", .{});
        return std.process.exit(0);
    } else if ((args.len <= 2) and !((std.mem.eql(u8, args[1], "-h")) or (std.mem.eql(u8, args[1], "--help")))) {
        std.debug.print("Error, no files specified\n", .{});
        return std.process.exit(0);
    } else if (std.mem.eql(u8, args[1], "-a") or std.mem.eql(u8, args[1], "--allowlist")) {
        return .{
            .flag_type = "allowlist",
            .list = args[2..],
        };
    } else if (std.mem.eql(u8, args[1], "-o") or std.mem.eql(u8, args[1], "--omitlist")) {
        return .{
            .flag_type = "omitlist",
            .list = args[2..],
        };
    } else if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        return .{
            .flag_type = "help",
            .list = args[2..],
        };
    }

    std.debug.print("Unknown error\n", .{});
    return std.process.exit(0);
}

pub fn main() !void {
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const original_args_list = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, original_args_list);

    const parsed_args = getAndParseInputFromSlice(original_args_list) catch |err| {
        std.debug.print("Error parsing arguments: {s}\n", .{@errorName(err)});
        return;
    };

    if (std.mem.eql(u8, parsed_args.flag_type, "allowlist")) {
        var paths_list = try walkProvidedPaths(allocator, parsed_args.list);
        defer {
            for (paths_list.items) |p| allocator.free(p);
            paths_list.deinit();
        }

        for (paths_list.items) |path_item| {
            try write("=============================================================================", "\n");
            try write(path_item, "\n");
            try write("=============================================================================", "\n");
            const contents = try getFileContents(allocator, path_item);
            defer allocator.free(contents);
            try write(contents, "\n");
        }
    } else if (std.mem.eql(u8, parsed_args.flag_type, "omitlist")) {
        var paths_list = try walkProvidedPaths(allocator, &[_][]const u8{"."});
        defer {
            for (paths_list.items) |p| allocator.free(p);
            paths_list.deinit();
        }

        const omit_list = parsed_args.list;
        omitPathsWithPrefix(allocator, &paths_list, omit_list);

        for (paths_list.items) |path_item| {
            try write("=============================================================================", "\n");
            try write(path_item, "\n");
            try write("=============================================================================", "\n");
            const contents = try getFileContents(allocator, path_item);
            defer allocator.free(contents);
            try write(contents, "\n");
        }
    } else if (std.mem.eql(u8, parsed_args.flag_type, "help")) {
        try write(
            \\USAGE:
            \\catd [OPTIONS] PATH
            \\
            \\  ARGUMENTS:
            \\  PATH | A file or directory to print.
            \\
            \\INPUT OPTIONS:
            \\  -o, --omitlist | Print all paths other than these.
            \\  -a, --allowlist | Print only these paths.
        , "\n");
    }
}
