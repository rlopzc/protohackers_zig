const std = @import("std");
const log = std.log.scoped(.prime_time);
const net = std.net;
const json = std.json;

const TcpServer = @import("tcp_server.zig").TcpServer;
const Client = @import("client.zig").Client;

pub fn main() !void {
    var server = TcpServer.start(3000) catch std.process.exit(1);
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

const malformed_request: []const u8 = "{}\n";

const Request = struct {
    method: []const u8,
    number: usize,
};

const Response = struct {
    method: []const u8,
    prime: bool,
};

fn callback(msg: []const u8, response_writer: anytype) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var request: Request = undefined;
    if (json.parseFromSlice(Request, gpa.allocator(), msg, .{})) |parsed_json| {
        defer parsed_json.deinit();

        if (!std.mem.eql(u8, parsed_json.value.method, "isPrime")) {
            _ = response_writer.write(malformed_request) catch unreachable;
            return;
        }
        request = parsed_json.value;
    } else |err| {
        log.info("parsing json error={}", .{err});
        _ = response_writer.write(malformed_request) catch unreachable;
        // TODO: Whenever you receive a malformed request, send back a single malformed
        // response, and disconnect the client.
        return;
    }

    const prime = is_prime(request.number);
    const response = Response{
        .method = request.method,
        .prime = prime,
    };

    // https://www.openmymind.net/Writing-Json-To-A-Custom-Output-in-Zig/
    json.stringify(response, .{}, response_writer) catch unreachable;
    _ = response_writer.write("\n") catch unreachable;
}

fn is_prime(number: usize) bool {
    var prime = true;
    var i: usize = 2;
    while (i < number) : (i += 1) {
        if (number % i == 0) {
            prime = false;
            break;
        }
    }

    return prime;
}
