# jsmn-zig

[jsmn](https://github.com/zserge/jsmn) JSON parser ported to [Zig](https://ziglang.org).

jsmn (pronounced like 'jasmine') is a minimalistic JSON parser.

You can find more information about JSON format at [json.org][1]

This Zig implementation is a direct port of Serge Zaitsev's <https://github.com/zserge/jsmn>.

## Philosophy

Most JSON parsers offer you a bunch of functions to load JSON data, parse it
and extract any value by its name. jsmn proves that checking the correctness of
every JSON packet or allocating temporary objects to store parsed JSON fields
often is an overkill.

JSON format itself is extremely simple, so why should we complicate it?

jsmn is designed to be **robust** (it should work fine even with erroneous
data), **fast** (it should parse data on the fly), **portable** (no superfluous
dependencies). And of course, **simplicity** is a
key feature - simple code style, simple algorithm, simple integration into
other projects.

## Features

- API contains only 2 functions
- no dynamic memory allocation
- incremental single-pass parsing
- library code is covered with unit-tests

### Serializer

- one function
- uses provided allocator, return string ([]u8)

## Design

The rudimentary jsmn object is a **token**. Let's consider a JSON string:

'{ "name" : "Jack", "age" : 27 }'

It holds the following tokens:

- Object: `{ "name" : "Jack", "age" : 27}` (the whole object)
- Strings: `"name"`, `"Jack"`, `"age"` (keys and some values)
- Number: `27`

In jsmn, tokens do not hold any data, but point to token boundaries in JSON
string instead. In the example above jsmn will create tokens like: Object
[0..31], String [3..7], String [12..16], String [20..23], Number [27..29].

Every jsmn token has a type, which indicates the type of corresponding JSON
token. jsmn supports the following token types:

- Object - a container of key-value pairs, e.g.:
  `{ "foo":"bar", "x":0.3 }`
- Array - a sequence of values, e.g.:
  `[ 1, 2, 3 ]`
- String - a quoted sequence of chars, e.g.: `"foo"`
- Primitive - a number, a boolean (`true`, `false`) or `null`

Besides start/end positions, jsmn tokens for complex types (like arrays
or objects) also contain a number of child items, so you can easily follow
object hierarchy.

This approach provides enough information for parsing any JSON data and makes
it possible to use zero-copy techniques.

## Usage

```
const jsmn = @import("jsmn.zig");
const Parser = jsmn.Parser;
const Token = jsmn.Token;

var parser: Parser = undefined;
var tokens: [128]Token = undefined;

parser.init();
const r = try parser.parse(json, &tokens);

const s = try serialize(&t, js, std.testing.allocator);
```

## API

Token types are described by `jsmntype_t`:

    pub const Type = enum(u8) {
        UNDEFINED = 0,
        OBJECT = 1 << 0,
        ARRAY = 1 << 1,
        STRING = 1 << 2,
        PRIMITIVE = 1 << 3,
    };

**Note:** Unlike JSON data types, primitive tokens are not divided into
numbers, booleans and null, because one can easily tell the type using the
first character:

- <code>'t', 'f'</code> - boolean
- <code>'n'</code> - null
- <code>'-', '0'..'9'</code> - number

Token is an object of `jsmntok_t` type:

    pub const Token = struct {
        typ: Type,     // Token type
        start: isize,  // Token start position
        end: isize,    // Token end position
        size: usize,   // Number of child (nested) tokens
        parent: isize, // Index of containing token
    };

**Note:** string tokens point to the first character after
the opening quote and the previous symbol before final quote. This was made
to simplify string extraction from JSON data.

All job is done by `jsmn.Parser` object. You can initialize a new parser using:

    var parser: Parser = undefined;
    var tokens: [10]Token = undefined;

    parser.init();

    // js - slice of JSON string
    // tokens - an array of tokens available
    // 10 - number of tokens available
    const r = try parser.parse(json, &tokens);

This will create a parser, and then it tries to parse up to 10 JSON tokens from
the `js` string.

Return value of `jsmn_parse` is the number of tokens actually
used by the parser.
Passing `null` instead of the tokens array would not store parsing results, but
instead the function will return the number of tokens needed to parse the given
string. This can be useful if you don't know yet how many tokens to allocate.

If something goes wrong, you will get an error. Error will be one of these:

- `Error.INVAL` - bad token, JSON string is corrupted
- `Error.NOMEM` - not enough tokens, JSON string is too large
- `Error.PART` - JSON string is too short, expecting more JSON data

If you get `Error.NOMEM`, you can re-allocate more tokens and call
`Parser.parse` once more. If you read json data from the stream, you can
periodically call `Parser.parse` and check if return value is `Error.PART`.
You will get this error until you reach the end of JSON data.

## Other info

This software is distributed under [0BSD license](https://opensource.org/licenses/0BSD),
so feel free to integrate it in your commercial products.

[1]: http://www.json.org/
