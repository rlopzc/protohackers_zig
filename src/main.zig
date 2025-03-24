const std = @import("std");
const log = std.log;
const net = std.net;
const process = std.process;

const arg_error_msg = "missing argument. specify test to run. i.e. 00, 01, ...";

const smoke_test = @import("exercises/00_smoke_test.zig");
const prime_time = @import("exercises/01_prime_time.zig");
const means_to_an_end = @import("exercises/02_means_to_an_end.zig");
const budget_chat = @import("exercises/03_budget_chat.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try process.argsAlloc(gpa.allocator());
    defer process.argsFree(gpa.allocator(), args);

    if (args.len == 1) {
        log.err(arg_error_msg, .{});
        process.exit(1);
    }

    const option = std.fmt.parseInt(u8, args[1], 10) catch {
        log.err(arg_error_msg, .{});
        process.exit(1);
    };

    switch (option) {
        0 => {
            log.info("Running 00 - Smoke Test", .{});
            try smoke_test.main();
        },
        1 => {
            log.info("Running 01 - Prime Time", .{});
            try prime_time.main();
        },
        2 => {
            log.info("Running 02 - Means to an End", .{});
            try means_to_an_end.main();
        },
        3 => {
            log.info("Running 03 - Budget Chat", .{});
            try budget_chat.main();
        },
        else => {
            log.err("test not found, try: 00, 01, ...", .{});
        },
    }
}
