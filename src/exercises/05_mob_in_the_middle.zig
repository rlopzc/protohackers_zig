const std = @import("std");
const log = std.log.scoped(.mob_in_the_middle);
const mvzr = @import("mvzr");
const testing = std.testing;

const TcpServer = @import("protohackers_zig").TcpServer;
const TcpClient = @import("protohackers_zig").TcpClient;
const Client = @import("protohackers_zig").Client;
const Runner = @import("protohackers_zig").Runner;

const UPSTREAM_SERVER = "chat.protohackers.com";
const UPSTREAM_PORT = 16963;

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
            const read_bytes = self.tcp_client.rcv(&buf) catch {
                log.warn("Upstream read error, closing loop", .{});
                break;
            };
            if (read_bytes == 0) break; // connection closed

            log.debug("async rcv from upstream: {f}", .{std.zig.fmtString(buf[0..read_bytes])});

            // Rewrite coin address
            const new_buf = try rewriteCoinAddress(self.allocator, buf[0..read_bytes]);
            defer self.allocator.free(new_buf);

            _ = client.write(new_buf) catch {
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

const TONY_ADDR = "7YWHMfk9JZe0LM0g1ZauHuiSxhI";
fn rewriteCoinAddress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    // We use the max range 35 (1 + 34).
    const regex = mvzr.Regex.compile("7[a-zA-Z0-9]{25,34}").?;
    var iter = regex.iterator(input);
    var last_index: usize = 0;

    while (iter.next()) |match| {
        // 1. Boundary Check: Start
        const preceded_by_space = (match.start == 0 or input[match.start - 1] == ' ');

        // 2. Boundary Check: End
        // We must ensure the character AFTER the match is NOT alphanumeric.
        // If it IS alphanumeric, then the address is actually longer than 35 chars,
        // which means this match is just a prefix and should be ignored.
        const followed_by_boundary = if (match.end == input.len)
            true
        else if (input[match.end] == ' ' or input[match.end] == '\n' or input[match.end] == '\r')
            true
        else
            false;

        // 3. Greedy Check:
        // Did we match the WHOLE alphanumeric block?
        // If the regex matched 26 chars but the 27th is 'b', mvzr might have stopped early.
        // We only accept if the NEXT character in the input isn't a valid address char.
        const is_greedy_match = if (match.end < input.len) !std.ascii.isAlphanumeric(input[match.end]) else true;

        if (preceded_by_space and followed_by_boundary and is_greedy_match) {
            try list.appendSlice(allocator, input[last_index..match.start]);
            try list.appendSlice(allocator, TONY_ADDR);
            last_index = match.end;
        }
    }

    try list.appendSlice(allocator, input[last_index..]);
    return list.toOwnedSlice(allocator);
}

test "ignores if there's no address" {
    testing.log_level = .debug;
    const allocator = testing.allocator;

    const buf = try std.fmt.allocPrint(allocator, "hello\n", .{});
    defer allocator.free(buf);

    const expected = "hello\n";

    const new_buf = try rewriteCoinAddress(allocator, buf);
    defer allocator.free(new_buf);

    try testing.expectEqualStrings(expected, new_buf);
}

test "ignores address if it's too long" {
    testing.log_level = .debug;
    const allocator = testing.allocator;

    const buf = try std.fmt.allocPrint(allocator, "Send the boguscoins to 7aaaaaaaaaaaaaaaaaaaaaaaabbbbbaaaaaaa\n", .{});
    defer allocator.free(buf);

    const expected = "Send the boguscoins to 7aaaaaaaaaaaaaaaaaaaaaaaabbbbbaaaaaaa\n";

    const new_buf = try rewriteCoinAddress(allocator, buf);
    defer allocator.free(new_buf);

    try testing.expectEqualStrings(expected, new_buf);
    try testing.expect(buf.len != new_buf.len);
}

test "rewrites coin address at the end" {
    testing.log_level = .debug;
    const allocator = testing.allocator;

    const buf = try std.fmt.allocPrint(allocator, "Send the boguscoins to 7aaaaaaaaaaaaaaaaaaaaaaaabbbbb\n", .{});
    defer allocator.free(buf);

    const expected = "Send the boguscoins to 7YWHMfk9JZe0LM0g1ZauHuiSxhI\n";

    const new_buf = try rewriteCoinAddress(allocator, buf);
    defer allocator.free(new_buf);

    try testing.expectEqualStrings(expected, new_buf);
    try testing.expectEqual(buf.len, new_buf.len);
}

test "rewrites coin address at the start" {
    testing.log_level = .debug;
    const allocator = testing.allocator;

    const buf = try std.fmt.allocPrint(allocator, "7aaaaaaaaaaaaaaaaaaaaaaaabbbbb is the address\n", .{});
    defer allocator.free(buf);

    const expected = "7YWHMfk9JZe0LM0g1ZauHuiSxhI is the address\n";

    const new_buf = try rewriteCoinAddress(allocator, buf);
    defer allocator.free(new_buf);

    try testing.expectEqualStrings(expected, new_buf);
}

test "rewrites coin address in the middle" {
    testing.log_level = .debug;
    const allocator = testing.allocator;

    const buf = try std.fmt.allocPrint(allocator, "send 7aaaaaaaaaaaaaaaaaaaaaaaabbbbb to the address\n", .{});
    defer allocator.free(buf);

    const expected = "send 7YWHMfk9JZe0LM0g1ZauHuiSxhI to the address\n";

    const new_buf = try rewriteCoinAddress(allocator, buf);
    defer allocator.free(new_buf);

    try testing.expectEqualStrings(expected, new_buf);
}
