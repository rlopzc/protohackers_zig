const std = @import("std");
const log = std.log.scoped(.prime_time);
const net = std.net;
const json = std.json;

const TcpServer = @import("protohackers_zig").TcpServer;
const Client = @import("protohackers_zig").Client;
const Runner = @import("protohackers_zig").Runner;

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

        var prime_time = PrimeTimeRunner{};
        const thread = try std.Thread.spawn(.{}, Client.run, .{
            client,
            prime_time.runner(),
        });
        thread.detach();
    }
}

const PrimeTimeRunner = struct {
    fn delimiterFinder(unprocessed: []u8) ?usize {
        const index = std.mem.indexOfScalar(u8, unprocessed, '\n');
        if (index != null) {
            return index.? + 1;
        }
        return null;
    }

    fn callback(_: *anyopaque, msg: []const u8, client: *const Client) !void {
        // const self: *SmokeTestRunner = @ptrCast(@alignCast(ptr));
        const request: Request = parseRequest(msg) catch |err| {
            log.err("parse error {}", .{err});
            try client.write(malformed_request);
            return;
        };

        const prime = is_prime(request.number);
        const response = Response{
            .method = request.method,
            .prime = prime,
        };

        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(gpa.allocator());

        // https://www.openmymind.net/Writing-Json-To-A-Custom-Output-in-Zig/
        var writer = buf.writer(gpa.allocator()).adaptToNewApi(&.{}).new_interface;
        try json.Stringify.value(response, .{}, &writer);
        try buf.append(gpa.allocator(), '\n');
        try client.write(buf.items);
    }

    fn runner(self: *PrimeTimeRunner) Runner {
        return .{
            .ptr = self,
            .callbackFn = callback,
            .delimiterFinderFn = delimiterFinder,
        };
    }
};

const malformed_request: []const u8 = "{}\n";

// Unsupported modulo operations for bitwidths > 128 https://github.com/ziglang/zig/issues/1534
const BigNumber = i128;

const Request = struct {
    method: []const u8,
    number: BigNumber,

    const Self = @This();
};

const Response = struct {
    method: []const u8,
    prime: bool,
};

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
            request.number = number.?.integer;
        },
        .float => {
            log.info("got float number {e}", .{number.?.float});
            request.number = @intFromFloat(number.?.float);
        },
        .number_string => {
            log.info("got number_string number {s}", .{number.?.number_string});
            var bigint = try std.math.big.int.Managed.init(allocator);
            defer bigint.deinit();
            try bigint.setString(10, number.?.number_string);
            request.number = try bigint.toInt(BigNumber);
        },
        else => {
            log.info("got number as {?any}", .{number});
            return error.ParseError;
        },
    }

    return request;
}

fn is_prime(number: BigNumber) bool {
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
}
