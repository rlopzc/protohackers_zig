const std = @import("std");
const log = std.log;
const net = std.net;

pub fn start(port: u16) !net.Server {
    const address = try net.Address.resolveIp("0.0.0.0", port);

    const server = try address.listen(.{
        .reuse_address = true,
    });
    log.info("Server listening on port {d}", .{address.getPort()});

    return server;
}
