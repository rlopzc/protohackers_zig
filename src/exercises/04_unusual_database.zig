const std = @import("std");
const log = std.log.scoped(.unusual_database);
const posix = std.posix;

const UdpServer = @import("../udp_server.zig").UdpServer;
const Client = @import("../client.zig").Client;
const version: []const u8 = "version=Ken's Key-Value Store 1.0";

pub fn main() !void {
    var server: UdpServer = try UdpServer.start(3000);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();

    var keyval = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = keyval.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        keyval.deinit();
    }

    var client_addr: posix.sockaddr = undefined;
    var client_addr_len: posix.socklen_t = server.addr.getOsSockLen();
    var buf: [1024]u8 = undefined;

    while (true) {
        const read_bytes: usize = try posix.recvfrom(server.sock, buf[0..], 0, &client_addr, &client_addr_len);
        log.debug("received: {s}", .{buf[0..read_bytes]});

        if (std.mem.indexOfScalar(u8, buf[0..read_bytes], '=')) |pos| {
            // Insert Op
            std.debug.print("key: {s} ; val: {s}\n", .{ buf[0..pos], buf[(pos + 1)..read_bytes] });

            const key = try allocator.dupe(u8, buf[0..pos]);
            const val = try allocator.dupe(u8, buf[(pos + 1)..read_bytes]);
            try keyval.put(key, val);

            var it = keyval.iterator();
            while (it.next()) |entry| {
                std.debug.print("[{s} => {s}], ", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            std.debug.print("items: {} \n", .{keyval.count()});
        } else {
            // Retrieve Op
            if (std.mem.eql(u8, "version", buf[0..read_bytes])) {
                _ = try posix.sendto(server.sock, version, 0, &client_addr, client_addr_len);
                continue;
            }

            var resp = try std.mem.concat(allocator, u8, &.{ buf[0..read_bytes], "=" });
            defer allocator.free(resp);

            if (keyval.get(buf[0..read_bytes])) |val| {
                resp = try std.mem.concat(allocator, u8, &.{ resp, val });
            }

            log.debug("sending: {s}", .{resp});
            _ = try posix.sendto(server.sock, resp, 0, &client_addr, client_addr_len);
        }
    }
}
