const std = @import("std");
const testing = std.testing;

/// JSON type identifier. Basic types are:
///  * Object
///  * Array
///  * String
///  * Other primitive: number, boolean (true/false) or null
pub const Type = enum {
    UNDEFINED,
    OBJECT,
    ARRAY,
    STRING,
    PRIMITIVE,
};

pub const Error = error{
    /// Not enough tokens were provided
    NOMEM,
    /// Invalid character inside JSON string
    INVAL,
    /// The string is not a full JSON packet, more bytes expected
    PART,
};

/// JSON token description.
/// type	type (object, array, string etc.)
/// start	start position in JSON data string
/// end		end position in JSON data string
pub const Token = struct {
    typ: Type,
    start: isize,
    end: isize,
    size: usize,
    parent: isize,

    /// Fills token type and boundaries.
    fn fill(token: *Token, typ: Type, start: isize, end: isize) void {
        token.typ = typ;
        token.start = start;
        token.end = end;
        token.size = 0;
    }
};

/// JSON parser. Contains an array of token blocks available. Also stores
/// the string being parsed now and current position in that string.
pub const Parser = struct {
    strict: bool,

    pos: isize,
    toknext: isize,
    toksuper: isize,

    pub fn init(parser: *Parser) void {
        parser.pos = 0;
        parser.toknext = 0;
        parser.toksuper = -1;
    }

    /// Parse JSON string and fill tokens.
    pub fn parse(parser: *Parser, js: []const u8, tokens: ?[]Token) Error!usize {
        var count = @intCast(usize, parser.toknext);

        while (parser.pos < js.len and js[@intCast(usize, parser.pos)] != 0) : (parser.pos += 1) {
            const c = js[@intCast(usize, parser.pos)];
            switch (c) {
                '{', '[' => {
                    count += 1;
                    if (tokens) |toks| {
                        const token = try parser.allocToken(toks);
                        if (parser.toksuper != -1) {
                            const t = &toks[@intCast(usize, parser.toksuper)];
                            if (parser.strict) {
                                // In strict mode an object or array can't become a key
                                if (t.typ == .OBJECT) {
                                    return Error.INVAL;
                                }
                            }

                            t.size += 1;
                            token.parent = parser.toksuper;
                        }
                        token.typ = if (c == '{') .OBJECT else .ARRAY;
                        token.start = parser.pos;
                        parser.toksuper = parser.toknext - 1;
                    }
                },
                '}', ']' => if (tokens) |toks| {
                    const typ: Type = if (c == '}') .OBJECT else .ARRAY;
                    if (parser.toknext < 1) {
                        return Error.INVAL;
                    }
                    var token = &toks[@intCast(usize, parser.toknext - 1)];
                    while (true) {
                        if (token.start != -1 and token.end == -1) {
                            if (token.typ != typ) {
                                return Error.INVAL;
                            }
                            token.end = parser.pos + 1;
                            parser.toksuper = token.parent;
                            break;
                        }
                        if (token.parent == -1) {
                            if (token.typ != typ or parser.toksuper == -1) {
                                return Error.INVAL;
                            }
                            break;
                        }
                        token = &toks[@intCast(usize, token.parent)];
                    }
                },
                '"' => {
                    try parser.parseString(js, tokens);
                    count += 1;
                    if (parser.toksuper != -1 and tokens != null) {
                        tokens.?[@intCast(usize, parser.toksuper)].size += 1;
                    }
                },
                '\t', '\r', '\n', ' ' => {},
                ':' => {
                    parser.toksuper = parser.toknext - 1;
                },
                ',' => {
                    if (tokens != null and parser.toksuper != -1) {
                        const typ = tokens.?[@intCast(usize, parser.toksuper)].typ;
                        if (typ != .ARRAY and
                            typ != .OBJECT)
                        {
                            parser.toksuper = tokens.?[@intCast(usize, parser.toksuper)].parent;
                        }
                    }
                },
                '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 't', 'f', 'n' => {
                    // In strict mode primitives are: numbers and booleans
                    if (parser.strict) {
                        // And they must not be keys of the object
                        if (tokens != null and parser.toksuper != -1) {
                            const t = &tokens.?[@intCast(usize, parser.toksuper)];
                            if (t.typ == .OBJECT or
                                (t.typ == .STRING and t.size != 0))
                            {
                                return Error.INVAL;
                            }
                        }
                    }
                    try parser.parsePrimitive(js, tokens);
                    count += 1;
                    if (parser.toksuper != -1 and tokens != null) {
                        tokens.?[@intCast(usize, parser.toksuper)].size += 1;
                    }
                },
                else => {
                    if (parser.strict) {
                        // Unexpected char in strict mode
                        return Error.INVAL;
                    } else {
                        try parser.parsePrimitive(js, tokens);
                        count += 1;
                        if (parser.toksuper != -1 and tokens != null) {
                            tokens.?[@intCast(usize, parser.toksuper)].size += 1;
                        }
                    }
                },
            }
        }

        if (tokens) |toks| {
            var i = parser.toknext - 1;
            while (i >= 0) : (i -= 1) {
                // Unmatched opened object or array
                if (toks[@intCast(usize, i)].start != -1 and toks[@intCast(usize, i)].end == -1) {
                    return Error.PART;
                }
            }
        }

        return count;
    }

    /// Fills next available token with JSON primitive.
    fn parsePrimitive(parser: *Parser, js: []const u8, tokens: ?[]Token) Error!void {
        const start = parser.pos;

        found: {
            while (parser.pos < js.len and js[@intCast(usize, parser.pos)] != 0) : (parser.pos += 1) {
                switch (js[@intCast(usize, parser.pos)]) {
                    ':' => {
                        // In strict mode primitive must be followed by "," or "}" or "]"
                        if (!parser.strict) break :found;
                    },
                    '\t', '\r', '\n', ' ', ',', ']', '}' => {
                        break :found;
                    },
                    else => {
                        // quiet pass
                    },
                }
                const char = js[@intCast(usize, parser.pos)];
                if (char < 32 or char >= 127) {
                    parser.pos = start;
                    return Error.INVAL;
                }
            }
            if (parser.strict) {
                // In strict mode primitive must be followed by a comma/object/array
                parser.pos = start;
                return Error.PART;
            }
        }

        if (tokens == null) {
            parser.pos -= 1;
            return;
        }
        const token = parser.allocToken(tokens.?) catch {
            parser.pos = start;
            return Error.NOMEM;
        };
        token.fill(.PRIMITIVE, start, parser.pos);
        token.parent = parser.toksuper;
        parser.pos -= 1;
    }

    /// Fills next token with JSON string.
    fn parseString(parser: *Parser, js: []const u8, tokens: ?[]Token) Error!void {
        const start = parser.pos;

        // Skip starting quote
        parser.pos += 1;

        while (parser.pos < js.len and js[@intCast(usize, parser.pos)] != 0) : (parser.pos += 1) {
            const c = js[@intCast(usize, parser.pos)];

            // Quote: end of string
            if (c == '\"') {
                if (tokens) |toks| {
                    const token = parser.allocToken(toks) catch {
                        parser.pos = start;
                        return Error.NOMEM;
                    };
                    token.fill(.STRING, start + 1, parser.pos);
                    token.parent = parser.toksuper;
                }
                return;
            }

            // Backslash: Quoted symbol expected
            if (c == '\\' and parser.pos + 1 < js.len) {
                parser.pos += 1;
                switch (js[@intCast(usize, parser.pos)]) {
                    // Allowed escaped symbols
                    '\"', '/', '\\', 'b', 'f', 'r', 'n', 't' => {},
                    // Allows escaped symbol \uXXXX
                    'u' => {
                        parser.pos += 1;
                        var i: usize = 0;
                        while (i < 4 and parser.pos < js.len and js[@intCast(usize, parser.pos)] != 0) : (i += 1) {
                            const char = js[@intCast(usize, parser.pos)];
                            // If it isn't a hex character we have an error
                            if (!((char >= 48 and char <= 57) or // 0-9
                                (char >= 65 and char <= 70) or // A-F
                                (char >= 97 and char <= 102)))
                            { // a-f
                                parser.pos = start;
                                return Error.INVAL;
                            }
                            parser.pos += 1;
                        }
                        parser.pos -= 1;
                    },
                    // Unexpected symbol
                    else => {
                        parser.pos = start;
                        return Error.INVAL;
                    },
                }
            }
        }
        parser.pos = start;
        return Error.PART;
    }

    /// Allocates a fresh unused token from the token pool.
    fn allocToken(parser: *Parser, tokens: []Token) Error!*Token {
        if (parser.toknext >= tokens.len) {
            return Error.NOMEM;
        }

        const tok = &tokens[@intCast(usize, parser.toknext)];
        parser.toknext += 1;
        tok.start = -1;
        tok.end = -1;
        tok.size = 0;
        tok.parent = -1;
        return tok;
    }
};

