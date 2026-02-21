const std = @import("std");
const models = @import("models.zig");
const Faker = @import("faker.zig").Faker;

const log = std.log.scoped(.syngen_gen);

pub const Generator = struct {
    allocator: std.mem.Allocator,
    faker: Faker,
    rand: std.Random,

    pub fn init(allocator: std.mem.Allocator, rand: std.Random) Generator {
        return .{
            .allocator = allocator,
            .faker = Faker.init(allocator, rand),
            .rand = rand,
        };
    }

    pub fn randNormal(self: *Generator) f64 {
        var v1: f64 = self.rand.float(f64);
        const v2: f64 = self.rand.float(f64);
        if (v1 < 1e-9) v1 = 1e-9;
        return @sqrt(-2.0 * @log(v1)) * @cos(2.0 * std.math.pi * v2);
    }

    pub fn randGaussianIndex(self: *Generator, max: usize) usize {
        if (max == 0) return 0;
        if (max == 1) return 0;
        const mean = @as(f64, @floatFromInt(max)) / 2.0;
        const sigma = @as(f64, @floatFromInt(max)) / 6.0;
        const val = self.randNormal() * sigma + mean;
        const idx = @as(isize, @intFromFloat(@round(val)));
        if (idx < 0) return 0;
        if (idx >= @as(isize, @intCast(max))) return max - 1;
        return @intCast(idx);
    }

    pub fn generateUsers(self: *Generator, count: usize, team_id: []const u8) ![]models.User {
        var users = try self.allocator.alloc(models.User, count);
        errdefer self.allocator.free(users);
        for (0..count) |i| {
            users[i] = try self.faker.generateUser(team_id);
        }
        return users;
    }

    pub fn generateChannels(self: *Generator, count: usize, users: []const models.User) ![]models.Channel {
        var channels = try self.allocator.alloc(models.Channel, count);
        errdefer self.allocator.free(channels);

        for (0..count) |i| {
            const creator_idx = self.rand.uintAtMost(usize, users.len - 1);
            const channel_name = try self.faker.sentence(1, 2);
            defer self.allocator.free(channel_name);
            
            var name_list: std.ArrayList(u8) = .empty;
            defer name_list.deinit(self.allocator);
            for (channel_name) |c| {
                if (std.ascii.isAlphabetic(c)) {
                    try name_list.append(self.allocator, std.ascii.toLower(c));
                } else if (c == ' ') {
                    try name_list.append(self.allocator, '-');
                }
            }
            if (name_list.items.len > 0 and name_list.items[name_list.items.len-1] == '.') {
                _ = name_list.pop();
            }

            const num_members = self.rand.uintAtMost(usize, users.len / 2) + users.len / 5 + 1;
            const actual_members = @min(num_members, users.len);
            var members = try self.allocator.alloc([]const u8, actual_members);
            
            for (0..actual_members) |m_idx| {
                members[m_idx] = try self.allocator.dupe(u8, users[m_idx].id);
            }

            const cid = self.faker.generateId('C');
            channels[i] = models.Channel{
                .id = try self.allocator.dupe(u8, &cid),
                .name = try name_list.toOwnedSlice(self.allocator),
                .created = std.time.timestamp() - @as(i64, @intCast(self.rand.uintAtMost(u32, 365 * 24 * 3600))),
                .creator = try self.allocator.dupe(u8, users[creator_idx].id),
                .members = members,
            };
        }
        return channels;
    }

    pub fn generateMessages(
        self: *Generator,
        count: usize,
        channels: []const models.Channel,
        users: []const models.User,
        days: usize,
        thread_prob: f64,
    ) ![]models.Message {
        const timer_start = std.time.milliTimestamp();
        const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
        log.info("Generating {d} messages using {d} threads...", .{ count, cpu_count });

        var messages = try self.allocator.alloc(models.Message, count);
        errdefer self.allocator.free(messages);

        const now = std.time.timestamp();
        const start = now - @as(i64, @intCast(days * 24 * 3600));

        // Pass 1: Parallel Generation
        if (cpu_count > 1 and count > 100) {
            var pool: std.Thread.Pool = undefined;
            try pool.init(.{ .allocator = self.allocator, .n_jobs = cpu_count });
            defer pool.deinit();

            const chunk_size = (count + cpu_count - 1) / cpu_count;
            var wg: std.Thread.WaitGroup = .{};

            for (0..cpu_count) |t_idx| {
                const chunk_start = t_idx * chunk_size;
                if (chunk_start >= count) break;
                const chunk_end = @min(chunk_start + chunk_size, count);
                const chunk = messages[chunk_start..chunk_end];

                wg.start();
                try pool.spawn(generateChunk, .{ self, chunk, channels, users, start, days, self.rand.uintAtMost(u64, std.math.maxInt(u64)), &wg });
            }
            pool.waitAndWork(&wg);
        } else {
            // Single-threaded fallback
            var wg: std.Thread.WaitGroup = .{};
            wg.start();
            generateChunk(self, messages, channels, users, start, days, self.rand.uintAtMost(u64, std.math.maxInt(u64)), &wg);
        }

        const gen_done = std.time.milliTimestamp();
        log.info("Data creation took {d}ms", .{gen_done - timer_start});

        // Sort messages by TS
        std.sort.pdq(models.Message, messages, {}, struct {
            fn lessThan(_: void, a: models.Message, b: models.Message) bool {
                return std.mem.lessThan(u8, a.ts, b.ts);
            }
        }.lessThan);

        const sort_done = std.time.milliTimestamp();
        log.info("Sorting took {d}ms", .{sort_done - gen_done});

        // Threading Pass (Sequential)
        log.info("Applying conversation threading...", .{});
        var active_threads = try self.allocator.alloc(?usize, channels.len);
        defer self.allocator.free(active_threads);
        for (active_threads) |*at| at.* = null;

        for (0..count) |i| {
            var ch_idx: ?usize = null;
            for (channels, 0..) |c, idx| {
                if (std.mem.eql(u8, c.id, messages[i].channel_id.?)) {
                    ch_idx = idx;
                    break;
                }
            }
            if (ch_idx == null) continue;

            var made_reply = false;
            if (active_threads[ch_idx.?]) |parent_idx| {
                const parent = &messages[parent_idx];
                const p_ts = try std.fmt.parseFloat(f64, parent.ts);
                const m_ts = try std.fmt.parseFloat(f64, messages[i].ts);
                
                if (m_ts - p_ts < 3 * 24 * 3600 and self.rand.float(f64) < thread_prob) {
                    messages[i].thread_ts = try self.allocator.dupe(u8, parent.ts);
                    messages[i].parent_user_id = try self.allocator.dupe(u8, parent.user);
                    
                    if (parent.reply_count) |rc| {
                        parent.reply_count = rc + 1;
                    } else {
                        parent.reply_count = 1;
                        parent.thread_ts = try self.allocator.dupe(u8, parent.ts);
                        parent.replies = try self.allocator.alloc(models.ReplyInfo, 0);
                        parent.reply_users = try self.allocator.alloc([]const u8, 0);
                    }
                    
                    if (parent.latest_reply) |lr| self.allocator.free(lr);
                    parent.latest_reply = try self.allocator.dupe(u8, messages[i].ts);
                    
                    // Add to replies array
                    var new_replies = try self.allocator.alloc(models.ReplyInfo, parent.replies.?.len + 1);
                    for (parent.replies.?, 0..) |r, r_idx| new_replies[r_idx] = r;
                    new_replies[parent.replies.?.len] = .{
                        .user = try self.allocator.dupe(u8, messages[i].user),
                        .ts = try self.allocator.dupe(u8, messages[i].ts),
                    };
                    self.allocator.free(parent.replies.?);
                    parent.replies = new_replies;

                    // Update reply users
                    var found_user = false;
                    for (parent.reply_users.?) |u| {
                        if (std.mem.eql(u8, u, messages[i].user)) {
                            found_user = true;
                            break;
                        }
                    }
                    if (!found_user) {
                        var new_users = try self.allocator.alloc([]const u8, parent.reply_users.?.len + 1);
                        for (parent.reply_users.?, 0..) |u, u_idx| new_users[u_idx] = u;
                        new_users[parent.reply_users.?.len] = try self.allocator.dupe(u8, messages[i].user);
                        self.allocator.free(parent.reply_users.?);
                        parent.reply_users = new_users;
                        parent.reply_users_count = @intCast(new_users.len);
                    }
                    made_reply = true;
                }
            }

            if (!made_reply and self.rand.float(f64) < 0.2) {
                active_threads[ch_idx.?] = i;
            }
        }

        const total_done = std.time.milliTimestamp();
        log.info("Total message processing took {d}ms", .{total_done - timer_start});

        return messages;
    }

    fn generateChunk(
        self: *Generator,
        chunk: []models.Message,
        channels: []const models.Channel,
        users: []const models.User,
        start: i64,
        days: usize,
        seed: u64,
        wg: *std.Thread.WaitGroup,
    ) void {
        defer wg.finish();
        var prng = std.Random.DefaultPrng.init(seed);
        const rand = prng.random();
        var thread_faker = Faker.init(self.allocator, rand);

        for (0..chunk.len) |i| {
            // Local implementation of Gaussian picking to avoid shared state
            const ch_idx = blk: {
                const max = channels.len;
                if (max <= 1) break :blk 0;
                const mean = @as(f64, @floatFromInt(max)) / 2.0;
                const sigma = @as(f64, @floatFromInt(max)) / 6.0;
                
                // Inline Box-Muller
                var vx1: f64 = rand.float(f64);
                const vx2: f64 = rand.float(f64);
                if (vx1 < 1e-9) vx1 = 1e-9;
                const norm = @sqrt(-2.0 * @log(vx1)) * @cos(2.0 * std.math.pi * vx2);
                
                const val = norm * sigma + mean;
                const idx = @as(isize, @intFromFloat(@round(val)));
                if (idx < 0) break :blk 0;
                if (idx >= @as(isize, @intCast(max))) break :blk max - 1;
                break :blk @as(usize, @intCast(idx));
            };

            const ch = channels[ch_idx];
            const m_idx = rand.uintAtMost(usize, ch.members.len - 1);
            const user_id = ch.members[m_idx];
            
            var user_obj: ?models.User = null;
            for (users) |u| {
                if (std.mem.eql(u8, u.id, user_id)) {
                    user_obj = u;
                    break;
                }
            }
            if (user_obj == null) user_obj = users[0];

            const ts_f = @as(f64, @floatFromInt(start)) + rand.float(f64) * @as(f64, @floatFromInt(days * 24 * 3600));
            const ts_str = std.fmt.allocPrint(self.allocator, "{d:.6}", .{ts_f}) catch unreachable;
            const text = thread_faker.sentence(3, 15) catch unreachable;
            const uuid = thread_faker.generateUuid();

            chunk[i] = models.Message{
                .user = self.allocator.dupe(u8, user_id) catch unreachable,
                .ts = ts_str,
                .client_msg_id = self.allocator.dupe(u8, &uuid) catch unreachable,
                .text = text,
                .team = self.allocator.dupe(u8, user_obj.?.team_id) catch unreachable,
                .user_team = self.allocator.dupe(u8, user_obj.?.team_id) catch unreachable,
                .source_team = self.allocator.dupe(u8, user_obj.?.team_id) catch unreachable,
                .user_profile = .{
                    .avatar_hash = self.allocator.dupe(u8, user_obj.?.profile.avatar_hash) catch unreachable,
                    .image_72 = self.allocator.dupe(u8, user_obj.?.profile.image_72) catch unreachable,
                    .first_name = self.allocator.dupe(u8, user_obj.?.profile.first_name) catch unreachable,
                    .real_name = self.allocator.dupe(u8, user_obj.?.profile.real_name) catch unreachable,
                    .display_name = self.allocator.dupe(u8, user_obj.?.profile.display_name) catch unreachable,
                    .team = self.allocator.dupe(u8, user_obj.?.team_id) catch unreachable,
                    .name = self.allocator.dupe(u8, user_obj.?.name) catch unreachable,
                },
                .blocks = self.allocator.alloc(std.json.Value, 0) catch unreachable,
                .channel_id = self.allocator.dupe(u8, ch.id) catch unreachable,
            };
        }
    }
};

test "generator test" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0);
    var gen = Generator.init(allocator, prng.random());

    const users = try gen.generateUsers(5, "T123");
    defer {
        for (users) |u| u.deinit(allocator);
        allocator.free(users);
    }

    const channels = try gen.generateChannels(2, users);
    defer {
        for (channels) |c| c.deinit(allocator);
        allocator.free(channels);
    }

    const msgs = try gen.generateMessages(10, channels, users, 30, 0.5);
    defer {
        for (msgs) |m| m.deinit(allocator);
        allocator.free(msgs);
    }

    try std.testing.expect(msgs.len == 10);
}
