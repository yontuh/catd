fn getFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // So you don't open a massive file and use all your ram
    return try file.readToEndAlloc(allocator, 50 * 1024 * 1024);
}

fn walkDir(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var dirWalker = try dir.walk(allocator);
    defer dirWalker.deinit();

    var paths = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (paths.items) |p| {
            allocator.free(p);
        }
        paths.deinit();
    }

    while (try dirWalker.next()) |entry| {
        if (entry.kind == .file) {
            const dupe_path = try allocator.dupe(u8, entry.path);

            paths.append(dupe_path) catch |err| {
                allocator.free(dupe_path);
                return err;
            };
        }
    }

    return paths;
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

fn getAndParseInput(allocator: std.mem.Allocator) !struct { list_type: []const u8, list: [][:0]u8 } {
    const args = try std.process.argsAlloc(allocator);
    if (args.len <= 1) {
        std.debug.print("Error, -a or -o not found\n", .{});
        return std.process.exit(0);
    } else if (false == (std.mem.eql(u8, args[1], "-a") or std.mem.eql(u8, args[1], "--allowlist")) and (false == std.mem.eql(u8, args[1], "-o") or std.mem.eql(u8, args[1], "--omitlist"))) {
        std.debug.print("Error, -a or -o not found\n", .{});
        return std.process.exit(0);
    } else if (args.len <= 2) {
        std.debug.print("Error, no files specified\n", .{});
        return std.process.exit(0);
    } else if (std.mem.eql(u8, args[1], "-a") or std.mem.eql(u8, args[1], "--allowlist")) {
        return .{
            .list_type = "allowlist",
            .list = args[2..],
        };
    } else if (std.mem.eql(u8, args[1], "-o") or std.mem.eql(u8, args[1], "--omitlist")) {
        return .{
            .list_type = "omitlist",
            .list = args[2..],
        };
    }

    std.debug.print("Unknown error\n", .{});
    return std.process.exit(0);
}

fn keepOnly(
    allocator: std.mem.Allocator,
    paths_list: *std.ArrayList([]const u8),
    allowlist: []const []const u8,
) (CatdError || error{OutOfMemory})!void {
    for (allowlist) |allowed_path| {
        var found = false;
        for (paths_list.items) |path| {
            if (std.mem.startsWith(u8, path, allowed_path)) {
                found = true;
                break;
            }
        }
        if (!found) {
            const err_msg = try std.fmt.allocPrint(allocator, "Allow-listed path not found: {s}\n", .{allowed_path});
            defer allocator.free(err_msg); // Good practice to free this too
            _ = std.io.getStdErr().writer().write(err_msg) catch {};
            return CatdError.InvalidAllowList;
        }
    }

    var i: usize = 0;
    while (i < paths_list.items.len) {
        const current_path = paths_list.items[i];
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
            const removed_path = paths_list.orderedRemove(i);
            allocator.free(removed_path);
        }
    }
}

pub fn main() !void {
    const allocator = gpa.allocator();

    const args = try getAndParseInput(allocator);
    var paths_list = try walkDir(allocator);
    if (std.mem.eql(u8, args.list_type, "allowlist")) {
        const allowlist = args.list;
        keepOnly(allocator, &paths_list, allowlist) catch |err| {
            std.io.getStdErr().writer().print("Error:\n", .{}) catch {};
            switch (err) {
                error.InvalidAllowList => {
                    std.io.getStdErr().writer().print("Invalid path given to allow list\n", .{}) catch {};
                },
                error.OutOfMemory => {
                    std.io.getStdErr().writer().print("Ran out of memory.\n", .{}) catch {};
                },
            }
            return std.process.exit(0);
        };
    } else if (std.mem.eql(u8, args.list_type, "omitlist")) {
        const omit_list = args.list;
        omitPathsWithPrefix(allocator, &paths_list, omit_list);
    }

    defer {
        for (paths_list.items) |p| {
            allocator.free(p);
        }
        paths_list.deinit();
    }

    for (paths_list.items) |path_item| {
        try write("=============================================================================", "\n");
        try write(path_item, "\n");
        try write("=============================================================================", "\n");
        const contents = try getFileContents(allocator, path_item);
        try write(contents, "\n");
        allocator.free(contents);
    }
}

const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const CatdError = error{InvalidAllowList};
