const std = @import("std");
const builtin = @import("builtin");

fn getenv(name: []const u8) ?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(std.heap.page_allocator, name) catch null;
    } else {
        return std.posix.getenv(name);
    }
}

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll("Hello from trolley!\n\n");
    try stdout.writeAll("This is a minimal trolley example.\n\n");

    const hello_from = getenv("HELLO_FROM") orelse "(not set)";
    const lang = getenv("LANG") orelse "(not set)";

    var buf: [256]u8 = undefined;
    var written = std.fmt.bufPrint(&buf, "HELLO_FROM = {s}\n", .{hello_from}) catch "(fmt error)";
    try stdout.writeAll(written);
    written = std.fmt.bufPrint(&buf, "LANG       = {s}\n\n", .{lang}) catch "(fmt error)";
    try stdout.writeAll(written);

    try stdout.writeAll("Press Enter to exit.\n");

    const stdin = std.fs.File.stdin();
    var read_buf: [1]u8 = undefined;
    _ = stdin.read(&read_buf) catch {};
}
