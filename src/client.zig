const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;
const mem = std.mem;

pub const Client = struct {
    allocator: mem.Allocator,
    socket: net.Server.Connection,
    buffer: []u8,

    const Self = @This();

    const callback = fn (msg: []const u8, client: *const Self) ?Action;
    pub const Action = enum {
        close_conn,
    };

    pub fn new(allocator: mem.Allocator, socket: net.Server.Connection) !Self {
        return .{
            .allocator = allocator,
            .socket = socket,
            .buffer = try allocator.alloc(u8, 4096),
        };
    }

    fn read(self: Self) !?[]u8 {
        var buf_reader = std.io.bufferedReader(self.socket.stream.reader());
        var reader = buf_reader.reader();

        const value = try reader.streamUntilDelimiter(self.buffer, '\n');
        log.info("client={} reading={?s}", .{ self.socket.address, value });
        return value;
    }

    pub fn write(self: Self, msg: []const u8) !void {
        var dest = try self.allocator.alloc(u8, msg.len + 1);
        defer self.allocator.free(dest);
        @memcpy(dest[0..msg.len], msg);
        dest[msg.len] = '\n';

        log.info("client={} sending={}", .{ self.socket.address, std.zig.fmtEscapes(dest) });

        var buf_writer = std.io.bufferedWriter(self.socket.stream.writer());
        var writer = buf_writer.writer();

        try writer.writeAll(dest);
        try buf_writer.flush();
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

            if (callback_fn(value, &self)) |action| switch (action) {
                .close_conn => {
                    break;
                },
            };
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
