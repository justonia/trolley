const std = @import("std");
const builtin = @import("builtin");

/// Command types supported by the command file protocol.
/// Each line of the command file is a JSON object: {"type":"...", "data":"..."}
pub const CommandTag = enum {
    text,
    key,
    wait,
    screenshot,
    text_dump,
};

/// A parsed command ready for execution.
pub const Command = struct {
    tag: CommandTag,
    data: []const u8,
    /// Optional format for text_dump: 0=plain, 1=vt, 2=html.
    format: u8 = 0,
};

/// Queue of commands loaded from a command file.
/// Supports sequential execution with wait timers between commands.
pub const CommandQueue = struct {
    commands: std.ArrayListUnmanaged(Command) = .empty,
    current: usize = 0,
    /// Monotonic deadline (ms) for the current wait command, or null if not waiting.
    wait_deadline_ms: ?i64 = null,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator) CommandQueue {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *CommandQueue) void {
        self.arena.deinit();
    }

    /// Discard all commands and reset the queue for reuse.
    pub fn reset(self: *CommandQueue) void {
        self.commands = .empty;
        self.current = 0;
        self.wait_deadline_ms = null;
        _ = self.arena.reset(.retain_capacity);
    }

    /// Load commands from a file at `path`, then delete the file.
    pub fn loadFromFile(self: *CommandQueue, path: [*:0]const u8) !void {
        self.reset();
        const file = std.fs.cwd().openFileZ(path, .{}) catch |err| {
            std.debug.print("trolley: command: failed to open {s}: {}\n", .{ path, err });
            return err;
        };
        defer file.close();
        const alloc = self.arena.allocator();
        const contents = file.readToEndAlloc(alloc, 1024 * 1024) catch |err| {
            std.debug.print("trolley: command: failed to read {s}: {}\n", .{ path, err });
            return err;
        };
        self.parse(contents) catch |err| {
            std.debug.print("trolley: command: parse error: {}\n", .{err});
            return err;
        };
        // Delete the file so the sender can write a fresh one next time.
        std.fs.cwd().deleteFileZ(path) catch {};
    }

    /// Parse newline-delimited JSON commands from a byte slice.
    fn parse(self: *CommandQueue, contents: []const u8) !void {
        const alloc = self.arena.allocator();
        var iter = std.mem.splitScalar(u8, contents, '\n');
        while (iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            const cmd = try parseCommand(alloc, trimmed);
            try self.commands.append(alloc, cmd);
        }
    }

    /// Get the next command to execute given the current monotonic time (ms).
    /// Returns null if the queue is exhausted or a wait is still active.
    /// Wait commands are consumed internally — they are never returned.
    pub fn tick(self: *CommandQueue, now_ms: i64) ?Command {
        while (true) {
            // Check if a wait is active.
            if (self.wait_deadline_ms) |deadline| {
                if (now_ms < deadline) return null;
                self.wait_deadline_ms = null;
            }

            if (self.current >= self.commands.items.len) return null;

            const cmd = self.commands.items[self.current];
            self.current += 1;

            if (cmd.tag == .wait) {
                // data is seconds (supports fractional, e.g. "0.5")
                const wait_secs = std.fmt.parseFloat(f64, cmd.data) catch 1.0;
                const wait_ms: i64 = @intFromFloat(wait_secs * 1000.0);
                self.wait_deadline_ms = now_ms + wait_ms;
                continue;
            }

            return cmd;
        }
    }

    /// True while there are still commands to process (including pending waits).
    pub fn isActive(self: *const CommandQueue) bool {
        return self.current < self.commands.items.len or self.wait_deadline_ms != null;
    }
};

// ---------------------------------------------------------------------------
// Key name → escape sequence map
// ---------------------------------------------------------------------------

