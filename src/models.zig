const std = @import("std");

pub const User = struct {
    id: []const u8,
    team_id: []const u8,
    name: []const u8,
    deleted: bool = false,
    color: []const u8 = "9f69e7",
    real_name: []const u8,
    tz: []const u8 = "Europe/Amsterdam",
    tz_label: []const u8 = "Central European Summer Time",
    tz_offset: i32 = 7200,
    profile: Profile,
    is_admin: bool = false,
    is_owner: bool = false,
    is_primary_owner: bool = false,
    is_restricted: bool = false,
    is_ultra_restricted: bool = false,
    is_bot: bool = false,
    is_app_user: bool = false,
    updated: i64,
    is_email_confirmed: bool = true,
    who_can_share_contact_card: []const u8 = "EVERYONE",

    pub fn deinit(self: User, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.team_id);
        allocator.free(self.name);
        allocator.free(self.real_name);
        self.profile.deinit(allocator);
    }
};

pub const Profile = struct {
    title: []const u8 = "",
    phone: []const u8 = "",
    skype: []const u8 = "",
    real_name: []const u8,
    real_name_normalized: []const u8,
    display_name: []const u8,
    display_name_normalized: []const u8,
    fields: std.json.Value = .null,
    status_text: []const u8 = "",
    status_emoji: []const u8 = "",
    status_emoji_display_info: []const std.json.Value = &.{},
    status_expiration: i64 = 0,
    avatar_hash: []const u8,
    image_original: []const u8,
    is_custom_image: bool = true,
    email: []const u8,
    first_name: []const u8,
    last_name: []const u8 = "",
    image_24: []const u8,
    image_32: []const u8,
    image_48: []const u8,
    image_72: []const u8,
    image_192: []const u8,
    image_512: []const u8,
    image_1024: []const u8,
    status_text_canonical: []const u8 = "",
    team: []const u8,

    pub fn deinit(self: Profile, allocator: std.mem.Allocator) void {
        allocator.free(self.real_name);
        allocator.free(self.real_name_normalized);
        allocator.free(self.display_name);
        allocator.free(self.display_name_normalized);
        // deinit fields if it's an object
        var fields = self.fields;
        switch (fields) {
            .object => |*obj| obj.deinit(),
            else => {},
        }
        allocator.free(self.avatar_hash);
        allocator.free(self.email);
        allocator.free(self.first_name);
        allocator.free(self.last_name);
        allocator.free(self.image_original);
        allocator.free(self.image_24);
        allocator.free(self.image_32);
        allocator.free(self.image_48);
        allocator.free(self.image_72);
        allocator.free(self.image_192);
        allocator.free(self.image_512);
        allocator.free(self.image_1024);
        allocator.free(self.team);
    }
};

pub const Channel = struct {
    id: []const u8,
    name: []const u8,
    created: i64,
    creator: []const u8,
    is_archived: bool = false,
    is_general: bool = false,
    members: [][]const u8,
    topic: TopicPurpose = .{},
    purpose: TopicPurpose = .{},

    pub fn deinit(self: Channel, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.creator);
        for (self.members) |m| allocator.free(m);
        allocator.free(self.members);
    }
};

pub const TopicPurpose = struct {
    value: []const u8 = "",
    creator: []const u8 = "",
    last_set: i64 = 0,
};

pub const Message = struct {
    user: []const u8,
    type: []const u8 = "message",
    ts: []const u8, // Slack uses string decimals "1755594129.627859"
    client_msg_id: []const u8,
    text: []const u8,
    team: []const u8,
    user_team: []const u8,
    source_team: []const u8,
    user_profile: MessageUserProfile,
    blocks: []std.json.Value,
    thread_ts: ?[]const u8 = null,
    parent_user_id: ?[]const u8 = null,
    reply_count: ?u32 = null,
    replies: ?[]ReplyInfo = null,
    latest_reply: ?[]const u8 = null,
    reply_users: ?[][]const u8 = null,
    reply_users_count: ?u32 = null,

    // Internal fields (not for Slack JSON)
    channel_id: ?[]const u8 = null,

    pub fn deinit(self: Message, allocator: std.mem.Allocator) void {
        allocator.free(self.user);
        allocator.free(self.ts);
        allocator.free(self.client_msg_id);
        allocator.free(self.text);
        allocator.free(self.team);
        allocator.free(self.user_team);
        allocator.free(self.source_team);
        self.user_profile.deinit(allocator);
        for (self.blocks) |b| {
            _ = b; // JSON values might need recursive free if they were not parsed with allocator
        }
        allocator.free(self.blocks);
        if (self.thread_ts) |t| allocator.free(t);
        if (self.parent_user_id) |p| allocator.free(p);
        if (self.latest_reply) |t| allocator.free(t);
        if (self.replies) |r| {
            for (r) |rep| {
                allocator.free(rep.user);
                allocator.free(rep.ts);
            }
            allocator.free(r);
        }
        if (self.reply_users) |u| {
            for (u) |user| allocator.free(user);
            allocator.free(u);
        }
        if (self.channel_id) |c| allocator.free(c);
    }
};

pub const MessageUserProfile = struct {
    avatar_hash: []const u8,
    image_72: []const u8,
    first_name: []const u8,
    real_name: []const u8,
    display_name: []const u8,
    team: []const u8,
    name: []const u8,
    is_restricted: bool = false,
    is_ultra_restricted: bool = false,

    pub fn deinit(self: MessageUserProfile, allocator: std.mem.Allocator) void {
        allocator.free(self.avatar_hash);
        allocator.free(self.image_72);
        allocator.free(self.first_name);
        allocator.free(self.real_name);
        allocator.free(self.display_name);
        allocator.free(self.team);
        allocator.free(self.name);
    }
};

pub const ReplyInfo = struct {
    user: []const u8,
    ts: []const u8,
};

test "json serialization - User" {
    const allocator = std.testing.allocator;
    const user = User{
        .id = "U0123456789",
        .team_id = "T0123456789",
        .name = "john.doe",
        .real_name = "John Doe",
        .updated = 1755159475,
        .profile = .{
            .real_name = "John Doe",
            .real_name_normalized = "John Doe",
            .display_name = "John",
            .display_name_normalized = "John",
            .avatar_hash = "d7fcbd23caf0",
            .image_original = "https://example.com/orig.jpg",
            .email = "john@example.com",
            .first_name = "John",
            .image_24 = "https://example.com/24.jpg",
            .image_32 = "https://example.com/32.jpg",
            .image_48 = "https://example.com/48.jpg",
            .image_72 = "https://example.com/72.jpg",
            .image_192 = "https://example.com/192.jpg",
            .image_512 = "https://example.com/512.jpg",
            .image_1024 = "https://example.com/1024.jpg",
            .team = "T0123456789",
        },
    };

    const json_str = try std.json.Stringify.valueAlloc(allocator, user, .{});
    defer allocator.free(json_str);

    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("id") != null);
}
