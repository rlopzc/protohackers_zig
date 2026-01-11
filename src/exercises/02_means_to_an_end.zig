const std = @import("std");
const log = std.log.scoped(.means_to_an_end);
const net = std.net;
const mem = std.mem;

const TcpServer = @import("protohackers_zig").TcpServer;
const Client = @import("protohackers_zig").Client;
const Runner = @import("protohackers_zig").Runner;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    while (true) {
        const client = server.accept() catch |err| {
            log.err("failed to accept client err={}", .{err});
            continue;
        };

        const means_to_an_end = try allocator.create(MeansToAnEndRunner);
        means_to_an_end.* = MeansToAnEndRunner.init(allocator);

        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client,
            means_to_an_end.runner(),
        });
        thread.detach();
    }
}

const MeansToAnEndRunner = struct {
    allocator: mem.Allocator,
    prices: std.HashMap(i32, i32, std.hash_map.AutoContext(i32), std.hash_map.default_max_load_percentage),

    fn init(allocator: mem.Allocator) MeansToAnEndRunner {
        return .{
            .allocator = allocator,
            .prices = std.AutoHashMap(i32, i32).init(allocator),
        };
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *MeansToAnEndRunner = @ptrCast(@alignCast(ptr));
        self.prices.deinit();
        self.allocator.destroy(self);
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
            return 9;
        }
    }

    fn callback(ptr: *anyopaque, msg: []const u8, client: *const Client) !void {
        if (msg.len != 9) return;
        const self: *MeansToAnEndRunner = @ptrCast(@alignCast(ptr));
        const prices = &self.prices;
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

        log.debug("op={} first={d} second={d}", .{ op, first, second });

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
            },
            // 'Q' in decimal
            81 => {
                // A query message lets the client query the average price over a given time period.
                // The message format is:
                // Byte:  |  0  |  1     2     3     4  |  5     6     7     8  |
                // Type:  |char |         int32         |         int32         |
                // Value: | 'Q' |        mintime        |        maxtime        |
                //
                // The first int32 is mintime, the earliest timestamp of the period.
                // The second int32 is maxtime, the latest timestamp of the period.
                //
                // The server must compute the mean of the inserted prices with timestamps T, mintime <= T <= maxtime (i.e. timestamps in the closed interval [mintime, maxtime]). If the mean is not an integer, it is acceptable to round either up or down, at the server's discretion.
                // The server must then send the mean to the client as a single int32.
                if (first > second) {
                    log.debug("mintime > maxtime, sending 0s...", .{});
                    try client.write(&mem.zeroes([4]u8));
                    return;
                }

                var count: i32 = 0;
                var total_price: i64 = 0;
                var iterator = prices.iterator();
                while (iterator.next()) |kv| {
                    const key = kv.key_ptr.*;
                    if (first <= key and key <= second) {
                        count += 1;
                        total_price += kv.value_ptr.*;
                    }
                }
                if (count == 0) {
                    log.debug("no prices found, sending 0s...", .{});
                    try client.write(&mem.zeroes([4]u8));
                    return;
                }

                const mean: i32 = @truncate(@divTrunc(total_price, count));
                log.debug("count={d} total_price={d} mean={d}", .{ count, total_price, mean });

                var buf: [4]u8 = undefined;
                mem.writeInt(i32, &buf, mean, .big);
                try client.write(&buf);
            },
            else => {
                log.debug("unknown op={} closing conn...", .{op});
                return Client.Error.CloseConn;
            },
        }
    }

    fn runner(self: *MeansToAnEndRunner) Runner {
        return .{
            .ptr = self,
            .callbackFn = callback,
            .delimiterFinderFn = delimiterFinder,
            .deinitFn = deinit,
        };
    }
};
