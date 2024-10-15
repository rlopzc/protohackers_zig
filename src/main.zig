const std = @import("std");
const log = std.log;
const net = std.net;

const smoke_test = @import("01_smoke_test.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    std.debug.print("There are {d} args:\n {s}\n", .{ args.len, args });

    const option = try std.fmt.parseInt(u8, args[1], 10);

    switch (option) {
        0 => {
            std.debug.print("Runnin 0 - Smoke Test", .{});
            try smoke_test.main();
        },
        else => {
            log.err("specify the test to run. i.e. 0, 01, ...", .{});
        },
    }
}
