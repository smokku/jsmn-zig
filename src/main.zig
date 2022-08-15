const std = @import("std");
const testing = std.testing;

/// JSON type identifier. Basic types are:
///  * Object
///  * Array
///  * String
///  * Other primitive: number, boolean (true/false) or null
pub const Type = enum(u8) {
    UNDEFINED = 0,
    OBJECT = 1 << 0,
    ARRAY = 1 << 1,
    STRING = 1 << 2,
    PRIMITIVE = 1 << 3,
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
                    if (tokens == null) {
                        continue;
                    }
                    const token = try parser.allocToken(tokens.?);
                    if (parser.toksuper != -1) {
                        const t = &tokens.?[@intCast(usize, parser.toksuper)];
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
                },
                '}', ']' => {
                    if (tokens == null) {
                        continue;
                    }
                    const typ: Type = if (c == '}') .OBJECT else .ARRAY;
                    if (parser.toknext < 1) {
                        return Error.INVAL;
                    }
                    var token = &tokens.?[@intCast(usize, parser.toknext - 1)];
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
                        token = &tokens.?[@intCast(usize, token.parent)];
                    }
                },
                '"' => {
                    const r = try parser.parseString(js, tokens);
                    if (r < 0) {
                        return r;
                    }
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
                    if (tokens != null and parser.toksuper != -1 and
                        tokens.?[@intCast(usize, parser.toksuper)].typ != .ARRAY and
                        tokens.?[@intCast(usize, parser.toksuper)].typ != .OBJECT)
                    {
                        parser.toksuper = tokens.?[@intCast(usize, parser.toksuper)].parent;
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

        if (tokens != null) {
            var i = parser.toknext - 1;
            while (i >= 0) : (i -= 1) {
                // Unmatched opened object or array
                if (tokens.?[@intCast(usize, i)].start != -1 and tokens.?[@intCast(usize, i)].end == -1) {
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
                if (js[@intCast(usize, parser.pos)] < 32 or js[@intCast(usize, parser.pos)] >= 127) {
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
    fn parseString(parser: *Parser, js: []const u8, tokens: ?[]Token) Error!usize {
        const start = parser.pos;

        // Skip starting quote
        parser.pos += 1;

        while (parser.pos < js.len and js[@intCast(usize, parser.pos)] != 0) : (parser.pos += 1) {
            const c = js[@intCast(usize, parser.pos)];

            // Quote: end of string
            if (c == '\"') {
                if (tokens == null) {
                    return 0;
                }
                const token = parser.allocToken(tokens.?) catch {
                    parser.pos = start;
                    return Error.NOMEM;
                };
                token.fill(.STRING, start + 1, parser.pos);
                token.parent = parser.toksuper;
                return 0;
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
                            // If it isn't a hex character we have an error
                            if (!((js[@intCast(usize, parser.pos)] >= 48 and js[@intCast(usize, parser.pos)] <= 57) or // 0-9
                                (js[@intCast(usize, parser.pos)] >= 65 and js[@intCast(usize, parser.pos)] <= 70) or // A-F
                                (js[@intCast(usize, parser.pos)] >= 97 and js[@intCast(usize, parser.pos)] <= 102)))
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
    var t: [128]Token = undefined;
    var p: Parser = undefined;
    const json =
        \\{ "name" : "Jack", "age" : 27 }
    ;

    p.init();
    const r1 = try p.parse(json, null);
    try testing.expectEqual(r1, 5);

    p.init();
    const r2 = try p.parse(json, &t);
    try testing.expectEqual(r2, 5);
}
