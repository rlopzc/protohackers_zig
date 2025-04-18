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
};

const ChatRoom = struct {
    allocator: mem.Allocator,
    users: std.HashMap(net.Address, User, AddressContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    fn printUsers(self: Self) void {
        var it = self.users.iterator();
        log.debug("Users:", .{});
        while (it.next()) |entry| {
            log.debug("{}: [{s}]", .{ entry.key_ptr.*, entry.value_ptr.username });
        }
    }

    fn init(allocator: mem.Allocator) ChatRoom {
        return .{
            .allocator = allocator,
            .users = std.HashMap(net.Address, User, AddressContext, std.hash_map.default_max_load_percentage).init(allocator),
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
        });
        try client.write("Welcome to the chat! What's your username?\n");
    }

    fn onDisconnect(ptr: *anyopaque, client: *const Client) !void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;
        const removed = users.fetchRemove(client.socket.address);

        if (removed) |user| {
            log.debug("{s} removed", .{user.value.username});
        }
    }

    fn callback(ptr: *anyopaque, msg: []const u8, client: *const Client) !void {
        const self: *ChatRoom = @ptrCast(@alignCast(ptr));
        const users = &self.users;

        const user: *User = users.getPtr(client.socket.address) orelse unreachable;

        switch (user.state) {
            UserState.setting_username => {
                const username = std.mem.trimRight(u8, msg, "\r\n");
                user.username = try self.allocator.dupe(u8, username);
                user.state = .chatting;
                self.printUsers();
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
            .onConnectFn = onConnect,
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
