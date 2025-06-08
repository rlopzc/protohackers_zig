const std = @import("std");
const log = std.log.scoped(.tcp_client);
const net = std.net;

pub const TcpClient = struct {
    stream: net.Stream,

    const Self = @This();

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !Self {
        const stream = try net.tcpConnectToHost(allocator, host, port);

        return .{
            .stream = stream,
        };
    }

    pub fn send(self: Self, msg: []const u8) !void {
        try self.stream.writeAll(msg);
    }

    pub fn deinit(self: Self) !void {
        self.stream.close();
    }
};
