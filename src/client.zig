const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;
const mem = std.mem;

const Reader = @import("buffered_reader.zig").Reader;
const Runner = @import("runner.zig").Runner;

pub const Client = struct {
    socket: net.Server.Connection,

    const Self = @This();
    pub const Error = error{
        CloseConn,
    };

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

    pub fn run(self: Self, runner: Runner) !void {
        log.info("client {} connected", .{self.socket.address});
        defer self.deinit();

        try runner.onConnect(&self);

        var buf: [4096]u8 = undefined;
        var reader = Reader{
            .pos = 0,
            .buf = &buf,
            .stream = self.socket.stream,
            .delimiterFinderFn = runner.delimiterFinderFn,
        };

        while (true) {
            const msg = reader.readMessage() catch break;
            log.info("client={} received={}", .{ self.socket.address, std.zig.fmtEscapes(msg) });
            runner.callback(msg, &self) catch break;
        }

        try runner.onDisconnect(&self);

        log.info("client {} disconnected", .{self.socket.address});
    }
};
