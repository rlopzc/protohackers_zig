const std = @import("std");
const log = std.log;
const net = std.net;

const TcpServer = @import("tcp_server.zig");

pub fn main() !void {
    var server = try TcpServer.start(3000);
    defer server.deinit();

    while (true) {
        const socket = try server.accept();
        const thread = try std.Thread.spawn(.{}, socket_loop, .{socket});
        thread.detach();
    }
}

fn socket_loop(socket: net.Server.Connection) !void {
    log.info("Client {} connected", .{socket.address});
    defer socket.stream.close();

    var buf: [1024]u8 = undefined;
    while (true) {
        const bytes_read = socket.stream.read(&buf) catch break;
        if (bytes_read == 0) break;
        std.debug.print("bytes_read={d} buffer={s}\n", .{ bytes_read, buf });

        try socket.stream.writeAll(&buf);
    }

    log.info("Client {} disconnected", .{socket.address});
}
