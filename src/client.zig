const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;
const mem = std.mem;

pub const Client = struct {
    allocator: mem.Allocator,
    socket: net.Server.Connection,
    buffer: []u8,

    const Self = @This();

    const callback = fn (msg: []const u8, socket: *const net.Server.Connection) ?Action;
    pub const Action = enum {
        close_conn,
    };

    pub fn new(allocator: mem.Allocator, socket: net.Server.Connection) !Self {
        return .{
            .allocator = allocator,
            .socket = socket,
            .buffer = try allocator.alloc(u8, 1024),
        };
    }

    fn read(self: Self) !?[]u8 {
        const value = try self.socket.stream.reader().readUntilDelimiterOrEof(self.buffer, '\n');
        return value;
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.buffer);
        self.socket.stream.close();
    }

    pub fn run(self: Self, callback_fn: callback) !void {
        defer self.deinit();
        log.info("client {} connected", .{self.socket.address});

        while (true) {
            const value = try self.read() orelse break;

            if (callback_fn(value, &self.socket)) |action| switch (action) {
                .close_conn => {
                    break;
                },
            };
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
