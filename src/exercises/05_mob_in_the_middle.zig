const std = @import("std");
const log = std.log.scoped(.mob_in_the_middle);

const TcpServer = @import("../tcp_server.zig").TcpServer;
const TcpClient = @import("../tcp_client.zig").TcpClient;
const Client = @import("../client.zig").Client;
const Runner = @import("../runner.zig").Runner;

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
            const n = self.tcp_client.rcv(&buf) catch {
                log.warn("Upstream read error, closing loop", .{});
                break;
            };
            if (n == 0) break; // connection closed

            log.debug("Async rcv from upstream: {}", .{std.zig.fmtEscapes(buf[0..n])});
            _ = client.write(buf[0..n]) catch {
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
