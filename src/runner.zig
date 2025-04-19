const std = @import("std");
const Client = @import("client.zig").Client;
const Reader = @import("buffered_reader.zig").Reader;

/// Exercise Runner interface.
/// This allows each exercise to have it's own runner with specific data. For
/// example, smoke_test doesn't need any other data than `*const Client` to
/// work, but means_to_an_end requires one HashMap per client.
pub const Runner = struct {
    ptr: *anyopaque,
    deinitFn: ?*const fn (ptr: *anyopaque) void = null,
    callbackFn: *const fn (ptr: *anyopaque, msg: []const u8, client: *const Client) anyerror!void,
    delimiterFinderFn: Reader.DelimiterFinder,
    onConnectFn: ?*const fn (ptr: *anyopaque, client: *const Client) anyerror!void = null,
    onDisconnectFn: ?*const fn (ptr: *anyopaque, client: *const Client) anyerror!void = null,

    pub fn deinit(self: Runner) void {
        if (self.deinitFn != null) {
            return self.deinitFn.?(self.ptr);
        }
    }

    pub fn callback(self: Runner, msg: []const u8, client: *const Client) !void {
        return self.callbackFn(self.ptr, msg, client);
    }

    pub fn onConnect(self: Runner, client: *const Client) !void {
        std.log.debug("{any}", .{self.onConnectFn});
        if (self.onConnectFn != null) {
            return self.onConnectFn.?(self.ptr, client);
        }
    }

    pub fn onDisconnect(self: Runner, client: *const Client) !void {
        if (self.onDisconnectFn != null) {
            return self.onDisconnectFn.?(self.ptr, client);
        }
    }
};
