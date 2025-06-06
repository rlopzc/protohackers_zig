const std = @import("std");
const log = std.log.scoped(.unusual_database);
const posix = std.posix;

const UdpServer = @import("../udp_server.zig").UdpServer;
const Client = @import("../client.zig").Client;

pub fn main() !void {
    var server: UdpServer = try UdpServer.start(3005);
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var keyval = std.StringHashMap([]const u8).init(gpa.allocator());
    defer keyval.deinit();

    var client_addr: posix.sockaddr = undefined;
    var client_addr_len: posix.socklen_t = server.addr.getOsSockLen();
    var buf: [1024]u8 = undefined;

    while (true) {
        const read_bytes: usize = try posix.recvfrom(server.sock, buf[0..], 0, &client_addr, &client_addr_len);
        log.debug("received: {s}", .{buf[0..read_bytes]});

        if (std.mem.indexOfScalar(u8, buf[0..read_bytes], '=')) |pos| {
            // Insert Op
            // TODO: allocation fails put
            try keyval.put(buf[0..pos], buf[(pos + 1)..read_bytes]);
            var it = keyval.iterator();
            while (it.next()) |entry| {
                std.debug.print("[{s} => {s}], ", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            std.debug.print("items: {} \n", .{keyval.count()});
        } else {
            // Retrieve Op
            var resp = try std.mem.concat(gpa.allocator(), u8, &.{ buf[0..read_bytes], "=" });
            defer gpa.allocator().free(resp);

            if (keyval.get(buf[0..read_bytes])) |val| {
                resp = try std.mem.concat(gpa.allocator(), u8, &.{ resp, val });
            }

            log.debug("sending: {s}", .{resp});
            _ = try posix.sendto(server.sock, resp, 0, &client_addr, client_addr_len);
        }
    }
}
