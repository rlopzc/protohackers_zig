const std = @import("std");
const log = std.log.scoped(.tcp_server);
const net = std.net;
const mem = std.mem;
const posix = std.posix;

const Client = @import("client.zig").Client;

pub const TcpServer = struct {
    allocator: mem.Allocator,
    server: net.Server,

    const Self = @This();

    pub fn start(allocator: mem.Allocator, port: u16) !Self {
        const address = try net.Address.resolveIp("0.0.0.0", port);

        const server = try address.listen(.{
            .reuse_address = true,
        });
        log.info("Server listening on port {d}", .{address.getPort()});

        return .{
            .allocator = allocator,
            .server = server,
        };
    }

    pub fn accept(self: *Self) !Client {
        const socket = try self.server.accept();

        // Added these two lines (.tv_sec and .tv_usec before zig 0.14.0)
        const timeout = posix.timeval{ .tv_sec = 2, .tv_usec = 500_000 };
        try posix.setsockopt(socket.stream.handle, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
        try posix.setsockopt(socket.stream.handle, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));
        return Client.new(self.allocator, socket);
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }
};
