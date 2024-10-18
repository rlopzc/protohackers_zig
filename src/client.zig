const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;

const callback = fn (msg: []const u8, response_writer: anytype) void;

pub const Client = struct {
    socket: net.Server.Connection,

    pub fn run(self: Client, callback_fn: callback) !void {
        log.info("client {} connected", .{self.socket.address});
        defer self.socket.stream.close();

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        var buf: [1024]u8 = undefined;
        var response_buf = std.ArrayList(u8).init(gpa.allocator());
        defer response_buf.deinit();

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

            callback_fn(buf[0..bytes_read], response_buf.writer());

            log.info("sending {}", .{std.zig.fmtEscapes(response_buf.items)});

            self.socket.stream.writeAll(response_buf.items) catch |err| {
                log.err("client {} error while writing to socket error={}", .{ self.socket.address, err });
                break;
            };
            buf = undefined;
            response_buf.clearRetainingCapacity();
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
