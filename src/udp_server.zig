const std = @import("std");
const log = std.log.scoped(.udp_server);
const net = std.net;
const posix = std.posix;

const Client = @import("client.zig").Client;

pub const UdpServer = struct {
    sock: posix.socket_t,

    const Self = @This();

    pub fn start(port: u16) !Self {
        const sock: posix.socket_t = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
        const addr: net.Address = try net.Address.parseIp("0.0.0.0", port);
        log.info("Server listening on port {d}", .{addr.getPort()});

        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(sock, &addr.any, addr.getOsSockLen());

        return .{ .sock = sock };
    }

    pub fn deinit(self: *Self) void {
        posix.close(self.sock);
    }
};
