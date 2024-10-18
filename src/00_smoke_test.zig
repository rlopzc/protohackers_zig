const std = @import("std");
const log = std.log;
const net = std.net;

const TcpServer = @import("tcp_server.zig");

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    while (true) {
        const socket = server.accept() catch |err| {
            log.err("failed to accept conn err={}", .{err});
            continue;
        };
        const thread = try std.Thread.spawn(.{}, socket_loop, .{socket});
        thread.detach();
    }
}

fn socket_loop(socket: net.Server.Connection) !void {
    log.info("client {} connected", .{socket.address});
    defer socket.stream.close();

    var buf: [1024]u8 = undefined;
    while (true) {
        const bytes_read = socket.stream.read(&buf) catch |err| {
            log.err("client {} error while reading from socket error={}", .{ socket.address, err });
            break;
        };
        if (bytes_read == 0) break;

        log.info("client {} send bytes={d} bytes={s}", .{
            socket.address,
            bytes_read,
            buf[0..(bytes_read - 1)],
        });

        _ = socket.stream.writeAll(buf[0..bytes_read]) catch |err| {
            log.err("client {} error while writing to socket error={}", .{ socket.address, err });
            break;
        };
        buf = undefined;
    }

    log.info("client {} disconnected", .{socket.address});
}
