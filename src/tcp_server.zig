const std = @import("std");
const log = std.log;
const net = std.net;

const Client = @import("client.zig").Client;

pub const TcpServer = struct {
    server: net.Server,

    pub fn start(port: u16) !TcpServer {
        const address = try net.Address.resolveIp("0.0.0.0", port);

        const server = try address.listen(.{
            .reuse_address = true,
        });
        log.info("Server listening on port {d}", .{address.getPort()});

        return TcpServer{ .server = server };
    }

    pub fn accept(self: *TcpServer) !Client {
        const socket = try self.server.accept();
        return Client{ .socket = socket };
    }

    pub fn deinit(self: *TcpServer) void {
        self.server.deinit();
    }
};
