const std = @import("std");
const models = @import("models.zig");
const data = @import("faker_data.zig");

pub const Faker = struct {
    allocator: std.mem.Allocator,
    rand: std.Random,

    pub fn init(allocator: std.mem.Allocator, rand: std.Random) Faker {
        return .{
            .allocator = allocator,
            .rand = rand,
        };
    }

    pub fn generateId(self: *Faker, prefix: u8) [11]u8 {
        var id: [11]u8 = undefined;
        id[0] = prefix;
        const charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        for (1..11) |i| {
            id[i] = charset[self.rand.uintAtMost(usize, charset.len - 1)];
        }
        return id;
    }

    pub fn generateUuid(self: *Faker) [36]u8 {
        var buf: [36]u8 = undefined;
        const hex = "0123456789abcdef";
        for (0..36) |i| {
            if (i == 8 or i == 13 or i == 18 or i == 23) {
                buf[i] = '-';
            } else if (i == 14) {
                buf[i] = '4';
            } else if (i == 19) {
                buf[i] = hex[self.rand.uintAtMost(usize, 3) + 8];
            } else {
                buf[i] = hex[self.rand.uintAtMost(usize, 15)];
            }
        }
        return buf;
    }

    pub fn word(self: *Faker) []const u8 {
        return data.words[self.rand.uintAtMost(usize, data.words.len - 1)];
    }

    pub fn sentence(self: *Faker, min_words: usize, max_words: usize) ![]const u8 {
        const count = self.rand.uintAtMost(usize, max_words - min_words) + min_words;
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(self.allocator);

        for (0..count) |i| {
            const w = self.word();
            if (i == 0) {
                try list.append(self.allocator, std.ascii.toUpper(w[0]));
                try list.appendSlice(self.allocator, w[1..]);
            } else {
                try list.append(self.allocator, ' ');
                try list.appendSlice(self.allocator, w);
            }
        }
        try list.append(self.allocator, '.');
        return list.toOwnedSlice(self.allocator);
    }

    pub fn generateAvatarHash(self: *Faker) [32]u8 {
        var hash: [32]u8 = undefined;
        const hex = "0123456789abcdef";
        for (0..32) |i| {
            hash[i] = hex[self.rand.uintAtMost(usize, 15)];
        }
        return hash;
    }

    pub fn generateUser(self: *Faker, team_id: []const u8) !models.User {
        const is_male = self.rand.boolean();
        const first = if (is_male)
            data.first_names_male[self.rand.uintAtMost(usize, data.first_names_male.len - 1)]
        else
            data.first_names_female[self.rand.uintAtMost(usize, data.first_names_female.len - 1)];
        const last = data.last_names[self.rand.uintAtMost(usize, data.last_names.len - 1)];

        const real_name = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ first, last });
        defer self.allocator.free(real_name);
        const name = try std.ascii.allocLowerString(self.allocator, first);
        defer self.allocator.free(name);
        const email = try std.fmt.allocPrint(self.allocator, "{s}@example.com", .{name});
        const avatar_hash = self.generateAvatarHash();

        const image_base = try std.fmt.allocPrint(self.allocator, "https://secure.gravatar.com/avatar/{s}.jpg?d=identicon", .{avatar_hash});

        const uid = self.generateId('U');
        return models.User{
            .id = try self.allocator.dupe(u8, &uid),
            .team_id = try self.allocator.dupe(u8, team_id),
            .name = try self.allocator.dupe(u8, name),
            .real_name = try self.allocator.dupe(u8, real_name),
            .updated = std.time.timestamp(),
            .profile = .{
                .real_name = try self.allocator.dupe(u8, real_name),
                .real_name_normalized = try self.allocator.dupe(u8, real_name),
                .display_name = try self.allocator.dupe(u8, first),
                .display_name_normalized = try self.allocator.dupe(u8, first),
                .fields = .{ .object = std.json.ObjectMap.init(self.allocator) },
                .status_emoji_display_info = &.{},
                .avatar_hash = try self.allocator.dupe(u8, &avatar_hash),
                .email = email,
                .first_name = try self.allocator.dupe(u8, first),
                .last_name = try self.allocator.dupe(u8, last),
                .image_original = image_base,
                .image_24 = try std.fmt.allocPrint(self.allocator, "{s}&s=24", .{image_base}),
                .image_32 = try std.fmt.allocPrint(self.allocator, "{s}&s=32", .{image_base}),
                .image_48 = try std.fmt.allocPrint(self.allocator, "{s}&s=48", .{image_base}),
                .image_72 = try std.fmt.allocPrint(self.allocator, "{s}&s=72", .{image_base}),
                .image_192 = try std.fmt.allocPrint(self.allocator, "{s}&s=192", .{image_base}),
                .image_512 = try std.fmt.allocPrint(self.allocator, "{s}&s=512", .{image_base}),
                .image_1024 = try std.fmt.allocPrint(self.allocator, "{s}&s=1024", .{image_base}),
                .team = try self.allocator.dupe(u8, team_id),
            },
        };
    }
};

test "faker full test" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0);
    var faker = Faker.init(allocator, prng.random());

    const id = faker.generateId('U');
    try std.testing.expect(id[0] == 'U');
    try std.testing.expect(id.len == 11);

    const s = try faker.sentence(3, 5);
    defer allocator.free(s);
    try std.testing.expect(s[s.len - 1] == '.');

    const user = try faker.generateUser("T012345");
    defer user.deinit(allocator);

    try std.testing.expect(user.id[0] == 'U');
}
