const std = @import("std");
const log = std.log.scoped(.prime_time);
const net = std.net;
const json = std.json;

const TcpServer = @import("tcp_server.zig").TcpServer;
const Client = @import("client.zig").Client;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();
    var server = TcpServer.start(allocator, 3000) catch std.process.exit(1);
    defer server.deinit();

    while (true) {
        const client = server.accept() catch |err| {
            log.err("failed to accept client err={}", .{err});
            continue;
        };
        const thread = try std.Thread.spawn(.{}, Client.run, .{ client, callback });
        thread.detach();
    }
}

const malformed_request: []const u8 = "{}";

const Request = struct {
    method: []const u8,
    number: f64,
};

const Response = struct {
    method: []const u8,
    prime: bool,
};

fn callback(msg: []const u8, client: *const Client) ?Client.Action {
    var request: Request = undefined;
    if (json.parseFromSlice(
        Request,
        gpa.allocator(),
        msg,
        .{ .ignore_unknown_fields = true },
    )) |parsed_json| {
        defer parsed_json.deinit();

        if (!std.mem.eql(u8, parsed_json.value.method, "isPrime")) {
            client.write(malformed_request) catch return .close_conn;
            return null;
        }
        request = parsed_json.value;
    } else |err| {
        log.info("parsing json error={}", .{err});
        client.write(malformed_request) catch return .close_conn;

        return .close_conn;
    }

    const prime = is_prime(request.number);
    const response = Response{
        .method = request.method,
        .prime = prime,
    };

    var buf = std.ArrayList(u8).init(gpa.allocator());
    defer buf.deinit();

    // https://www.openmymind.net/Writing-Json-To-A-Custom-Output-in-Zig/
    json.stringify(response, .{}, buf.writer()) catch unreachable;
    client.write(buf.items) catch return .close_conn;
    return null;
}

fn is_prime(float: f64) bool {
    const number: isize = @intFromFloat(float);
    if (number <= 1) return false;

    var prime = true;
    var i: isize = 2;
    while (i < number) : (i += 1) {
        if (@rem(number, i) == 0) {
            prime = false;
            break;
        }
    }

    return prime;
}
