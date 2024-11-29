const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;
const mem = std.mem;
const Reader = @import("./buffered_reader.zig").Reader;

pub const Client = struct {
    socket: net.Server.Connection,

    const Self = @This();
    const callback = fn (msg: []const u8, client: *const Self) anyerror!void;

    pub fn new(socket: net.Server.Connection) !Self {
        return .{
            .socket = socket,
        };
    }

    pub fn write(self: Self, msg: []const u8) !void {
        // TODO: use buffered writer
        log.info("client={} sending={}", .{ self.socket.address, std.zig.fmtEscapes(msg) });
        _ = try self.socket.stream.writeAll(msg);
    }

    fn deinit(self: Self) void {
        self.socket.stream.close();
    }

    pub fn run(
        self: Self,
        callback_fn: callback,
        delimiterFinder: Reader.DelimiterFinder,
    ) !void {
        defer self.deinit();
        log.info("client {} connected", .{self.socket.address});

        var buf: [4096]u8 = undefined;
        var reader = Reader{
            .pos = 0,
            .buf = &buf,
            .stream = self.socket.stream,
            .delimiterFinder = delimiterFinder,
        };

        while (true) {
            const msg = reader.readMessage() catch break;
            log.info("client={} received={}", .{ self.socket.address, std.zig.fmtEscapes(msg) });

            callback_fn(msg, &self) catch |err| switch (err) {
                else => {
                    break;
                },
            };
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
