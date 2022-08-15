const std = @import("std");
const testing = std.testing;

const jsmn = @import("main.zig");
const Parser = jsmn.Parser;
const Error = jsmn.Error;
const Status = Error!usize;
const Token = jsmn.Token;
const Type = jsmn.Type;

fn parse(json: []const u8, status: Status, comptime numtok: usize, comptime result: anytype, strict: bool) anyerror!void {
    var tokens: [numtok]Token = undefined;
    var p: Parser = undefined;

    p.init();
    p.strict = strict;
    const r = p.parse(json, &tokens);
    try testing.expectEqual(r, status);

    if (r) |count| {
        try testing.expectEqual(count, try status);
    } else |err| {
        try testing.expectError(err, status);
    }

    inline for (result) |res, index| {
        const tk = &tokens[index];
        const typ = res[0];
        try testing.expectEqual(tk.typ, typ);
        switch (typ) {
            Type.UNDEFINED => unreachable,
            Type.OBJECT, Type.ARRAY => {
                if (res[1] != -1 and res[2] != -1) {
                    try testing.expectEqual(tk.start, res[1]);
                    try testing.expectEqual(tk.end, res[2]);
                }
                try testing.expectEqual(tk.size, res[3]);
            },
            Type.STRING, Type.PRIMITIVE => {
                const value = json[@intCast(usize, tk.start)..@intCast(usize, tk.end)];
                try testing.expectEqualSlices(u8, value, res[1]);
                if (typ == Type.STRING)
                    try testing.expectEqual(tk.size, res[2]);
            },
        }
    }
}

test "empty" {
    try parse("{}", 1, 1, .{.{ Type.OBJECT, 0, 2, 0 }}, false);
    try parse("[]", 1, 1, .{.{ Type.ARRAY, 0, 2, 0 }}, false);
    try parse("[{},{}]", 3, 3, .{ .{ Type.ARRAY, 0, 7, 2 }, .{ Type.OBJECT, 1, 3, 0 }, .{ Type.OBJECT, 4, 6, 0 } }, false);
}

test "object" {
    try parse("{\"a\":0}", 3, 3, .{ .{ Type.OBJECT, 0, 7, 1 }, .{ Type.STRING, "a", 1 }, .{ Type.PRIMITIVE, "0" } }, false);
    try parse("{\"a\":[]}", 3, 3, .{ .{ Type.OBJECT, 0, 8, 1 }, .{ Type.STRING, "a", 1 }, .{ Type.ARRAY, 5, 7, 0 } }, false);
    try parse("{\"a\":{},\"b\":{}}", 5, 5, .{ .{ Type.OBJECT, 0, 15, 2 }, .{ Type.STRING, "a", 1 }, .{ Type.OBJECT, -1, -1, 0 }, .{ Type.STRING, "b", 1 }, .{ Type.OBJECT, -1, -1, 0 } }, false);
    try parse("{\n \"Day\": 26,\n \"Month\": 9,\n \"Year\": 12\n }", 7, 7, .{ .{ Type.OBJECT, -1, -1, 3 }, .{ Type.STRING, "Day", 1 }, .{ Type.PRIMITIVE, "26" }, .{ Type.STRING, "Month", 1 }, .{ Type.PRIMITIVE, "9" }, .{ Type.STRING, "Year", 1 }, .{ Type.PRIMITIVE, "12" } }, false);
    try parse("{\"a\": 0, \"b\": \"c\"}", 5, 5, .{ .{ Type.OBJECT, -1, -1, 2 }, .{ Type.STRING, "a", 1 }, .{ Type.PRIMITIVE, "0" }, .{ Type.STRING, "b", 1 }, .{ Type.STRING, "c", 0 } }, false);

    try parse("{\"a\"\n0}", Error.INVAL, 3, .{}, true);
    try parse("{\"a\", 0}", Error.INVAL, 3, .{}, true);
    try parse("{\"a\": {2}}", Error.INVAL, 3, .{}, true);
    try parse("{\"a\": {2: 3}}", Error.INVAL, 3, .{}, true);
    // FIXME:
    // try parse("{\"a\": {\"a\": 2 3}}", Error.INVAL, 5, .{}, true);
    //try parse("{\"a\"}", Error.INVAL, 2);
    //try parse("{\"a\": 1, \"b\"}", Error.INVAL, 4);
    //try parse("{\"a\",\"b\":1}", Error.INVAL, 4);
    //try parse("{\"a\":1,}", Error.INVAL, 4);
    //try parse("{\"a\":\"b\":\"c\"}", Error.INVAL, 4);
    //try parse("{,}", Error.INVAL, 4);
}
