const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;

pub const Client = struct {
    socket: net.Server.Connection,

    const callback = fn (msg: []const u8, socket: *const net.Server.Connection) ?Action;
    pub const Action = enum {
        close_conn,
    };

    pub fn run(self: Client, callback_fn: callback) !void {
        log.info("client {} connected", .{self.socket.address});
        defer self.socket.stream.close();

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        var buffer = try std.ArrayList(u8).initCapacity(gpa.allocator(), 1024);
        defer buffer.deinit();

        while (true) {
            defer buffer.clearRetainingCapacity();
            while (self.socket.stream.reader().readByte()) |byte| {
                if (byte == '\n') {
                    try buffer.append('\n');
                    break;
                }
                try buffer.append(byte);
            } else |err| {
                log.err("client {} error while reading from socket error={}", .{ self.socket.address, err });
            }
            log.info("client {} send bytes={} buffer={s}", .{ self.socket.address, buffer.items.len, buffer.items });

            if (callback_fn(buffer.items, &self.socket)) |action| switch (action) {
                .close_conn => {
                    break;
                },
            };
            log.info("sending {}", .{std.zig.fmtEscapes(buffer.items)});
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
