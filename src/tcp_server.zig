const std = @import("std");
const log = std.log.scoped(.tcp_server);
const net = std.net;
const mem = std.mem;
const posix = std.posix;

const Client = @import("client.zig").Client;

pub const TcpServer = struct {
    server: net.Server,

    const Self = @This();

    pub fn start(port: u16) !Self {
        const address = try net.Address.resolveIp("0.0.0.0", port);

        const server = try address.listen(.{
            .reuse_address = true,
        });
        log.info("Server listening on port {d}", .{address.getPort()});

        return .{
            .server = server,
        };
    }

    pub fn accept(self: *Self) !Client {
        const conn = try self.server.accept();

        const timeout = posix.timeval{ .sec = 20, .usec = 0 };
        try posix.setsockopt(conn.stream.handle, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
        try posix.setsockopt(conn.stream.handle, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));
        return Client.new(conn);
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }
};
