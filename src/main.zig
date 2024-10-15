const std = @import("std");
const log = std.log;
const net = std.net;

pub fn main() !void {
    const address = try net.Address.resolveIp("127.0.0.1", 3000);

    var server = try address.listen(.{});
    defer server.deinit();
    log.info("Server listening on port {d}", .{address.getPort()});

    while (true) {
        var socket = try server.accept();
        const thread = try std.Thread.spawn(.{}, socket_loop, .{&socket});
        thread.detach();
    }
}

fn socket_loop(socket: *net.Server.Connection) !void {
    log.info("Client {} connected", .{socket.address});
    defer socket.stream.close();

    var buf: [1024]u8 = undefined;
    while (true) {
        const bytes_read = try socket.stream.read(&buf);
        std.debug.print("bytes_read={d} buffer={s}\n", .{ bytes_read, buf });

        if (bytes_read == 0) {
            break;
        }

        try socket.stream.writeAll(&buf);
        // TODO: close the conn properly
    }

    log.info("Client {} disconnected", .{socket.address});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
