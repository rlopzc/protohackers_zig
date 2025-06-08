const std = @import("std");
const log = std.log.scoped(.tcp_client);
const net = std.net;

pub const TcpClient = struct {
    stream: net.Stream,

    const Self = @This();

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !Self {
        const stream = try net.tcpConnectToHost(allocator, host, port);
        log.debug("connected to {s}:{}", .{ host, port });

        return .{
            .stream = stream,
        };
    }

    pub fn send(self: Self, msg: []const u8) !void {
        _ = try self.stream.write(msg);
    }

    pub fn rcv(self: Self, buf: []u8) !usize {
        return try self.stream.read(buf[0..]);
    }

    pub fn deinit(self: Self) void {
        self.stream.close();
    }
};
