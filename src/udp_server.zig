const std = @import("std");
const net = std.net;
const posix = std.posix;

const Client = @import("client.zig").Client;

pub const UdpServer = struct {
    sock: posix.socket_t,

    const Self = @This();

    pub fn start(port: u16) !Self {
        const sock: posix.socket_t = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
        const addr: net.Address = try net.Address.parseIp("0.0.0.0", port);

        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(sock, &addr.any, addr.getOsSockLen());
        try posix.listen(sock, 128);

        return .{ .sock = sock };
    }

    pub fn accept(self: Self) !Client {
        var client_addr: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);

        const client_sock: posix.socket_t = try posix.accept(self.sock, &client_addr.any, &client_address_len, 0);
        const stream = net.Stream{ .handle = client_sock };
        const conn = net.Server.Connection{ .stream = stream, .address = client_addr };

        return Client.new(conn);
    }

    pub fn deinit(self: Self) void {
        posix.close(self.sock);
    }
};
