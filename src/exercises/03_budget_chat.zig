const std = @import("std");
const log = std.log.scoped(.budget_chat);
const net = std.net;
const mem = std.mem;
const mvzr = @import("mvzr");

const TcpServer = @import("../tcp_server.zig").TcpServer;
const Client = @import("../client.zig").Client;
const Runner = @import("../runner.zig").Runner;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var budget_chat = ChatRoom.init(gpa.allocator());
    var runner = budget_chat.runner();
    defer runner.deinit();

    while (true) {
        const client = server.accept() catch |err| {
            log.err("failed to accept client err={}", .{err});
            continue;
        };

        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client,
            runner,
        });
        thread.detach();
    }
}

const Username = []const u8;

const UserState = enum {
    setting_username,
    chatting,
};

const User = struct {
    state: UserState,
    username: Username,
    client: *const Client,

    const Self = @This();

    fn isChatting(self: Self) bool {
        return self.state == .chatting;
    }
};

// The first message from a client sets the user's name, which must contain at
// least 1 character, and must consist entirely of alphanumeric characters
// (uppercase, lowercase, and digits).
// Implementations may limit the maximum length of a name, but must allow at
// least 16 characters.
const username_regex: mvzr.Regex = mvzr.Regex.compile("^[a-zA-Z0-9]{1,}$").?;

const ChatRoom = struct {
    allocator: mem.Allocator,
    users: std.HashMap(
        net.Address,
        User,
        AddressContext,
        std.hash_map.default_max_load_percentage,
    ),

    const Self = @This();

    fn printUsers(self: Self) void {
        std.debug.print("users: ", .{});
        var it = self.users.iterator();
        while (it.next()) |entry| {
            std.debug.print("[{}: {s}], ", .{ entry.key_ptr.*, entry.value_ptr.username });
        }
        std.debug.print("\n", .{});
    }

    fn init(allocator: mem.Allocator) ChatRoom {
        return .{
            .allocator = allocator,
            .users = std.HashMap(
                net.Address,
                User,
                AddressContext,
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
        };
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;
        var it = users.valueIterator();
        while (it.next()) |value_ptr| {
            self.allocator.free(value_ptr.username);
        }

        self.users.deinit();
    }

    fn delimiterFinder(unprocessed: []u8) ?usize {
        const index = mem.indexOfScalar(u8, unprocessed, '\n');
        if (index != null) {
            return index.? + 1;
        }
        return null;
    }

    fn onConnect(ptr: *anyopaque, client: *const Client) !void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;
        try users.put(client.socket.address, User{
            .state = .setting_username,
            .username = undefined,
            .client = client,
        });
        try client.write("Welcome to the chat! What's your username?\n");
    }

    fn onDisconnect(ptr: *anyopaque, client: *const Client) !void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;
        const removed = users.fetchRemove(client.socket.address);

        if (removed) |entry| try self.notifyDisconnectedUser(entry.value);
    }

    fn notifyDisconnectedUser(self: Self, disconnected_user: User) !void {
        if (disconnected_user.username.len == 0) return;
        const disconnected_user_msg = try std.fmt.allocPrint(self.allocator, "* {s} has left the room\n", .{disconnected_user.username});
        defer self.allocator.free(disconnected_user_msg);

        log.debug("{s} removed", .{disconnected_user.username});

        var it = self.users.valueIterator();
        while (it.next()) |user| {
            if (user.isChatting()) {
                try user.client.write(disconnected_user_msg);
            }
        }
    }

    fn notifyNewUser(self: Self, new_user: *User) !void {
        const users = &self.users;
        const new_user_msg: []const u8 = try std.fmt.allocPrint(self.allocator, "* {s} has entered the room\n", .{new_user.username});
        defer self.allocator.free(new_user_msg);

        // notify who is in the room
        var users_in_room_msg: []u8 = try std.fmt.allocPrint(self.allocator, "* The room contains: ", .{});
        defer self.allocator.free(users_in_room_msg);

        var it = users.iterator();
        while (it.next()) |entry| {
            if (!entry.key_ptr.eql(new_user.client.socket.address) and entry.value_ptr.isChatting()) {
                try entry.value_ptr.client.write(new_user_msg);
                users_in_room_msg = try std.fmt.allocPrint(self.allocator, "{s} {s},", .{ users_in_room_msg, entry.value_ptr.username });
            }
        }

        users_in_room_msg[users_in_room_msg.len - 1] = '\n';
        try new_user.client.write(users_in_room_msg);
    }

    fn callback(ptr: *anyopaque, msg: []const u8, client: *const Client) !void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;

        const user: *User = users.getPtr(client.socket.address) orelse unreachable;

        switch (user.state) {
            UserState.setting_username => {
                var username = std.mem.trimRight(u8, msg, "\r\n");
                username = username[0..@min(username.len, 20)];
                if (!username_regex.isMatch(username)) {
                    // username invalid, remove from users
                    const removed = users.remove(client.socket.address);
                    std.log.debug("user with IP {any} removed {}", .{client.socket.address, removed});
                    return Client.Error.CloseConn;
                }

                user.username = try self.allocator.dupe(u8, username);
                user.state = .chatting;

                std.log.debug("set username: {s}", .{user.username});

                try self.notifyNewUser(user);
            },
            UserState.chatting => {
                const chatMsg: []const u8 = try std.fmt.allocPrint(self.allocator, "[{s}] {s}", .{ user.username, msg });
                defer self.allocator.free(chatMsg);

                var it = users.iterator();
                while (it.next()) |entry| {
                    if (!entry.key_ptr.eql(client.socket.address) and entry.value_ptr.isChatting()) {
                        try entry.value_ptr.client.write(chatMsg);
                    }
                }
            },
        }
    }

    fn runner(self: *ChatRoom) Runner {
        return .{
            .ptr = self,
            .callbackFn = callback,
            .delimiterFinderFn = delimiterFinder,
            .deinitFn = deinit,
            .onConnectFn = onConnect,
            .onDisconnectFn = onDisconnect,
        };
    }
};

const AddressContext = struct {
    pub fn hash(_: AddressContext, address: net.Address) u64 {
        var h = std.hash.Wyhash.init(0);

        const bytes = @as([*]const u8, @ptrCast(&address.any))[0..address.getOsSockLen()];
        h.update(bytes);

        return h.final();
    }

    pub fn eql(_: AddressContext, a: net.Address, b: net.Address) bool {
        return net.Address.eql(a, b);
    }
};
