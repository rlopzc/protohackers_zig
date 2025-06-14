const std = @import("std");
const log = std.log.scoped(.mob_in_the_middle);
const mvzr = @import("mvzr");
const testing = std.testing;

const TcpServer = @import("../tcp_server.zig").TcpServer;
const TcpClient = @import("../tcp_client.zig").TcpClient;
const Client = @import("../client.zig").Client;
const Runner = @import("../runner.zig").Runner;

const UPSTREAM_SERVER = "localhost";
const UPSTREAM_PORT = 3005;

pub fn main() !void {
    var server = try TcpServer.start(3000);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    while (true) {
        const client = try server.accept();

        const mob_in_the_middle = try allocator.create(MobInTheMiddleRunner);
        mob_in_the_middle.* = try MobInTheMiddleRunner.init(allocator);
        const runner = mob_in_the_middle.runner();

        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client, runner,
        });
        thread.detach();
    }
}

// A substring is considered to be a Boguscoin address if it satisfies all of:
// it starts with a "7"
// it consists of at least 26, and at most 35, alphanumeric characters
// it starts at the start of a chat message, or is preceded by a space
// it ends at the end of a chat message, or is followed by a space
// You should rewrite all Boguscoin addresses to Tony's address, which is 7YWHMfk9JZe0LM0g1ZauHuiSxhI.
const BOGUSCOIN_ADDR_REGEX: mvzr.Regex = mvzr.Regex.compile("7[a-zA-Z0-9]{25,35}+").?;
const TONY_ADDR = "7YWHMfk9JZe0LM0g1ZauHuiSxhI";

const MobInTheMiddleRunner = struct {
    allocator: std.mem.Allocator,
    tcp_client: TcpClient = undefined,
    buf: [1024]u8 = undefined,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
        const tcp_client = try TcpClient.connect(allocator, UPSTREAM_SERVER, UPSTREAM_PORT);
        return .{
            .allocator = allocator,
            .tcp_client = tcp_client,
        };
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.tcp_client.deinit();
        self.allocator.destroy(self);
    }

    fn delimiterFinder(unprocessed: []u8) ?usize {
        const index = std.mem.indexOfScalar(u8, unprocessed, '\n');
        if (index != null) {
            return index.? + 1;
        }
        return null;
    }

    fn onConnect(ptr: *anyopaque, client: *const Client) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = try std.Thread.spawn(.{}, Self.upstreamReadLoop, .{ self, client });
    }

    fn callback(ptr: *anyopaque, msg: []const u8, _: *const Client) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.tcp_client.send(msg);
    }

    fn upstreamReadLoop(self: *Self, client: *const Client) !void {
        var buf: [1024]u8 = undefined;

        while (true) {
            var read_bytes = self.tcp_client.rcv(&buf) catch {
                log.warn("Upstream read error, closing loop", .{});
                break;
            };
            if (read_bytes == 0) break; // connection closed

            log.debug("async rcv from upstream: {}", .{std.zig.fmtEscapes(buf[0..read_bytes])});

            // Rewrite coin address
            if (BOGUSCOIN_ADDR_REGEX.match(buf[0..read_bytes])) |match| {
                log.debug("changing address {s}", .{match.slice});
                read_bytes = rewriteCoinAddress(buf[0..read_bytes], match);
            }

            _ = client.write(buf[0..read_bytes]) catch {
                log.warn("Client write error", .{});
                break;
            };
        }
    }

    fn runner(self: *Self) Runner {
        return .{
            .ptr = self,
            .callbackFn = callback,
            .delimiterFinderFn = delimiterFinder,
            .deinitFn = deinit,
            .onConnectFn = onConnect,
        };
    }
};

fn rewriteCoinAddress(buf: []u8, match: mvzr.Match) usize {
    var len = match.start;
    log.debug("\nmatch: {}\n", .{match});
    const end_buff = buf[match.end..];

    log.debug("end_buff len: {d} {}\n", .{ end_buff.len, std.zig.fmtEscapes(end_buff) });

    std.mem.copyForwards(u8, buf[len..][0..TONY_ADDR.len], TONY_ADDR);
    len += TONY_ADDR.len;

    log.debug("buff len: {d} new: {}", .{ len, std.zig.fmtEscapes(buf) });

    std.mem.copyForwards(u8, buf[len..], end_buff);
    len += end_buff.len;

    log.debug("buff len: {d} ult: {}", .{ len, std.zig.fmtEscapes(buf[0..len]) });

    return len;
}

test "rewrites coin adddresses" {
    // testing.log_level = .debug;
    const allocator = testing.allocator;

    const buf = try std.fmt.allocPrint(allocator, "Send the boguscoins to 7aaaaaaaaaaaaaaaaaaaaaaaabbbbb\n", .{});
    defer allocator.free(buf);

    const expected = "Send the boguscoins to 7YWHMfk9JZe0LM0g1ZauHuiSxhI\n";

    const match: mvzr.Match = BOGUSCOIN_ADDR_REGEX.match(buf).?;
    const end_of_new_buf = rewriteCoinAddress(buf, match);

    try testing.expectEqualStrings(expected, buf[0..end_of_new_buf]);
    try testing.expect(buf.len != end_of_new_buf);
}
