const std = @import("std");
const log = std.log.scoped(.client);
const net = std.net;
const mem = std.mem;
const BufferedReader = std.io.BufferedReader(4096, net.Stream.Reader);

const Reader = struct {
    buf: []u8,
    pos: usize = 0,
    start: usize = 0,
    stream: net.Stream,

    const Self = @This();

    fn readMessage(self: *Self) ![]u8 {
        var buf = self.buf;
        // check if there is a message in my buffer, return it
        // if there is no message, read from the socket and leave it unprocessed
        while (true) {
            if (try self.bufferedMessage()) |msg| {
                return msg;
            }

            const pos = self.pos;
            const bytes_read = try self.stream.read(buf[pos..]);
            if (bytes_read == 0) {
                // If we consumed every byte, return error.Closed
                if (self.start == self.pos) {
                    return error.Closed;
                } else {
                    // Otherwise, return the pending items in the buffer
                    const unprocessed = buf[self.start..self.pos];
                    self.pos = self.start;
                    return unprocessed;
                }
            }

            self.pos = pos + bytes_read;
        }
    }

    // Checks if there's a full message in self.buf already.
    // If there isn't, checks that we have enough spare space in self.buf for
    // the next message.
    fn bufferedMessage(self: *Self) !?[]u8 {
        const buf = self.buf;
        // position up to where there's valid data
        const pos = self.pos;
        // start of the next valid message
        const start = self.start;

        std.debug.assert(pos >= start);
        const unprocessed = buf[start..pos];

        // search index of the delimiter
        const delimiter_index = std.mem.indexOfScalar(u8, unprocessed, '\n');
        if (delimiter_index == null) {
            self.ensureSpace(unprocessed.len + 16) catch unreachable;
            return null;
        }

        log.info("buffer={} start={d} pos={d} index={?d}", .{ std.zig.fmtEscapes(buf[0..pos]), start, pos, delimiter_index });

        self.start = start + delimiter_index.? + 1;
        return unprocessed[0..delimiter_index.?];
    }

    fn ensureSpace(self: *Self, space: usize) error{BufferTooSmall}!void {
        const buf = self.buf;
        if (buf.len < space) {
            log.err("buffer to small", .{});
            return error.BufferTooSmall;
        }

        const start = self.start;
        const spare = buf.len - start;
        if (spare >= space) {
            return;
        }

        const pos = self.pos;
        const unprocessed = buf[start..pos];
        std.mem.copyForwards(u8, buf[0..unprocessed.len], unprocessed);

        self.start = 0;
        self.pos = unprocessed.len;
    }
};

pub const Client = struct {
    allocator: mem.Allocator,
    socket: net.Server.Connection,

    const Self = @This();

    const callback = fn (msg: []const u8, client: *const Self) ?Action;
    pub const Action = enum {
        close_conn,
    };

    pub fn new(allocator: mem.Allocator, socket: net.Server.Connection) !Self {
        return .{
            .allocator = allocator,
            .socket = socket,
        };
    }

    pub fn write(self: Self, msg: []const u8) !void {
        var dest = try self.allocator.alloc(u8, msg.len + 1);
        defer self.allocator.free(dest);

        @memcpy(dest[0..msg.len], msg);
        dest[msg.len] = '\n';

        log.info("client={} sending={}", .{ self.socket.address, std.zig.fmtEscapes(dest) });

        _ = try self.socket.stream.write(dest);
    }

    fn deinit(self: Self) void {
        self.socket.stream.close();
    }

    pub fn run(self: Self, callback_fn: callback) !void {
        defer self.deinit();
        log.info("client {} connected", .{self.socket.address});

        var buf: [4096]u8 = undefined;
        var reader = Reader{ .pos = 0, .buf = &buf, .stream = self.socket.stream };

        while (true) {
            const msg = reader.readMessage() catch break;

            if (callback_fn(msg, &self)) |action| switch (action) {
                .close_conn => {
                    break;
                },
            };
        }

        log.info("client {} disconnected", .{self.socket.address});
    }
};