test "example" {
    var parser: Parser = undefined;
    const json =
        \\{ "name" : "Jack", "age" : 27 }
    ;

    // count tokens needed to parse
    parser.init();
    const count = try parser.parse(json, null);
    try testing.expectEqual(count, 5);

    // and parse to tokens
    var tokens: [5]Token = undefined;
    parser.init();
    const r2 = try parser.parse(json, &tokens);
    try testing.expectEqual(r2, 5);
}

fn serializeToken(i: usize, tokens: []const Token, bytes: []const u8, writer: anytype) anyerror!usize {
    const token = &tokens[i];
    var num = token.size;
    var next = i + 1;

    switch (token.typ) {
        .UNDEFINED => unreachable,
        .PRIMITIVE => {
            _ = try writer.write(bytes[@intCast(usize, token.start)..@intCast(usize, token.end)]);
        },
        .STRING => {
            _ = try writer.write("\"");
            _ = try writer.write(bytes[@intCast(usize, token.start)..@intCast(usize, token.end)]);
            _ = try writer.write("\"");

            while (num > 0 and next < tokens.len) : (num -= 1) {
                _ = try writer.write(":");
                next = try serializeToken(next, tokens, bytes, writer);
            }
        },
        .ARRAY => {
            _ = try writer.write("[");
            while (num > 0 and next < tokens.len) : (num -= 1) {
                if (num != token.size)
                    _ = try writer.write(",");
                next = try serializeToken(next, tokens, bytes, writer);
            }
            _ = try writer.write("]");
        },
        .OBJECT => {
            _ = try writer.write("{");
            while (num > 0 and next < tokens.len) : (num -= 1) {
                if (num != token.size)
                    _ = try writer.write(",");
                next = try serializeToken(next, tokens, bytes, writer);
            }
            _ = try writer.write("}");
        },
    }

    return next;
}

/// Writes JSON representation of tokens.
/// caller owns the returned memory
pub fn serialize(tokens: []Token, bytes: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    const writer = out.writer();

    var index: usize = 0;
    while (index < tokens.len) {
        index = try serializeToken(index, tokens, bytes, writer);
    }
    return out.toOwnedSlice();
}

test "serialize" {
    var p: Parser = undefined;
    p.init();
    var t: [10]Token = undefined;
    const js =
        \\{
        \\  "one": "uno",
        \\  "two":     2,
        \\  "three": [   false,    1,"2"]
        \\}
    ;
    const r = try p.parse(js, &t);
    try testing.expectEqual(@as(usize, 10), r);

    // now actually serialize
    const s = try serialize(&t, js, testing.allocator);
    defer testing.allocator.destroy(s.ptr);

    const expected =
        \\{"one":"uno","two":2,"three":[false,1,"2"]}
    ;
    try testing.expectFmt(expected, "{s}", .{s});
}
