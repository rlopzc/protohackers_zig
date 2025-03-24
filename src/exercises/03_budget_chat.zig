const std = @import("std");
const log = std.log.scoped(.smoke_test);
const net = std.net;
const mem = std.mem;

const TcpServer = @import("../tcp_server.zig").TcpServer;
const Client = @import("../client.zig").Client;
const Runner = @import("../runner.zig").Runner;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    while (true) {
        const client = server.accept() catch |err| {
            log.err("failed to accept client err={}", .{err});
            continue;
        };

        var budget_chat = ChatRoom.init(gpa.allocator());
        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client,
            budget_chat.runner(),
        });
        thread.detach();
    }
}

const Username = []const u8;

const UserState = enum { setting_usernamename, chatting };

const User = struct {
    state: UserState,
    username: Username,
};

const ChatRoom = struct {
    allocator: mem.Allocator,
    users: std.HashMap(net.Address, User, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    fn init(allocator: mem.Allocator) ChatRoom {
        return .{
            .allocator = allocator,
            .users = std.StringHashMap(User).init(allocator),
        };
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        defer self.users.deinit();
        // TODO: Deallocate []const u8 usernames
    }

    fn delimiterFinder(_: usize, unprocessed: []u8) ?usize {
        const index = mem.indexOfScalar(u8, unprocessed, '\n');
        if (index != null) {
            return index.? + 1;
        }
        return null;
    }

    fn callback(ptr: *anyopaque, msg: []const u8, client: *const Client) !void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;
        const value = try users.get(client.socket.address);
        if (!value.found_existing) unreachable;

        const user: *User = value.value_ptr;
        switch (user.state) {
            UserState.setting_username => {
                const username = std.mem.Allocator.dupe(self.allocator, []const u8, );
            },
            UserState.chatting => {},
        }
    }

    fn runner(self: *ChatRoom) Runner {
        return .{
            .ptr = self,
            .callbackFn = callback,
            .delimiterFinderFn = delimiterFinder,
            .deinitFn = deinit,
        };
    }
};
