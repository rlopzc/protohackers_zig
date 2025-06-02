const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;
const mem = std.mem;

const Reader = @import("buffered_reader.zig").Reader;
const Runner = @import("runner.zig").Runner;

pub const Client = struct {
    conn: net.Server.Connection,

    const Self = @This();
    pub const Error = error{
        CloseConn,
    };

    pub fn new(conn: net.Server.Connection) !Self {
        return .{
            .conn = conn,
        };
    }

    pub fn write(self: Self, msg: []const u8) !void {
        // TODO: use buffered writer
        log.info("client={} sending={}", .{ self.conn.address, std.zig.fmtEscapes(msg) });
        _ = try self.conn.stream.writeAll(msg);
    }

    fn deinit(self: Self) void {
        self.conn.stream.close();
    }

    pub fn run(self: Self, runner: Runner) !void {
        log.info("client {} connected", .{self.conn.address});
        defer self.deinit();

        try runner.onConnect(&self);

        var buf: [4096]u8 = undefined;
        var reader = Reader{
            .pos = 0,
            .buf = &buf,
            .stream = self.conn.stream,
            .delimiterFinderFn = runner.delimiterFinderFn,
        };

        while (true) {
            const msg = reader.readMessage() catch break;
            log.info("client={} received={}", .{ self.conn.address, std.zig.fmtEscapes(msg) });
            runner.callback(msg, &self) catch break;
        }

        try runner.onDisconnect(&self);

        log.info("client {} disconnected", .{self.conn.address});
    }
};
