const std = @import("std");
const log = std.log.scoped(.mob_in_the_middle);

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

        var mob_in_the_middle = try MobInTheMiddleRunner.init(allocator);
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
        return .{
            .allocator = allocator,
        };
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.tcp_client.deinit();
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
        const tcp_client = try TcpClient.connect(self.allocator, UPSTREAM_SERVER, UPSTREAM_PORT);
        self.tcp_client = tcp_client;

        var ns = try std.time.Timer.start();
        // TODO: check local. Upstream sends a msg, but we read it after tcp server timeout: 20 secs
        const read_bytes = try self.tcp_client.rcv(self.buf[0..]);
        const lapsed = ns.read();
        log.debug("rcv: {s} - afer {}", .{ self.buf[0..read_bytes], lapsed });

        try client.write(self.buf[0..read_bytes]);
    }

    fn callback(ptr: *anyopaque, msg: []const u8, client: *const Client) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.tcp_client.send(msg);

        const read_bytes = try self.tcp_client.rcv(self.buf[0..]);
        try client.write(self.buf[0..read_bytes]);
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
