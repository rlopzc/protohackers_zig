const std = @import("std");
const log = std.log.scoped(.prime_time);
const net = std.net;
const json = std.json;
const big_int = std.math.big.int;

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

const malformed_request: []const u8 = "{}\n";

const Number = union(enum) {
    int: isize,
    big: big_int.Managed,

    fn isBig(self: Number) bool {
        return switch (self) {
            .int => false,
            .big => true,
        };
    }
};
const Request = struct {
    method: []const u8,
    number: Number,
};

const Response = struct {
    method: []const u8,
    prime: bool,
};

fn callback(msg: []const u8, client: *const Client) ?Client.Action {
    var request: Request = undefined;
    defer {
        if (request.number.isBig()) {
            request.number.big.deinit();
        }
    }

    if (json.parseFromSlice(
        json.Value,
        gpa.allocator(),
        msg,
        .{ .ignore_unknown_fields = true },
    )) |parsed_json| {
        defer parsed_json.deinit();

        if (parsed_json.value.object.get("method")) |method| {
            switch (method) {
                .string => {
                    if (!std.mem.eql(u8, method.string, "isPrime")) {
                        client.write(malformed_request) catch return .close_conn;
                        return null;
                    }
                    request.method = "isPrime";
                },
                else => {
                    client.write(malformed_request) catch return .close_conn;
                    return null;
                },
            }
        } else {
            client.write(malformed_request) catch return .close_conn;
            return null;
        }

        if (parsed_json.value.object.get("number")) |number| {
            switch (number) {
                .integer => {
                    log.info("got int number {d}", .{number.integer});
                    request.number = .{ .int = number.integer };
                },
                .float => {
                    log.info("got float number {e}", .{number.float});
                    request.number = .{ .int = @intFromFloat(number.float) };
                },
                .number_string => {
                    request.number = .{ .big = big_int.Managed.init(allocator) catch unreachable };
                    request.number.big.setString(10, number.number_string) catch unreachable;
                },
                else => {
                    log.info("got number as {any}", .{number});
                    client.write(malformed_request) catch return .close_conn;
                    return null;
                },
            }
        } else {
            client.write(malformed_request) catch return .close_conn;
            return null;
        }
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
    buf.append('\n') catch unreachable;
    client.write(buf.items) catch return .close_conn;
    return null;
}

fn is_prime(n: Number) bool {
    switch (n) {
        .int => |number| {
            if (number <= 1) return false;

            var prime = true;
            var i: isize = 2;
            while (i * i <= number) : (i += 1) {
                if (@rem(number, i) == 0) {
                    prime = false;
                    break;
                }
            }

            return prime;
        },
        .big => |_| {
            n.big.dump();
            return false;
        },
    }
}
