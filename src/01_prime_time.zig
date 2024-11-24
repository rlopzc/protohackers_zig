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

const Number = union(enum) {
    int: isize,
    big: big_int.Managed,

    const Self = @This();

    fn isBig(self: Self) bool {
        return switch (self) {
            .int => false,
            .big => true,
        };
    }

    fn deinit(self: *Self) void {
        if (self.isBig()) {
            self.big.deinit();
        }
    }
};

const Request = struct {
    method: []const u8,
    number: Number,

    const Self = @This();

    fn deinit(self: *Self) void {
        self.number.deinit();
    }
};

const Response = struct {
    method: []const u8,
    prime: bool,
};

fn callback(msg: []const u8, client: *const Client) !void {
    var request: Request = try parseRequest(msg);
    defer request.deinit();

    const prime = is_prime(request.number);
    const response = Response{
        .method = request.method,
        .prime = prime,
    };

    var buf = std.ArrayList(u8).init(gpa.allocator());
    defer buf.deinit();

    // https://www.openmymind.net/Writing-Json-To-A-Custom-Output-in-Zig/
    try json.stringify(response, .{}, buf.writer());
    try buf.append('\n');
    try client.write(buf.items);
}

const PrimeError = error{
    ParseError,
};

fn parseRequest(msg: []const u8) !Request {
    var request: Request = undefined;
    const parsed_json = try json.parseFromSlice(
        json.Value,
        gpa.allocator(),
        msg,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_json.deinit();

    const method: ?json.Value = parsed_json.value.object.get("method");
    const number: ?json.Value = parsed_json.value.object.get("number");

    if (method == null or number == null) {
        return error.ParseError;
    }

    switch (method.?) {
        .string => {
            if (!std.mem.eql(u8, method.?.string, "isPrime")) {
                return error.ParseError;
            }
            request.method = "isPrime";
        },
        else => {
            return error.ParseError;
        },
    }

    switch (number.?) {
        .integer => {
            log.info("got int number {d}", .{number.?.integer});
            request.number = .{ .int = number.?.integer };
        },
        .float => {
            log.info("got float number {e}", .{number.?.float});
            request.number = .{ .int = @intFromFloat(number.?.float) };
        },
        .number_string => {
            request.number = .{ .big = try big_int.Managed.init(allocator) };
            try request.number.big.setString(10, number.?.number_string);
        },
        else => {
            log.info("got number as {?any}", .{number});
            return error.ParseError;
        },
    }

    return request;
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
