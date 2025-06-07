pub fn main() !void {
    const file_contents = try getFileContents("src/main.zig");
    _ = file_contents;
    // try write(file_contents);
    // try listDir();
    try walkDir();
}
fn walkDir() !void {
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();
    var dirWalker = try dir.walk(gpa.allocator());
    while (try dirWalker.next()) |entry| {
        std.debug.print("{s}\n", .{entry.path});
    }
}

fn listDir() !void {
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();
    var dirIterator = dir.iterate();
    while (try dirIterator.next()) |dirContent| {
        std.debug.print("{s}\n", .{dirContent.name});
    }
}

fn write(data: []const u8) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}", .{data});
    try bw.flush(); // Don't forget to flush!
}
fn getFileContents(path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var buffered = std.io.bufferedReader(file.reader());
    var bufreader = buffered.reader();
    var buffer: [1000]u8 = undefined;
    @memset(buffer[0..], 0);

    _ = try bufreader.read(buffer[0..]);
    return &buffer;
}
const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