/// Map key names used in command files to terminal escape sequences.
/// These are standard VT/xterm sequences (normal cursor mode).
pub const key_map = std.StaticStringMap([]const u8).initComptime(.{
    // Navigation
    .{ "enter", "\r" },
    .{ "tab", "\x09" },
    .{ "escape", "\x1b" },
    .{ "backspace", "\x7f" },
    .{ "space", " " },

    // Arrow keys (normal mode — CSI sequences)
    .{ "arrow_up", "\x1b[A" },
    .{ "arrow_down", "\x1b[B" },
    .{ "arrow_right", "\x1b[C" },
    .{ "arrow_left", "\x1b[D" },
    .{ "up", "\x1b[A" },
    .{ "down", "\x1b[B" },
    .{ "right", "\x1b[C" },
    .{ "left", "\x1b[D" },

    // Control pad
    .{ "home", "\x1b[H" },
    .{ "end", "\x1b[F" },
    .{ "page_up", "\x1b[5~" },
    .{ "page_down", "\x1b[6~" },
    .{ "insert", "\x1b[2~" },
    .{ "delete", "\x1b[3~" },

    // Function keys
    .{ "f1", "\x1bOP" },
    .{ "f2", "\x1bOQ" },
    .{ "f3", "\x1bOR" },
    .{ "f4", "\x1bOS" },
    .{ "f5", "\x1b[15~" },
    .{ "f6", "\x1b[17~" },
    .{ "f7", "\x1b[18~" },
    .{ "f8", "\x1b[19~" },
    .{ "f9", "\x1b[20~" },
    .{ "f10", "\x1b[21~" },
    .{ "f11", "\x1b[23~" },
    .{ "f12", "\x1b[24~" },

    // Ctrl combinations
    .{ "ctrl+a", "\x01" },
    .{ "ctrl+b", "\x02" },
    .{ "ctrl+c", "\x03" },
    .{ "ctrl+d", "\x04" },
    .{ "ctrl+e", "\x05" },
    .{ "ctrl+f", "\x06" },
    .{ "ctrl+g", "\x07" },
    .{ "ctrl+h", "\x08" },
    .{ "ctrl+k", "\x0b" },
    .{ "ctrl+l", "\x0c" },
    .{ "ctrl+n", "\x0e" },
    .{ "ctrl+o", "\x0f" },
    .{ "ctrl+p", "\x10" },
    .{ "ctrl+q", "\x11" },
    .{ "ctrl+r", "\x12" },
    .{ "ctrl+s", "\x13" },
    .{ "ctrl+t", "\x14" },
    .{ "ctrl+u", "\x15" },
    .{ "ctrl+v", "\x16" },
    .{ "ctrl+w", "\x17" },
    .{ "ctrl+x", "\x18" },
    .{ "ctrl+y", "\x19" },
    .{ "ctrl+z", "\x1a" },
});

/// Keys that change when DECCKM (application cursor key mode) is active.
/// Only arrow keys and home/end are affected — they send SS3 instead of CSI.
const app_cursor_overrides = std.StaticStringMap([]const u8).initComptime(.{
    .{ "arrow_up", "\x1bOA" },
    .{ "arrow_down", "\x1bOB" },
    .{ "arrow_right", "\x1bOC" },
    .{ "arrow_left", "\x1bOD" },
    .{ "up", "\x1bOA" },
    .{ "down", "\x1bOB" },
    .{ "right", "\x1bOC" },
    .{ "left", "\x1bOD" },
    .{ "home", "\x1bOH" },
    .{ "end", "\x1bOF" },
});

/// Look up the escape sequence for a key name, respecting application cursor
/// key mode (DECCKM). When `app_cursor` is true and the key has an override,
/// the SS3 variant is returned; otherwise falls back to the normal CSI map.
pub fn resolveKey(name: []const u8, app_cursor: bool) ?[]const u8 {
    if (app_cursor) {
        if (app_cursor_overrides.get(name)) |seq| return seq;
    }
    return key_map.get(name);
}

/// Parse the "format" field of a text_dump command into the u8 enum.
fn parseTextDumpFormat(fmt_str: []const u8) u8 {
    if (std.mem.eql(u8, fmt_str, "vt")) return 1;
    if (std.mem.eql(u8, fmt_str, "html")) return 2;
    return 0; // plain
}

// ---------------------------------------------------------------------------
// JSON line parser
// ---------------------------------------------------------------------------

/// Minimal JSON string extractor — finds the value for a given key in a flat
/// JSON object. Returns the raw string content (without quotes). Handles
/// basic backslash escapes (\", \\, \n, \t, \r) but not \uXXXX.
fn jsonStringField(json: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key"  :  "value"
    var i: usize = 0;
    while (i + key.len + 3 < json.len) : (i += 1) {
        // Look for opening quote of the key.
        if (json[i] != '"') continue;
        const key_start = i + 1;
        if (key_start + key.len >= json.len) continue;
        if (!std.mem.eql(u8, json[key_start .. key_start + key.len], key)) continue;
        if (json[key_start + key.len] != '"') continue;

        // Skip past closing quote of key, whitespace, and colon.
        var j = key_start + key.len + 1;
        while (j < json.len and (json[j] == ' ' or json[j] == ':' or json[j] == '\t')) : (j += 1) {}

        // Expect opening quote of value.
        if (j >= json.len or json[j] != '"') continue;
        j += 1;

        // Find closing quote (skip escaped characters).
        const val_start = j;
        while (j < json.len) : (j += 1) {
            if (json[j] == '\\') {
                j += 1; // skip escaped char
                continue;
            }
            if (json[j] == '"') break;
        }
        if (j >= json.len) continue;
        return json[val_start..j];
    }
    return null;
}

/// Unescape a JSON string value in-place into the arena allocator.
/// Handles: \\, \", \n, \t, \r, \/.
fn unescapeJsonString(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    // Fast path: no escapes.
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;

    var buf = try allocator.alloc(u8, raw.len);
    var out: usize = 0;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            i += 1;
            buf[out] = switch (raw[i]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '"' => '"',
                '/' => '/',
                else => raw[i],
            };
        } else {
            buf[out] = raw[i];
        }
        out += 1;
    }
    return buf[0..out];
}

