const std = @import("std");
const log = std.log.scoped(.mob_in_the_middle);

pub fn main() !void {
    log.debug("hello from zig", .{});
}
