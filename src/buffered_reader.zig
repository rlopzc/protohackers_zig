const std = @import("std");
const log = std.log.scoped(.buffered_reader);
const net = std.net;
const mem = std.mem;

pub const Reader = struct {
    buf: []u8,
    pos: usize = 0,
    start: usize = 0,
    stream: net.Stream,
    delimiterFinderFn: DelimiterFinder,

    const Self = @This();
    pub const DelimiterFinder = *const fn (unprocessed: []u8) ?usize;

    pub fn readMessage(self: *Self) ![]u8 {
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
                // If we consumed every byte and there are no pending buffer items, return error.Closed
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
        const delimiter_index = self.delimiterFinderFn(unprocessed);
        if (delimiter_index == null) {
            self.ensureSpace(128) catch unreachable;
            return null;
        }

        // Position start at the start of the next message. We might not have
        // any data for this next message, but we know that it'll start where
        // our last message ended.
        self.start += delimiter_index.?;
        return unprocessed[0..delimiter_index.?];
    }

    fn ensureSpace(self: *Self, space: usize) error{BufferTooSmall}!void {
        const buf = self.buf;
        if (buf.len < space) {
            log.err("buffer to small, space={d}", .{space});
            return error.BufferTooSmall;
        }

        const start = self.start;
        const spare = buf.len - start;
        if (spare >= space) {
            return;
        }

        const unprocessed = buf[start..self.pos];
        std.mem.copyForwards(u8, buf[0..unprocessed.len], unprocessed);

        self.start = 0;
        self.pos = unprocessed.len;
    }
};