fn parseCommand(allocator: std.mem.Allocator, line: []const u8) !Command {
    const type_str = jsonStringField(line, "type") orelse return error.MissingType;
    const data_raw = jsonStringField(line, "data") orelse "";
    const data = try unescapeJsonString(allocator, data_raw);

    const tag: CommandTag = if (std.mem.eql(u8, type_str, "text"))
        .text
    else if (std.mem.eql(u8, type_str, "key"))
        .key
    else if (std.mem.eql(u8, type_str, "wait"))
        .wait
    else if (std.mem.eql(u8, type_str, "screenshot"))
        .screenshot
    else if (std.mem.eql(u8, type_str, "text_dump"))
        .text_dump
    else {
        std.debug.print("trolley: command: unknown type \"{s}\"\n", .{type_str});
        return error.UnknownCommandType;
    };

    var format: u8 = 0;
    if (tag == .text_dump) {
        if (jsonStringField(line, "format")) |fmt| {
            format = parseTextDumpFormat(fmt);
        }
    }

    return .{ .tag = tag, .data = data, .format = format };
}

// ---------------------------------------------------------------------------
// Monotonic clock helper
// ---------------------------------------------------------------------------

/// Returns the current monotonic time in milliseconds.
pub fn nowMs() i64 {
    if (comptime builtin.os.tag == .windows) {
        const kernel32 = struct {
            extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.winapi) i32;
            extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.winapi) i32;
        };
        var counter: i64 = 0;
        var freq: i64 = 1;
        _ = kernel32.QueryPerformanceCounter(&counter);
        _ = kernel32.QueryPerformanceFrequency(&freq);
        return @divTrunc(counter * 1000, freq);
    } else {
        const ts = std.posix.clock_gettime(.MONOTONIC) catch return 0;
        return @as(i64, ts.sec) * 1000 + @divTrunc(ts.nsec, 1_000_000);
    }
}

// ---------------------------------------------------------------------------
// Command file path resolution
// ---------------------------------------------------------------------------

/// Resolve the command file path from the environment variable
/// TROLLEY_COMMAND_FILE, falling back to the config value.
/// Returns null if neither is set.
pub fn resolveCommandFilePath(config_path: ?[*:0]const u8) ?[*:0]const u8 {
    // Check environment variable first.
    if (comptime builtin.os.tag == .windows) {
        // Windows: use _wgetenv or just check the config path.
        // The Rust config loader already checks the env var and sets config_path.
        return config_path;
    } else {
        const env_val = std.posix.getenv("TROLLEY_COMMAND_FILE");
        if (env_val) |val| {
            if (val.len > 0) return val.ptr;
        }
        return config_path;
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "jsonStringField basics" {
    const json = "{\"type\":\"text\", \"data\":\"hello world\"}";
    try std.testing.expectEqualStrings("text", jsonStringField(json, "type").?);
    try std.testing.expectEqualStrings("hello world", jsonStringField(json, "data").?);
    try std.testing.expect(jsonStringField(json, "missing") == null);
}

test "parseCommand text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmd = try parseCommand(arena.allocator(), "{\"type\":\"text\", \"data\":\"hello\\nworld\"}");
    try std.testing.expect(cmd.tag == .text);
    try std.testing.expectEqualStrings("hello\nworld", cmd.data);
}

test "parseCommand key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmd = try parseCommand(arena.allocator(), "{\"type\":\"key\", \"data\":\"enter\"}");
    try std.testing.expect(cmd.tag == .key);
    try std.testing.expectEqualStrings("enter", cmd.data);
}

test "parseCommand wait" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmd = try parseCommand(arena.allocator(), "{\"type\":\"wait\", \"data\":\"2.5\"}");
    try std.testing.expect(cmd.tag == .wait);
    try std.testing.expectEqualStrings("2.5", cmd.data);
}

test "parseCommand text_dump with format" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmd = try parseCommand(arena.allocator(), "{\"type\":\"text_dump\", \"data\":\"/tmp/dump.txt\", \"format\":\"vt\"}");
    try std.testing.expect(cmd.tag == .text_dump);
    try std.testing.expectEqualStrings("/tmp/dump.txt", cmd.data);
    try std.testing.expect(cmd.format == 1);
}

test "CommandQueue tick with wait" {
    var q = CommandQueue.init(std.testing.allocator);
    defer q.deinit();
    const alloc = q.arena.allocator();

    try q.commands.append(alloc, .{ .tag = .text, .data = "hello" });
    try q.commands.append(alloc, .{ .tag = .wait, .data = "1" });
    try q.commands.append(alloc, .{ .tag = .text, .data = "world" });

    // First tick returns "hello".
    const cmd1 = q.tick(0);
    try std.testing.expect(cmd1 != null);
    try std.testing.expectEqualStrings("hello", cmd1.?.data);

    // Next tick at t=0 returns null (wait consuming + deadline set).
    try std.testing.expect(q.tick(0) == null);

    // Still waiting at t=500.
    try std.testing.expect(q.tick(500) == null);

    // Wait expired at t=1000.
    const cmd2 = q.tick(1000);
    try std.testing.expect(cmd2 != null);
    try std.testing.expectEqualStrings("world", cmd2.?.data);

    // Queue exhausted.
    try std.testing.expect(q.tick(2000) == null);
    try std.testing.expect(!q.isActive());
}
