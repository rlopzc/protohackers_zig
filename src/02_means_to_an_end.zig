const std = @import("std");
const log = std.log.scoped(.smoke_test);
const net = std.net;
const mem = std.mem;

const TcpServer = @import("tcp_server.zig").TcpServer;
const Client = @import("client.zig").Client;

var prices: std.HashMap(i32, i32, std.hash_map.AutoContext(i32), std.hash_map.default_max_load_percentage) = undefined;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    prices = std.AutoHashMap(i32, i32).init(gpa.allocator());
    defer prices.deinit();

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
    if (unprocessed.len < 9) {
        return null;
    } else {
        return unprocessed.len;
    }
}

// TODO: shared memory between threads.
// Lock mechanism?
fn callback(msg: []const u8, client: *const Client) !void {
    std.debug.print("bin={b}\nhex={x}\n", .{ msg, msg });
    // The first byte of a message is a character indicating its type. This will be
    // an ASCII uppercase 'I' or 'Q' character, indicating whether the message
    // inserts or queries prices, respectively.
    const op: u8 = msg[0];

    // The next 8 bytes are two signed two's complement 32-bit integers in network
    // byte order (big endian), whose meaning depends on the message type.
    // We'll refer to these numbers as int32, but note this may differ from
    // your system's native int32 type (if any), particularly with regard to
    // byte order.
    const first: i32 = mem.readInt(i32, msg[1..5], .big);
    const second: i32 = mem.readInt(i32, msg[5..9], .big);

    std.debug.print("op={} first={d} second={d}\n", .{ op, first, second });

    switch (op) {
        // 'I' in decimal
        73 => {
            // An insert message lets the client insert a timestamped price.
            // The message format is:
            // Byte:  |  0  |  1     2     3     4  |  5     6     7     8  |
            // Type:  |char |         int32         |         int32         |
            // Value: | 'I' |       timestamp       |         price         |
            //
            // The first int32 is the timestamp, in seconds since 00:00, 1st Jan 1970.
            // The second int32 is the price, in pennies, of this client's asset, at the given timestamp.
            const value = try prices.getOrPut(first);
            if (!value.found_existing) {
                value.value_ptr.* = second;
            }
            std.debug.print("{any}", .{prices});
        },
        // 'Q' in decimal
        81 => {
            try client.write("kaka");
        },
        else => {
            log.debug("unknown op={}", .{op});
        },
    }
}
