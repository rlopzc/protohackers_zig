const std = @import("std");
const log = std.log.scoped(.smoke_test);
const net = std.net;

const TcpServer = @import("tcp_server.zig").TcpServer;
const Client = @import("client.zig").Client;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();
    var server = TcpServer.start(allocator, 3000) catch std.process.exit(1);
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
    var dest = allocator.alloc(u8, msg.len + 1) catch unreachable;
    defer allocator.free(dest);

    @memcpy(dest[0..msg.len], msg);

    dest[msg.len] = '\n';

    log.info("sending {}", .{std.zig.fmtEscapes(dest)});

    socket.stream.writeAll(dest) catch unreachable;
    return null;
}
