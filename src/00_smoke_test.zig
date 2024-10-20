const std = @import("std");
const log = std.log.scoped(.smoke_test);
const net = std.net;

const TcpServer = @import("tcp_server.zig").TcpServer;
const Client = @import("client.zig").Client;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    while (true) {
        const client = server.accept() catch |err| {
            log.err("failed to accept client err={}", .{err});
            continue;
        };
        const thread = try std.Thread.spawn(.{}, Client.run, .{ client, callback });
        thread.detach();
    }
}

fn callback(msg: []const u8, socket: *const net.Server.Connection) ?Client.Action {
    socket.stream.writeAll(msg) catch unreachable;
    return null;
}
