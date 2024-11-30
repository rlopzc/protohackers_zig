const std = @import("std");
const log = std.log.scoped(.smoke_test);
const net = std.net;
const mem = std.mem;

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
        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client,
            callback,
            delimiterFinder,
        });
        thread.detach();
    }
}

// To keep bandwidth usage down, a simple binary format has been specified.
// Each message from a client is 9 bytes long. Clients can send multiple
// messages per connection. Messages are not delimited by newlines or any other
// character: you'll know where one message ends and the next starts because
// they are always 9 bytes.
fn delimiterFinder(unprocessed: []u8) ?usize {
    if (unprocessed.len < 8) {
        return null;
    } else {
        return 9;
    }
}

fn callback(msg: []const u8, client: *const Client) !void {
    std.debug.print("msg={s}\nbin={b}\nhex={x}\n", .{ msg, msg, msg });
    const op: u8 = msg[0];
    const timestamp: i32 = mem.readInt(i32, msg[1..5], .big);
    const price: i32 = mem.readInt(i32, msg[5..9], .big);

    std.debug.print("op={} timestamp={d} price={d}\n", .{ op, timestamp, price });

    try client.write(msg);
}
