const std = @import("std");
const log = std.log.scoped(.smoke_test);
const net = std.net;

const TcpServer = @import("protohackers_zig").TcpServer;
const Client = @import("protohackers_zig").Client;
const Runner = @import("protohackers_zig").Runner;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
    defer server.deinit();

    while (true) {
        const client = server.accept() catch |err| {
            log.err("failed to accept client err={}", .{err});
            continue;
        };

        var smoke_test = SmokeTestRunner{};
        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client,
            smoke_test.runner(),
        });
        thread.detach();
    }
}

const SmokeTestRunner = struct {
    fn delimiterFinder(unprocessed: []u8) ?usize {
        if (unprocessed.len != 0) return unprocessed.len;
        return null;
    }

    fn callback(ptr: *anyopaque, msg: []const u8, client: *const Client) !void {
        _ = ptr;
        try client.write(msg);
    }

    fn runner(self: *SmokeTestRunner) Runner {
        return .{
            .ptr = self,
            .callbackFn = callback,
            .delimiterFinderFn = delimiterFinder,
        };
    }
};
