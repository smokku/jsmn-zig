const std = @import("std");
const testing = std.testing;

const jsmn = @import("main.zig");
const Parser = jsmn.Parser;
const Status = jsmn.Error!usize;
const Token = jsmn.Token;
const Type = jsmn.Type;

const ResultToken = std.meta.Tuple(&[_]type{ Type, isize, isize, usize });

fn parse(json: []const u8, status: Status, comptime result: []const ResultToken) anyerror!void {
    var tokens: [result.len]Token = undefined;
    var p: Parser = undefined;

    p.init();
    const r = p.parse(json, &tokens);
    try testing.expectEqual(r, status);

    if (r) |count| {
        try testing.expectEqual(count, try status);
    } else |err| return err;

    for (result) |token, index| {
        try testing.expectEqual(tokens[index].typ, token[0]);
        try testing.expectEqual(tokens[index].start, token[1]);
        try testing.expectEqual(tokens[index].end, token[2]);
        try testing.expectEqual(tokens[index].size, token[3]);
    }
}

test "empty" {
    try parse("{}", 1, &[_]ResultToken{.{ Type.OBJECT, 0, 2, 0 }});
    try parse("[]", 1, &[_]ResultToken{.{ Type.ARRAY, 0, 2, 0 }});
    try parse("[{},{}]", 3, &[_]ResultToken{ .{ Type.ARRAY, 0, 7, 2 }, .{ Type.OBJECT, 1, 3, 0 }, .{ Type.OBJECT, 4, 6, 0 } });
}
