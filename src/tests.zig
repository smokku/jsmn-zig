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

test "for a empty JSON objects/arrays" {
    try parse("{}", 1, 1, .{.{ Type.OBJECT, 0, 2, 0 }}, false);
    try parse("[]", 1, 1, .{.{ Type.ARRAY, 0, 2, 0 }}, false);
    try parse("[{},{}]", 3, 3, .{ .{ Type.ARRAY, 0, 7, 2 }, .{ Type.OBJECT, 1, 3, 0 }, .{ Type.OBJECT, 4, 6, 0 } }, false);
}

test "for a JSON objects" {
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

test "for a JSON arrays" {
    // FIXME:
    //try parse("[10}", Error.INVAL, 3, .{}, false);
    //try parse("[1,,3]", Error.INVAL, 3);
    try parse("[10]", 2, 2, .{ .{ Type.ARRAY, -1, -1, 1 }, .{ Type.PRIMITIVE, "10" } }, false);
    try parse("{\"a\": 1]", Error.INVAL, 3, .{}, false);
    // FIXME:
    //try parse("[\"a\": 1]", Error.INVAL, 3, .{}, false);
}

test "test primitive JSON data types" {
    try parse("{\"boolVar\" : true }", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "boolVar", 1 }, .{ Type.PRIMITIVE, "true" } }, false);
    try parse("{\"boolVar\" : false }", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "boolVar", 1 }, .{ Type.PRIMITIVE, "false" } }, false);
    try parse("{\"nullVar\" : null }", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "nullVar", 1 }, .{ Type.PRIMITIVE, "null" } }, false);
    try parse("{\"intVar\" : 12}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "intVar", 1 }, .{ Type.PRIMITIVE, "12" } }, false);
    try parse("{\"floatVar\" : 12.345}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "floatVar", 1 }, .{ Type.PRIMITIVE, "12.345" } }, false);
}

test "test string JSON data types" {
    try parse("{\"strVar\" : \"hello world\"}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "strVar", 1 }, .{ Type.STRING, "hello world", 0 } }, false);
    try parse("{\"strVar\" : \"escapes: \\/\\r\\n\\t\\b\\f\\\"\\\\\"}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "strVar", 1 }, .{ Type.STRING, "escapes: \\/\\r\\n\\t\\b\\f\\\"\\\\", 0 } }, false);
    try parse("{\"strVar\": \"\"}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "strVar", 1 }, .{ Type.STRING, "", 0 } }, false);
    try parse("{\"a\":\"\\uAbcD\"}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "a", 1 }, .{ Type.STRING, "\\uAbcD", 0 } }, false);
    try parse("{\"a\":\"str\\u0000\"}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "a", 1 }, .{ Type.STRING, "str\\u0000", 0 } }, false);
    try parse("{\"a\":\"\\uFFFFstr\"}", 3, 3, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "a", 1 }, .{ Type.STRING, "\\uFFFFstr", 0 } }, false);
    try parse("{\"a\":[\"\\u0280\"]}", 4, 4, .{ .{ Type.OBJECT, -1, -1, 1 }, .{ Type.STRING, "a", 1 }, .{ Type.ARRAY, -1, -1, 1 }, .{ Type.STRING, "\\u0280", 0 } }, false);

    try parse("{\"a\":\"str\\uFFGFstr\"}", Error.INVAL, 3, .{}, false);
    try parse("{\"a\":\"str\\u@FfF\"}", Error.INVAL, 3, .{}, false);
    try parse("{{\"a\":[\"\\u028\"]}", Error.INVAL, 4, .{}, false);
}

test "test partial JSON string parsing" {
    //   int r;
    //   unsigned long i;
    //   jsmn_parser p;
    //   jsmntok_t tok[5];
    //   const char *js = "{\"x\": \"va\\\\ue\", \"y\": \"value y\"}";

    //   jsmn_init(&p);
    //   for (i = 1; i <= strlen(js); i++) {
    //     r = jsmn_parse(&p, js, i, tok, sizeof(tok) / sizeof(tok[0], .{}, false);
    //     if (i == strlen(js)) {
    //       try r == 5);
    //       try tokeq(js, tok, 5, Type.OBJECT, -1, -1, 2, Type.STRING, "x", 1,
    //                   Type.STRING, "va\\\\ue", 0, Type.STRING, "y", 1, Type.STRING,
    //                   "value y", 0, .{}, false);
    //     } else {
    //       try r == Error.PART);
    //     }
    //   }
}

test "test partial array reading" {
    //   int r;
    //   unsigned long i;
    //   jsmn_parser p;
    //   jsmntok_t tok[10];
    //   const char *js = "[ 1, true, [123, \"hello\"]]";

    //   jsmn_init(&p);
    //   for (i = 1; i <= strlen(js); i++) {
    //     r = jsmn_parse(&p, js, i, tok, sizeof(tok) / sizeof(tok[0], .{}, true);
    //     if (i == strlen(js)) {
    //       try r == 6);
    //       try tokeq(js, tok, 6, Type.ARRAY, -1, -1, 3, Type.PRIMITIVE, "1",
    //                   Type.PRIMITIVE, "true", Type.ARRAY, -1, -1, 2, Type.PRIMITIVE,
    //                   "123", Type.STRING, "hello", 0, .{}, true);
    //     } else {
    //       try r == Error.PART);
    //     }
    //   }
}

test "test array reading with a smaller number of tokens" {
    //   int i;
    //   int r;
    //   jsmn_parser p;
    //   jsmntok_t toksmall[10], toklarge[10];
    //   const char *js;

    //   js = "  [ 1, true, [123, \"hello\"]]";

    //   for (i = 0; i < 6; i++) {
    //     jsmn_init(&p);
    //     memset(toksmall, 0, sizeof(toksmall, .{}, false);
    //     memset(toklarge, 0, sizeof(toklarge, .{}, false);
    //     r = jsmn_parse(&p, js, strlen(js), toksmall, i);
    //     try r == Error.NOMEM);

    //     memcpy(toklarge, toksmall, sizeof(toksmall, .{}, false);

    //     r = jsmn_parse(&p, js, strlen(js), toklarge, 10);
    //     try r >= 0);
    //     try tokeq(js, toklarge, 4, Type.ARRAY, -1, -1, 3, Type.PRIMITIVE, "1",
    //                 Type.PRIMITIVE, "true", Type.ARRAY, -1, -1, 2, Type.PRIMITIVE,
    //                 "123", Type.STRING, "hello", 0, .{}, false);
    //   }
}

test "test unquoted keys (like in JavaScript)" {
    //   int r;
    //   jsmn_parser p;
    //   jsmntok_t tok[10];
    //   const char *js;

    //   jsmn_init(&p);
    //   js = "key1: \"value\"\nkey2 : 123";

    //   r = jsmn_parse(&p, js, strlen(js), tok, 10);
    //   try r >= 0);
    //   try tokeq(js, tok, 4, Type.PRIMITIVE, "key1", Type.STRING, "value", 0,
    //               Type.PRIMITIVE, "key2", Type.PRIMITIVE, "123", .{}, false);
}

test "test issue #22" {
    //   int r;
    //   jsmn_parser p;
    //   jsmntok_t tokens[128];
    //   const char *js;

    //   js =
    //       "{ \"height\":10, \"layers\":[ { \"data\":[6,6], \"height\":10, "
    //       "\"name\":\"Calque de Tile 1\", \"opacity\":1, \"type\":\"tilelayer\", "
    //       "\"visible\":true, \"width\":10, \"x\":0, \"y\":0 }], "
    //       "\"orientation\":\"orthogonal\", \"properties\": { }, \"tileheight\":32, "
    //       "\"tilesets\":[ { \"firstgid\":1, \"image\":\"..\\/images\\/tiles.png\", "
    //       "\"imageheight\":64, \"imagewidth\":160, \"margin\":0, "
    //       "\"name\":\"Tiles\", "
    //       "\"properties\":{}, \"spacing\":0, \"tileheight\":32, \"tilewidth\":32 "
    //       "}], "
    //       "\"tilewidth\":32, \"version\":1, \"width\":10 }";
    //   jsmn_init(&p);
    //   r = jsmn_parse(&p, js, strlen(js), tokens, 128);
    //   try r >= 0);
}

test "test issue #27" {
    //   const char *js =
    //       "{ \"name\" : \"Jack\", \"age\" : 27 } { \"name\" : \"Anna\", ";
    //   try parse(js, Error.PART, 8, .{}, false);
}

test "test strings that are not null-terminated" {
    //   const char *js;
    //   int r;
    //   jsmn_parser p;
    //   jsmntok_t tokens[10];

    //   js = "{\"a\": 0}garbage";

    //   jsmn_init(&p);
    //   r = jsmn_parse(&p, js, 8, tokens, 10);
    //   try r == 3);
    //   try tokeq(js, tokens, 3, Type.OBJECT, -1, -1, 1, Type.STRING, "a", 1,
    //               Type.PRIMITIVE, "0", .{}, false);
}

test "test tokens count estimation" {
    //   jsmn_parser p;
    //   const char *js;

    //   js = "{}";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 1);

    //   js = "[]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 1);

    //   js = "[[]]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 2);

    //   js = "[[], []]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 3);

    //   js = "[[], []]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 3);

    //   js = "[[], [[]], [[], []]]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 7);

    //   js = "[\"a\", [[], []]]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 5);

    //   js = "[[], \"[], [[]]\", [[]]]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 5);

    //   js = "[1, 2, 3]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 4);

    //   js = "[1, 2, [3, \"a\"], null]";
    //   jsmn_init(&p);
    //   try jsmn_parse(&p, js, strlen(js), NULL, 0) == 7);

}

test "for non-strict mode" {
    var js: []const u8 = "a: 0garbage";
    // try parse(js, 2, 2, .{ .{ Type.PRIMITIVE, "a" }, .{ Type.PRIMITIVE, "0garbage" } }, false);

    js = "Day : 26\nMonth : Sep\n\nYear: 12";
    // try parse(js, 6, 6, .{ .{ Type.PRIMITIVE, "Day" }, .{ Type.PRIMITIVE, "26" }, .{ Type.PRIMITIVE, "Month" }, .{ Type.PRIMITIVE, "Sep" }, .{ Type.PRIMITIVE, "Year" }, .{ Type.PRIMITIVE, "12" } }, false);

    // nested {s don't cause a parse error. */
    js = "\"key {1\": 1234";
    try parse(js, 2, 2, .{ .{ Type.STRING, "key {1", 1 }, .{ Type.PRIMITIVE, "1234" } }, false);
}

test "for unmatched brackets" {
    var js: []const u8 = "\"key 1\": 1234}";
    try parse(js, Error.INVAL, 2, .{}, false);
    js = "{\"key 1\": 1234";
    try parse(js, Error.PART, 3, .{}, false);
    js = "{\"key 1\": 1234}}";
    try parse(js, Error.INVAL, 3, .{}, false);
    js = "\"key 1\"}: 1234";
    try parse(js, Error.INVAL, 3, .{}, false);
    js = "{\"key {1\": 1234}";
    try parse(js, 3, 3, .{ .{ Type.OBJECT, 0, 16, 1 }, .{ Type.STRING, "key {1", 1 }, .{ Type.PRIMITIVE, "1234" } }, false);
    js = "{\"key 1\":{\"key 2\": 1234}";
    try parse(js, Error.PART, 5, .{}, false);
}

test "for key type" {
    var js: []const u8 = "{\"key\": 1}";
    try parse(js, 3, 3, .{ .{ Type.OBJECT, 0, 10, 1 }, .{ Type.STRING, "key", 1 }, .{ Type.PRIMITIVE, "1" } }, false);
    js = "{true: 1}";
    try parse(js, Error.INVAL, 3, .{}, true);
    js = "{1: 1}";
    try parse(js, Error.INVAL, 3, .{}, true);
    js = "{{\"key\": 1}: 2}";
    try parse(js, Error.INVAL, 5, .{}, true);
    js = "{[1,2]: 2}";
    try parse(js, Error.INVAL, 5, .{}, true);
}
