const std = @import("std");
const log = std.log.scoped(.speed_daemon);
const testing = std.testing;

// 0x10: Error (Server->Client)
const Error = struct {
    msg: []const u8,
};
// 0x20: Plate (Client->Server)
const Plate = struct {
    plate: []const u8,
    timestamp: u32,
};
// 0x21: Ticket (Server->Client)
const Ticket = struct {
    plate: []const u8,
    road: u16,
    mile1: u16,
    timestamp1: u32,
    mile2: u16,
    timestamp2: u32,
    speed: u16,
};
// 0x40: WantHeartbeat (Client->Server)
const WantHeartbeat = struct {
    interval: u32,
};
// 0x41: Heartbeat (Server->Client)
const Heartbeat = struct {};
// 0x80: IAmCamera (Client->Server)
const IAmCamera = struct {
    road: u16,
    mile: u16,
    limit: u16,
};
// 0x81: IAmDispatcher (Client->Server)
const IAmDispatcher = struct {
    numroads: u8,
    roads: []u16,
};

// Messages
const ClientMsg = union(enum) {
    plate: Plate,
    want_heartbeat: WantHeartbeat,
    i_am_camera: IAmCamera,
    i_am_dispatcher: IAmDispatcher,
};
const ServerMsg = union(enum) {
    err: Error,
    ticket: Ticket,
    heartbeat: Heartbeat,
};
