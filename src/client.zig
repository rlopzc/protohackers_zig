const std = @import("std");
const log = std.log;
const net = std.net;

pub const Client = struct {
    socket: net.Server.Connection,

    pub fn run(self: Client, callback: fn (msg: []const u8) []const u8) !void {
        log.info("client {} connected", .{self.socket.address});
        defer self.socket.stream.close();

        var buf: [1024]u8 = undefined;
        while (true) {
            const bytes_read = self.socket.stream.read(&buf) catch |err| {
                log.err("client {} error while reading from socket error={}", .{ self.socket.address, err });
                break;
            };
            if (bytes_read == 0) break;

            log.info("client {} send bytes={d} buffer={s}", .{
                self.socket.address,
                bytes_read,
                buf[0..(bytes_read - 1)],
            });

            const response = callback(buf[0..bytes_read]);

            _ = self.socket.stream.writeAll(response) catch |err| {
                log.err("client {} error while writing to socket error={}", .{ self.socket.address, err });
                break;
            };
            buf = undefined;
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
