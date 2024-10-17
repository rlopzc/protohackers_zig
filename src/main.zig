const std = @import("std");
const log = std.log;
const net = std.net;
const process = std.process;

const arg_error_msg = "missing argument. specify test to run. i.e. 00, 01, ...";

const smoke_test = @import("01_smoke_test.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try process.argsAlloc(gpa.allocator());
    defer process.argsFree(gpa.allocator(), args);

    log.debug("There are {d} args:\n {s}\n", .{ args.len, args });

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
            log.info("Running 0 - Smoke Test", .{});
            try smoke_test.main();
        },
        else => {
            log.err("test not found, try: 00, 01, ...", .{});
        },
    }
}
