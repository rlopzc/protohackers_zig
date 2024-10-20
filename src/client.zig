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

        var buffer: [1024]u8 = undefined;

        while (true) {
            defer buffer = undefined;
            const bytes_read = try self.socket.stream.read(&buffer);
            if (bytes_read == 0) break;

            log.info("client {} sent bytes={} buffer={}", .{
                self.socket.address,
                bytes_read,
                std.zig.fmtEscapes(buffer[0..bytes_read]),
            });

            if (callback_fn(buffer[0..bytes_read], &self.socket)) |action| switch (action) {
                .close_conn => {
                    break;
                },
            };
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
