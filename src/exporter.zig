const std = @import("std");
const models = @import("models.zig");

const log = std.log.scoped(.syngen_exp);

pub const Exporter = struct {
    allocator: std.mem.Allocator,
    base_dir: std.fs.Dir,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Exporter {
        // Ensure a clean directory for every run
        std.fs.cwd().deleteTree(path) catch {};
        try std.fs.cwd().makePath(path);
        const dir = try std.fs.cwd().openDir(path, .{});
        return .{
            .allocator = allocator,
            .base_dir = dir,
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Exporter) void {
        self.base_dir.close();
        self.allocator.free(self.path);
    }

    pub fn writeUsers(self: *Exporter, users: []const models.User) !void {
        const file = try self.base_dir.createFile("users.json", .{});
        defer file.close();
        var write_buf: [65536]u8 = undefined;
        var f_writer = file.writer(&write_buf);
        try std.json.Stringify.value(users, .{}, &f_writer.interface);
        try f_writer.interface.flush();
    }

    pub fn writeChannels(self: *Exporter, channels: []const models.Channel) !void {
        const file = try self.base_dir.createFile("channels.json", .{});
        defer file.close();
        var write_buf: [65536]u8 = undefined;
        var f_writer = file.writer(&write_buf);
        try std.json.Stringify.value(channels, .{}, &f_writer.interface);
        try f_writer.interface.flush();
        
        for (channels) |ch| {
            try self.base_dir.makePath(ch.name);
        }
    }

    pub fn writeMessages(self: *Exporter, messages: []models.Message, channels: []const models.Channel) !void {
        log.info("Writing {d} messages to channel files using parallelism...", .{messages.len});
        const timer_start = std.time.milliTimestamp();

        const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
        var pool: std.Thread.Pool = undefined;
        try pool.init(.{ .allocator = self.allocator, .n_jobs = cpu_count });
        defer pool.deinit();

        var wg: std.Thread.WaitGroup = .{};

        // Actually, we can just sort the message array by channel_id first.
        // It's already sorted by TS. Sorting by channel_id (stable) will group channels while keeping TS order within channel.
        std.sort.pdq(models.Message, messages, {}, struct {
            fn lessThan(_: void, a: models.Message, b: models.Message) bool {
                return std.mem.lessThan(u8, a.channel_id.?, b.channel_id.?);
            }
        }.lessThan);

        var start_idx: usize = 0;
        while (start_idx < messages.len) {
            const current_ch_id = messages[start_idx].channel_id.?;
            var end_idx = start_idx + 1;
            while (end_idx < messages.len and std.mem.eql(u8, messages[end_idx].channel_id.?, current_ch_id)) {
                end_idx += 1;
            }

            const channel_msgs = messages[start_idx..end_idx];
            const ch_name = blk: {
                for (channels) |c| {
                    if (std.mem.eql(u8, c.id, current_ch_id)) break :blk c.name;
                }
                break :blk "unknown";
            };

            wg.start();
            try pool.spawn(writeChannelMessages, .{ self, ch_name, channel_msgs, &wg });
            
            start_idx = end_idx;
        }

        pool.waitAndWork(&wg);
        const total_done = std.time.milliTimestamp();
        log.info("Finished writing files in {d}ms", .{total_done - timer_start});
    }

    fn writeChannelMessages(self: *Exporter, ch_name: []const u8, messages: []const models.Message, wg: *std.Thread.WaitGroup) void {
        defer wg.finish();
        
        // Use a local arena for temporary strings (keys, dates)
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var current_msg_list: std.ArrayList(models.Message) = .empty;
        defer current_msg_list.deinit(allocator);
        var last_date: ?[]const u8 = null;

        for (messages) |msg| {
            const ts_f = std.fmt.parseFloat(f64, msg.ts) catch continue;
            const date_str = self.formatDateThreadSafe(allocator, @intFromFloat(ts_f)) catch continue;

            if (last_date == null or !std.mem.eql(u8, date_str, last_date.?)) {
                if (current_msg_list.items.len > 0) {
                    self.flushMessagesThreadSafe(ch_name, last_date.?, current_msg_list.items) catch {};
                    current_msg_list.clearRetainingCapacity();
                }
                last_date = date_str;
            }
            current_msg_list.append(allocator, msg) catch {};
        }

        if (current_msg_list.items.len > 0) {
            self.flushMessagesThreadSafe(ch_name, last_date.?, current_msg_list.items) catch {};
        }
    }

    fn flushMessagesThreadSafe(self: *Exporter, ch_name: []const u8, date_str: []const u8, msgs: []const models.Message) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ ch_name, date_str });
        defer self.allocator.free(path);
        
        const file = try self.base_dir.createFile(path, .{});
        defer file.close();
        
        // Use a 64KB buffer for streaming JSON to disk
        var write_buf: [65536]u8 = undefined;
        var f_writer = file.writer(&write_buf);
        try std.json.Stringify.value(msgs, .{}, &f_writer.interface);
        try f_writer.interface.flush();
    }

    fn formatDateThreadSafe(self: *Exporter, allocator: std.mem.Allocator, ts: i64) ![]const u8 {
        _ = self;
        const seconds_in_day = 86400;
        const days_since_epoch = @divFloor(ts, seconds_in_day);
        var year: i32 = 1970;
        var remaining_days = days_since_epoch;
        while (true) {
            const is_leap = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
            const days_in_year: i32 = if (is_leap) 366 else 365;
            if (remaining_days < days_in_year) break;
            remaining_days -= days_in_year;
            year += 1;
        }
        const is_leap = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
        const month_days = [_]i32{ 31, if (is_leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var month: usize = 0;
        while (remaining_days >= month_days[month]) {
            remaining_days -= month_days[month];
            month += 1;
        }
        return std.fmt.allocPrint(allocator, "{:0>4}-{:0>2}-{:0>2}", .{ @as(u32, @intCast(year)), @as(u32, @intCast(month + 1)), @as(u32, @intCast(remaining_days + 1)) });
    }

    pub fn finalize(self: *Exporter, output_filename: []const u8) !void {
        const absolute_output_path = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(absolute_output_path);
        
        const zip_filename = if (std.mem.endsWith(u8, output_filename, ".zip"))
            try self.allocator.dupe(u8, output_filename)
        else
            try std.fmt.allocPrint(self.allocator, "{s}.zip", .{output_filename});
        defer self.allocator.free(zip_filename);

        // Delete existing zip file to prevent accumulation
        std.fs.cwd().deleteFile(zip_filename) catch {};

        const full_zip_path = try std.fs.path.join(self.allocator, &[_][]const u8{ absolute_output_path, zip_filename });
        defer self.allocator.free(full_zip_path);

        var child = std.process.Child.init(&[_][]const u8{ "zip", "-q", "-1", "-r", full_zip_path, "." }, self.allocator);
        
        const absolute_base_path = try std.fs.cwd().realpathAlloc(self.allocator, self.path);
        defer self.allocator.free(absolute_base_path);
        child.cwd = absolute_base_path;

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| if (code != 0) return error.ZipCommandFailed,
            else => return error.ZipCommandFailed,
        }
    }

    fn formatDate(self: *Exporter, ts: i64) ![]const u8 {
        const seconds_in_day = 86400;
        const days_since_epoch = @divFloor(ts, seconds_in_day);
        
        var year: i32 = 1970;
        var remaining_days = days_since_epoch;
        
        while (true) {
            const is_leap = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
            const days_in_year: i32 = if (is_leap) 366 else 365;
            if (remaining_days < days_in_year) break;
            remaining_days -= days_in_year;
            year += 1;
        }
        
        const is_leap = (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
        const month_days = [_]i32{ 31, if (is_leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        
        var month: usize = 0;
        while (remaining_days >= month_days[month]) {
            remaining_days -= month_days[month];
            month += 1;
        }
        
        return std.fmt.allocPrint(self.allocator, "{:0>4}-{:0>2}-{:0>2}", .{ @as(u32, @intCast(year)), @as(u32, @intCast(month + 1)), @as(u32, @intCast(remaining_days + 1)) });
    }
};

test "exporter test" {
    const allocator = std.testing.allocator;
    const test_path = "test-export";
    defer std.fs.cwd().deleteTree(test_path) catch {};

    var exporter = try Exporter.init(allocator, test_path);
    defer exporter.deinit();

    const users = [_]models.User{
        .{
            .id = try allocator.dupe(u8, "U123"),
            .team_id = try allocator.dupe(u8, "T1"),
            .name = try allocator.dupe(u8, "john"),
            .real_name = try allocator.dupe(u8, "John"),
            .updated = 0,
            .profile = .{
                .real_name = try allocator.dupe(u8, "John"),
                .real_name_normalized = try allocator.dupe(u8, "John"),
                .display_name = try allocator.dupe(u8, "John"),
                .display_name_normalized = try allocator.dupe(u8, "John"),
                .avatar_hash = try allocator.dupe(u8, "abc"),
                .email = try allocator.dupe(u8, "john@ex.com"),
                .first_name = try allocator.dupe(u8, "John"),
                .last_name = try allocator.dupe(u8, "Doe"),
                .image_original = try allocator.dupe(u8, "url"),
                .image_24 = try allocator.dupe(u8, "url"),
                .image_32 = try allocator.dupe(u8, "url"),
                .image_48 = try allocator.dupe(u8, "url"),
                .image_72 = try allocator.dupe(u8, "url"),
                .image_192 = try allocator.dupe(u8, "url"),
                .image_512 = try allocator.dupe(u8, "url"),
                .image_1024 = try allocator.dupe(u8, "url"),
                .team = try allocator.dupe(u8, "T1"),
            },
        }
    };
    defer {
        for (users) |u| u.deinit(allocator);
    }

    try exporter.writeUsers(&users);
    
    const channels = [_]models.Channel{
        .{
            .id = try allocator.dupe(u8, "C123"),
            .name = try allocator.dupe(u8, "general"),
            .created = 0,
            .creator = try allocator.dupe(u8, "U123"),
            .members = try allocator.alloc([]const u8, 1),
        }
    };
    channels[0].members[0] = try allocator.dupe(u8, "U123");
    defer {
        for (channels) |c| c.deinit(allocator);
    }

    try exporter.writeChannels(&channels);

    var msgs = [_]models.Message{
        .{
            .user = try allocator.dupe(u8, "U123"),
            .ts = try allocator.dupe(u8, "1755594129.627859"),
            .client_msg_id = try allocator.dupe(u8, "uuid"),
            .text = try allocator.dupe(u8, "hello"),
            .team = try allocator.dupe(u8, "T1"),
            .user_team = try allocator.dupe(u8, "T1"),
            .source_team = try allocator.dupe(u8, "T1"),
            .user_profile = .{
                .avatar_hash = try allocator.dupe(u8, "abc"),
                .image_72 = try allocator.dupe(u8, "url"),
                .first_name = try allocator.dupe(u8, "John"),
                .real_name = try allocator.dupe(u8, "John"),
                .display_name = try allocator.dupe(u8, "John"),
                .team = try allocator.dupe(u8, "T1"),
                .name = try allocator.dupe(u8, "john"),
            },
            .blocks = try allocator.alloc(std.json.Value, 0),
            .channel_id = try allocator.dupe(u8, "C123"),
        }
    };
    defer {
        for (msgs) |m| m.deinit(allocator);
    }

    try exporter.writeMessages(&msgs, &channels);

    try std.fs.cwd().access(test_path ++ "/users.json", .{});
    try std.fs.cwd().access(test_path ++ "/channels.json", .{});
    try std.fs.cwd().access(test_path ++ "/general", .{});
}
