// zigdragon.zig
// Author: Riley Mann
//
// using Zig version 0.16.0
//
// try `zig run zigdragon.zig -- -h`
//
// Created on 18 Jul 2026

const std = @import("std");

const help_message =
    \\Usage: zigdragon [-fm] [-s/--style <style>] [-n <iteration>]...
    \\
    \\zigdragon is a Heighway curve generator.
    \\
    \\Drawing Styles:
    \\  none        no drawing
    \\  arcs        utf-8 light box characters with rounded corners
    \\  ascii       plain ascii using the [--brush] character
    \\  box         (default) utf-8 light box drawing characters
    \\  braille     utf-8 braille patterns
    \\  doublebox   utf-8 double box drawing characters
    \\  halfblocks  utf-8 half-blocks
    \\  heavybox    utf-8 heavy box drawing characters
    \\  quadrants   utf-8 block quadrants
    \\
    \\Options:
    \\  -f, --folds                 Print the sequence of folds
    \\  -m, --mirror                Generate a right instead of left-handed curve
    \\  -s, --style <style>         Drawing style (see the styles listed above)
    \\  -n <iteration>              Number of iterations the pattern is folded,
    \\                              iteration < 24 (default: 10)
    \\  -x, --scale <len>           Segment length between each fold (default: 1)
    \\  -d, --direction <heading>   Cardinal direction to start the curve with
    \\                              e.g. N, S, E, W (default: S)
    \\  -b, --brush <char>          Ascii character to draw with in 'ascii' style
    \\                              (default: '#')
    \\  -h, --help                  Show help
    \\
;
const n_limit = 23; // Limit the fractal to ~8M folds
const canvas_limit = 16_777_216; // canvas limit in bytes

// Enum representing the fractal drawing styles
// These field names are used to generate the valid CLI options
const DrawingStyle = enum {
    none,
    arcs,
    ascii,
    box,
    braille,
    doublebox,
    halfblocks,
    heavybox,
    quadrants,
};

// Cardinal directions are useful for drawing and orienting the fractal
const Cardinal = enum(u2) {
    east,
    north,
    west,
    south,

    // Method that returns the rotated cardinal direction (positive: E->N->W->S->E)
    fn rotated(self: @This(), by: i32) @This() {
        var heading: u2 = @intFromEnum(self);
        heading +%= @as(u2, @intCast(@mod(by, 4)));
        return @enumFromInt(heading);
    }
};

// CLI arguments are parsed using this struct's field names
// Argument patterns are seperated by ' ', ',', '/' or '|'
// Single characters without hyphens are used for parsing grouped flags (e.g. '-fm')
// Each field needs a default value
const Arguments = struct {
    @"f --folds": bool = false,           // print the sequence of folds
    @"m --mirror": bool = false,          // generate a right instead of left-handed curve
    @"-s --style": DrawingStyle = .box,
    @"-n": u32 = 10,                      // number of iterations the pattern is folded
    @"-x --scale": u32 = 1,               // segment length between each fold
    @"-d --direction": Cardinal = .south, // cardinal direction to start the curve with
    @"-b --brush": u8 = '#',              // ascii character to draw with in 'ascii' style
    @"-h --help": bool = false,           // show the help message
};

// Returns true if the captured CLI arg is in the template
// Ignores single character patterns since those are for grouped flags
fn argInTemplate(arg: []const u8, comptime template: []const u8) bool {
    if (template.len < 2) return false;

    var matches: bool = true;
    var i: usize = 0;
    for (template) |c| switch (c) {
        ' ', ',', '/', '|' => {
            if (matches) break;
            matches = true;
            i = 0;
        },
        else => {
            if (!matches) continue;
            if (i >= arg.len) {
                matches = false;
                continue;
            }
            if (c != arg[i]) matches = false;
            i += 1;
        },
    };
    if (i == 1 or i < arg.len) matches = false;

    return matches;
}

// Returns true if a character from a grouped flag is in the template
fn flagInTemplate(flag: u8, comptime template: []const u8) bool {
    if (template.len == 0) return false;

    var first_character: bool = true;
    var matches: bool = false;
    for (template) |c| switch (c) {
        ' ', ',', '/', '|' => {
            if (matches) break;
            first_character = true;
            matches = false;
        },
        else => {
            if (first_character) {
                if (c == flag) matches = true;
                first_character = false;
            } else matches = false;
        },
    };

    return matches;
}

test "argInTemplate, flagInTemplate" {
    try std.testing.expect(argInTemplate("-n", "-n"));
    try std.testing.expect(!argInTemplate("n", "-n"));
    try std.testing.expect(argInTemplate("-x", "-x --scale"));
    try std.testing.expect(argInTemplate("--scale", "-x --scale"));
    try std.testing.expect(!argInTemplate("--x", "-x --scale"));

    // Grouped flags
    try std.testing.expect(!argInTemplate("r", "r --right"));
    try std.testing.expect(flagInTemplate('r', "r --right"));
    try std.testing.expect(flagInTemplate('r', "--right r"));
    try std.testing.expect(!flagInTemplate('n', "--right r"));
    try std.testing.expect(!flagInTemplate('r', "--right rar"));
}

const ArgsError = error { InvalidArgument };

// Returns an instance of Arguments populated with values parsed from an argument slice
// Reflects on `Arguments` and `DrawingStyle` structs
fn parseArgsSlice(args: []const [:0]const u8) ArgsError!Arguments {
    var results: Arguments = .{};

    // Loop through and parse each argument
    const templates = @typeInfo(Arguments).@"struct".fields;
    var args_i: usize = 0;
    argloop: while (args_i < args.len) : (args_i += 1) {
        const arg = args[args_i];

        // Handle args that match templates
        inline for (templates) |field| {
            if (argInTemplate(arg, field.name)) {
                // Bools simply get set to true
                if (field.type == bool) {
                    @field(results, field.name) = true;
                    continue :argloop; // argument successfully handled
                }

                // Other types read the following argument as the parameter
                args_i += 1;
                if (args_i >= args.len) {
                    std.log.err("missing value for {s}", .{arg});
                    return ArgsError.InvalidArgument;
                }
                const val = args[args_i];

                // Set the value of the matching field
                // Parsed based on type
                @field(results, field.name) = switch (field.type) {
                    u8 => if (val.len == 1) val[0] else ArgsError.InvalidArgument,
                    u32, i32 => std.fmt.parseInt(field.type, val, 10),
                    DrawingStyle => asdrawingstyle: {
                        const styles = @typeInfo(DrawingStyle).@"enum".fields;
                        inline for (styles) |style| {
                            if (std.ascii.eqlIgnoreCase(val, style.name)) {
                                break :asdrawingstyle @as(
                                    DrawingStyle,
                                    @enumFromInt(style.value),
                                );
                            }
                        }
                        break :asdrawingstyle ArgsError.InvalidArgument;
                    },
                    Cardinal => ascardinal: {
                        const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
                        if (eqlIgnoreCase(val, "w") or eqlIgnoreCase(val, "west")) {
                            break :ascardinal Cardinal.west;
                        } else if (eqlIgnoreCase(val, "e") or eqlIgnoreCase(val, "east")) {
                            break :ascardinal Cardinal.east;
                        } else if (eqlIgnoreCase(val, "n") or eqlIgnoreCase(val, "north")) {
                            break :ascardinal Cardinal.north;
                        } else if (eqlIgnoreCase(val, "s") or eqlIgnoreCase(val, "south")) {
                            break :ascardinal Cardinal.south;
                        } else {
                            break :ascardinal ArgsError.InvalidArgument;
                        }
                    },
                    else => {
                        @compileLog(field.type);
                        @compileError("unimplemented arg type");
                    },
                } catch {
                    std.log.err("invalid value {s} '{s}'", .{arg, val});
                    return ArgsError.InvalidArgument;
                };

                continue :argloop; // argument successfully handled
            }
        }

        // Handle grouped flags e.g. '-rSD'
        if (arg.len >= 2) {
            if (arg[0] == '-' and arg[1] != '-') {
                flagloop: for (arg[1..]) |flag| {
                    // Set matching template value to true
                    inline for (templates) |field| {
                        if (flagInTemplate(flag, field.name)) {
                            if (field.type == bool) {
                                @field(results, field.name) = true;
                                continue :flagloop; // flag successfully handled
                            }
                        }
                    }

                    // If no templates matched
                    std.log.err("unknown flag '{c}' in '{s}'", .{flag, arg});
                    return ArgsError.InvalidArgument;
                }

                continue :argloop; // argument successfully handled
            }
        }

        // If not handled, it's an invalid argument
        std.log.err("unknown option '{s}'", .{arg});
        return ArgsError.InvalidArgument;
    }

    return results;
}

// Heighway curves are made of folds
const Fold = enum(u1) {
    left,
    right,

    fn reversed(self: @This()) @This() {
        return @enumFromInt(~@intFromEnum(self));
    }
};

const FoldsError = error { ExceedsLimit, OutOfMemory };

// Structure for representing a sequence of folds in an array of bytes: 8 folds per byte
const Folds = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    len: usize,

    // Allocates and returns the folds of a heighway curve
    fn generate(allocator: std.mem.Allocator, n: u32, hand: Fold) !@This() {
        if (n > n_limit) return FoldsError.ExceedsLimit;

        // Calculate the required array length and initialize the array
        const folds_len: usize = folds_len: {
            var result: usize = 0;
            for (0..n) |_| result = (result << 1) + 1;
            break :folds_len result;
        };
        const data_len: usize = data_len: {
            var result: usize = folds_len >> 3;
            if (folds_len & 7 > 0) result += 1;
            break :data_len result;
        };
        var data: []u8 = try allocator.alloc(u8, data_len);

        // Initialize the bytes as zeroes
        for (data, 0..) |_, i| data[i] = 0;

        // Generate the fractal
        const hand_as_bit: u8 = @intFromEnum(hand);
        var end: usize = 0;
        for (0..n) |_| {
            const pivot: usize = end >> 3;
            const alignment: u3 = @truncate(end);

            // Set the end bit
            data[pivot] |=  hand_as_bit << alignment;

            // Fold the pattern from the pivot byte around the end bit
            if (alignment != 0) {
                const flipped: u8 =
                    ~@bitReverse(data[pivot]) >> (7 - alignment + 1);
                if (alignment != 7) {
                    data[pivot] |= flipped << (alignment + 1);
                }
                if (alignment > 3) {
                    data[pivot + 1] |= flipped >> (7 - alignment);
                }
            }

            // Fold the pattern from all previous bytes around the end bit
            for (1..pivot + 1) |radius| {
                const flipped: u8 = ~@bitReverse(data[pivot - radius]);
                data[pivot + radius] |= flipped << alignment;
                if (alignment != 0) {
                    data[pivot + radius + 1] |= flipped >> (7 - alignment + 1);
                }
            }

            // Move the end bit to the end of the pattern
            end = (end << 1) + 1;
        }

        return .{ .allocator=allocator, .data=data, .len=folds_len };
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    fn print(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        var it: FoldsIterator = .{ .folds = &self };
        while (it.next()) |fold| switch (fold) {
            .left => try w.writeAll("L"),
            .right => try w.writeAll("R"),
        };
        try w.writeByte('\n');
        try w.flush();
    }
};

// Structure for iterating through each Fold in an instance of Folds
const FoldsIterator = struct {
    folds: *const Folds,
    index: usize = 0,
    reader: u8 = 0,

    // Returns a Fold and increments the index
    // Returns null when the end is reached
    fn next(self: *@This()) ?Fold {
        if (self.index >= self.folds.len) return null;
        if (self.index & 7 == 0) self.reader = self.folds.data[self.index >> 3];
        const result: Fold = @enumFromInt(@as(u1, @truncate(self.reader)));
        self.index += 1;
        self.reader >>= 1;
        return result;
    }

    fn reset(self: *@This()) void {
        self.index = 0;
    }
};

test Folds {
    const allocator = std.testing.allocator;

    const folds = try Folds.generate(allocator, 23, .left);
    defer folds.deinit();
}

// Structure used to measure the bounding box of the heighway curve
const Envelope = struct {
    l: u32 = 0,
    r: u32 = 0,
    t: u32 = 0,
    b: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,

    // Moves x, y expanding the envelope whenever it reaches the edges
    fn walk(self: *@This(), heading: Cardinal) void {
        switch (heading) {
            .west => {
                if (self.x == 0) {
                    self.l += 1;
                } else {
                    self.x -= 1;
                }
            },
            .east => {
                self.x += 1;
                if (self.x == self.l + self.r + 1) self.r += 1;
            },
            .north => {
                if (self.y == 0) {
                    self.t += 1;
                } else {
                    self.y -= 1;
                }
            },
            .south => {
                self.y += 1;
                if (self.y == self.t + self.b + 1) self.b += 1;
            },
        }
    }
};

const CanvasError = error {
    CanvasTooBig,
    InvalidBrush,
    OffCanvas,
};

// The following canvas structures are used to draw the fractal on a grid of cells
// Each have init, deinit, placeBrush, and moveBrush methods
// Their printing methods vary

// Canvas structure where each cell is either on or off
const BinaryCanvas = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    bwidth: u32,
    width: u32,
    height: u32,
    x: u32 = 0,
    y: u32 = 0,

    // Allocates and fills the canvas with zeroes
    // 0 1 <- Each u8 represents an 8 pixel tile
    // 2 3
    // 4 5
    // 6 7
    fn init(allocator: std.mem.Allocator, width: u32, height: u32) !@This() {
        // Calculate the required bytes
        const bwidth: u32 = bwidth: {
            var result: u32 = width >> 1;
            if (width & 1 > 0) result += 1;
            break :bwidth result;
        };
        const bheight: u32 = bheight: {
            var result: u32 = height >> 2;
            if (height & 3 > 0) result += 1;
            break :bheight result;
        };
        const size = try std.math.mul(u32, bwidth, bheight);
        if (size > canvas_limit) return CanvasError.CanvasTooBig;

        // Allocate bytes
        var bytes: []u8 = try allocator.alloc(u8, size);
        errdefer allocator.free(bytes);

        // Fill canvas with zeroes
        for (0..size) |i| bytes[i] = 0;

        return .{
            .allocator = allocator,
            .bytes = bytes,
            .bwidth = bwidth,
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.bytes);
    }

    // Sets x, y and draws at that point
    fn placeBrush(self: *@This(), x: u32, y: u32) CanvasError!void {
        if (x >= self.width or y >= self.height) return CanvasError.OffCanvas;
        self.x = x;
        self.y = y;
        const bx: u32 = x >> 1;
        const by: u32 = y >> 2;
        const shift_amt: u3 = @truncate((x & 1) + ((y & 3) << 1));
        self.bytes[bx + by * self.bwidth] |= @as(u8, 1) << shift_amt;
    }

    // Moves the brush along a cardinal direction while drawing
    fn moveBrush(self: *@This(), heading: Cardinal, distance: u32) CanvasError!void {
        for (0..distance) |_| {
            switch (heading) {
                .west => {
                    if (self.x == 0) return CanvasError.OffCanvas;
                    try self.placeBrush(self.x - 1, self.y);
                },
                .east => try self.placeBrush(self.x + 1, self.y),
                .north => {
                    if (self.y == 0) return CanvasError.OffCanvas;
                    try self.placeBrush(self.x, self.y - 1);
                },
                .south => try self.placeBrush(self.x, self.y + 1),
            }
        }
    }

    // Prints the canvas using an ascii brush
    fn asciiPrint(self: @This(), w: *std.Io.Writer, brush: u8) !void {
        if (!std.ascii.isAscii(brush)) return CanvasError.InvalidBrush;
        if (self.bytes.len == 0) return;
        for (0..self.height) |y| {
            const by = y >> 2;
            var tile: u8 = undefined;
            for (0..self.width) |x| {
                const bx = x >> 1;
                if (x & 1 == 0) tile = self.bytes[bx + by * self.bwidth];
                const shift_amt: u3 = @truncate((x & 1) + ((y & 3) << 1));
                if ((tile >> shift_amt) & 1 != 0) {
                    try w.writeByte(brush);
                } else {
                    try w.writeByte(' ');
                }
            }
            try w.writeByte('\n');
        }
        try w.flush();
    }

    // Converts canvas tiles to UTF-8 braille patterns
    fn utf8Braille(tile: u8) u21 {
        var result: u21 = 0x2800;
        result |= tile & 0b11100001;
        result |= (tile & 0b00000010) << 2;
        result |= (tile & 0b00000100) >> 1;
        result |= (tile & 0b00001000) << 1;
        result |= (tile & 0b00010000) >> 2;
        return result;
    }

    // Prints the canvas using unicode braille characters
    fn braillePrint(self: @This(), w: *std.Io.Writer) !void {
        if (self.bytes.len == 0) return;
        const bheight: u32 = bheight: {
            var result: u32 = self.height >> 2;
            if (self.height & 3 > 0) result += 1;
            break :bheight result;
        };
        var character: [3]u8 = @splat(0);
        for (0..bheight) |by| {
            for (0..self.bwidth) |bx| {
                _ = try std.unicode.utf8Encode(
                    utf8Braille(self.bytes[bx + by * self.bwidth]),
                    &character,
                );
                try w.writeAll(&character);
            }
            try w.writeByte('\n');
        }
        try w.flush();
    }

    // Converts canvas halftiles to UTF-8 block patterns
    // 0 1 <- halftile bits
    // 2 3
    fn utf8Quadrants(halftile: u4) u21 {
        switch (halftile) {
            0b0000 => return ' ',    // empty
            0b0001 => return 0x2598, // quadrant upper left
            0b0010 => return 0x259D, // quadrant upper right
            0b0011 => return 0x2580, // upper half block
            0b0100 => return 0x2596, // quadrant lower left
            0b0101 => return 0x258C, // left half block
            0b0110 => return 0x259E, // quadrant upper R, lower L
            0b0111 => return 0x259B, // quadrant upper L, upper R, lower L
            0b1000 => return 0x2597, // quadrant lower right
            0b1001 => return 0x259A, // quadrant upper L, lower R
            0b1010 => return 0x2590, // right half block
            0b1011 => return 0x259C, // quadrant upper L, upper R, lower R
            0b1100 => return 0x2584, // lower half block
            0b1101 => return 0x2599, // quadrant upper L, lower L, lower R
            0b1110 => return 0x259F, // quadrant upper R, lower L, lower R
            0b1111 => return 0x2588, // full block
        }
    }

    // Prints the canvas using unicode block quadrants
    fn quadrantsPrint(self: @This(), w: *std.Io.Writer) !void {
        if (self.bytes.len == 0) return;
        const cheight: u32 = cheight: {
            var result: u32 = self.height >> 1;
            if (self.height & 1 > 0) result += 1;
            break :cheight result;
        };
        var character: [3]u8 = @splat(0);
        for (0..cheight) |cy| {
            const by = cy >> 1;
            for (0..self.bwidth) |bx| {
                const halftile: u4 =
                    if (cy & 1 == 0) @truncate(self.bytes[bx + by * self.bwidth])
                    else @truncate(self.bytes[bx + by * self.bwidth] >> 4);
                const length = try std.unicode.utf8Encode(utf8Quadrants(halftile), &character);
                try w.writeAll(character[0..length]);
            }
            try w.writeByte('\n');
        }
        try w.flush();
    }

    // Converts canvas quartertiles to UTF-8 half-block patterns
    // 0 <- quartertile bits
    // 1
    fn utf8Halfblocks(quartertile: u2) u21 {
        switch (quartertile) {
            0b00 => return ' ',    // empty
            0b01 => return 0x2580, // upper half block
            0b10 => return 0x2584, // lower half block
            0b11 => return 0x2588, // full block
        }
    }

    // Prints the canvas using unicode half-blocks
    fn halfblocksPrint(self: @This(), w: *std.Io.Writer) !void {
        if (self.bytes.len == 0) return;
        const cheight: u32 = cheight: {
            var result: u32 = self.height >> 1;
            if (self.height & 1 > 0) result += 1;
            break :cheight result;
        };
        var character: [3]u8 = @splat(0);
        for (0..cheight) |cy| {
            const by = cy >> 1;
            var halftile: u4 = undefined;
            for (0..self.width) |cx| {
                const bx = cx >> 1;
                if (cx & 1 == 0) {
                    halftile = 
                        if (cy & 1 == 0) @truncate(self.bytes[bx + by * self.bwidth])
                        else @truncate(self.bytes[bx + by * self.bwidth] >> 4);
                }
                const quartertile: u2 = 
                    if (cx & 1 == 0) @truncate(halftile & 1 | (halftile & 4) >> 1)
                    else @truncate((halftile & 2) >> 1 | (halftile & 8) >> 2);
                const length = try std.unicode.utf8Encode(utf8Halfblocks(quartertile), &character);
                try w.writeAll(character[0..length]);
            }
            try w.writeByte('\n');
        }
        try w.flush();
    }
};

test BinaryCanvas {
    const allocator = std.testing.allocator;

    var canvas = try BinaryCanvas.init(allocator, 19, 9);
    defer canvas.deinit();

    try std.testing.expectEqual(10, canvas.bwidth);
    try std.testing.expectEqual(30, canvas.bytes.len);

    var canvas2 = try BinaryCanvas.init(allocator, 4, 6);
    defer canvas2.deinit();

    try canvas2.placeBrush(1, 3);
    try canvas2.moveBrush(.west, 1);
    try canvas2.moveBrush(.north, 3);
    try canvas2.moveBrush(.east, 3);
    try canvas2.moveBrush(.south, 5);
    try canvas2.moveBrush(.west, 3);

    try std.testing.expectEqual(0b1101_0111, canvas2.bytes[0]);
    try std.testing.expectEqual(0b1010_1011, canvas2.bytes[1]);
    try std.testing.expectEqual(0b0000_1100, canvas2.bytes[2]);
    try std.testing.expectEqual(0b0000_1110, canvas2.bytes[3]);
}

// Canvas structure where each cell is a junction between its four headings: up, down, left, right
const JunctionCanvas = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    bwidth: u32,
    width: u32,
    height: u32,
    x: u32 = 0,
    y: u32 = 0,

    // Allocates and fills the canvas with zeroes
    // |  1  |  5  | <- Each u8 represents two adjacent junctions
    // |2   0|6   4|
    // |  3  |  7  |
    fn init(allocator: std.mem.Allocator, width: u32, height: u32) !@This() {
        // Calculate the required bytes
        const bwidth: u32 = bwidth: {
            var result: u32 = width >> 1;
            if (width & 1 > 0) result += 1;
            break :bwidth result;
        };
        const size = try std.math.mul(u32, bwidth, height);
        if (size > canvas_limit) return CanvasError.CanvasTooBig;

        // Allocate bytes
        var bytes: []u8 = try allocator.alloc(u8, size);
        errdefer allocator.free(bytes);

        // Fill canvas with zeroes
        for (0..size) |i| bytes[i] = 0;

        return .{
            .allocator = allocator,
            .bytes = bytes,
            .bwidth = bwidth,
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.bytes);
    }

    // Sets the brush x, y
    fn placeBrush(self: *@This(), x: u32, y: u32) CanvasError!void {
        if (x >= self.width or y >= self.height) return CanvasError.OffCanvas;
        self.x = x;
        self.y = y;
    }

    // Moves the brush along a cardinal direction while drawing
    fn moveBrush(self: *@This(), heading: Cardinal, distance: u32) CanvasError!void {
        var bx: u32 = self.x >> 1;
        for (0..distance) |_| {
            // Update leaving junction
            var update: u8 = @as(u8, 1) << @intFromEnum(heading);
            if (self.x & 1 != 0) update <<= 4;
            self.bytes[bx + self.y * self.bwidth] |= update;

            // Move
            switch (heading) {
                .west => {
                    if (self.x == 0) return CanvasError.OffCanvas;
                    try self.placeBrush(self.x - 1, self.y);
                    bx = self.x >> 1;
                },
                .east => {
                    try self.placeBrush(self.x + 1, self.y);
                    bx = self.x >> 1;
                },
                .north => {
                    if (self.y == 0) return CanvasError.OffCanvas;
                    try self.placeBrush(self.x, self.y - 1);
                },
                .south => try self.placeBrush(self.x, self.y + 1),
            }

            // Update entering junction
            update = @as(u8, 1) << @intFromEnum(heading.rotated(2));
            if (self.x & 1 != 0) update <<= 4;
            self.bytes[bx + self.y * self.bwidth] |= update;
        }
    }

    // Unicode box drawing character styles
    const BoxStyle = enum {
        light,
        heavy,
        double,
        arcs,
    };

    // Converts junction directions to UTF-8 box drawing characters
    // |  1  | <- direction bits
    // |2   0|
    // |  3  |
    fn utf8Box(directions: u4, style: BoxStyle) u21 {
        switch (style) {
            .light => switch (directions) {
                0b0000 => return ' ',
                0b0001 => return 0x2576,
                0b0010 => return 0x2575,
                0b0011 => return 0x2514,
                0b0100 => return 0x2574,
                0b0101 => return 0x2500,
                0b0110 => return 0x2518,
                0b0111 => return 0x2534,
                0b1000 => return 0x2577,
                0b1001 => return 0x250C,
                0b1010 => return 0x2502,
                0b1011 => return 0x251C,
                0b1100 => return 0x2510,
                0b1101 => return 0x252C,
                0b1110 => return 0x2524,
                0b1111 => return 0x253C,
            },
            .heavy => switch (directions) {
                0b0000 => return ' ',
                0b0001 => return 0x257A,
                0b0010 => return 0x2579,
                0b0011 => return 0x2517,
                0b0100 => return 0x2578,
                0b0101 => return 0x2501,
                0b0110 => return 0x251B,
                0b0111 => return 0x253B,
                0b1000 => return 0x257B,
                0b1001 => return 0x250F,
                0b1010 => return 0x2503,
                0b1011 => return 0x2523,
                0b1100 => return 0x2513,
                0b1101 => return 0x2533,
                0b1110 => return 0x252B,
                0b1111 => return 0x254B,
            },
            .double => switch (directions) {
                0b0000 => return ' ',
                0b0001 => return 0x255E,
                0b0010 => return 0x2568,
                0b0011 => return 0x255A,
                0b0100 => return 0x2561,
                0b0101 => return 0x2550,
                0b0110 => return 0x255D,
                0b0111 => return 0x2569,
                0b1000 => return 0x2565,
                0b1001 => return 0x2554,
                0b1010 => return 0x2551,
                0b1011 => return 0x2560,
                0b1100 => return 0x2557,
                0b1101 => return 0x2566,
                0b1110 => return 0x2563,
                0b1111 => return 0x256C,
            },
            .arcs => switch (directions) {
                0b0000 => return ' ',
                0b0001 => return 0x2576,
                0b0010 => return 0x2575,
                0b0011 => return 0x2570,
                0b0100 => return 0x2574,
                0b0101 => return 0x2500,
                0b0110 => return 0x256F,
                0b0111 => return 0x2534,
                0b1000 => return 0x2577,
                0b1001 => return 0x256D,
                0b1010 => return 0x2502,
                0b1011 => return 0x251C,
                0b1100 => return 0x256E,
                0b1101 => return 0x252C,
                0b1110 => return 0x2524,
                0b1111 => return 0x253C,
            },
        }
    }

    // Prints the canvas using unicode box drawing characters
    fn print(self: @This(), w: *std.Io.Writer, style: BoxStyle) !void {
        if (self.bytes.len == 0) return;
        var character: [3]u8 = @splat(0);
        for (0..self.height) |by| {
            var byte: u8 = undefined;
            for (0..self.width) |x| {
                const bx = x >> 1;
                if (x & 1 == 0) byte = self.bytes[bx + by * self.bwidth];
                const junction: u4 = if (x & 1 == 0) @truncate(byte) else @truncate(byte >> 4);
                const length = try std.unicode.utf8Encode(utf8Box(junction, style), &character);
                try w.writeAll(character[0..length]);
            }
            try w.writeByte('\n');
        }
        try w.flush();
    }
};

test JunctionCanvas {
    const allocator = std.testing.allocator;

    var canvas = try JunctionCanvas.init(allocator, 3, 2);
    defer canvas.deinit();

    try std.testing.expectEqual(4, canvas.bytes.len);

    // Draw in a circle
    try canvas.placeBrush(1, 1);
    try canvas.moveBrush(.west, 1);
    try canvas.moveBrush(.north, 1);
    try canvas.moveBrush(.east, 1);
    try canvas.moveBrush(.south, 1);

    try std.testing.expectEqual(0b1100_1001, canvas.bytes[0]);
    try std.testing.expectEqual(0b0110_0011, canvas.bytes[2]);
}

// Returns an allocated canvas with the curve drawn on it
fn drawDragon(
    comptime CanvasT: type,
    allocator: std.mem.Allocator,
    folds: Folds,
    starting_direction: Cardinal,
    segment_length: u32,
) !CanvasT {
    var it: FoldsIterator = .{ .folds = &folds };

    // Walk along the fractal for drawing dimensions and starting position
    var envelope: Envelope = .{};
    var heading = starting_direction;
    envelope.walk(heading);
    while (it.next()) |fold| {
        switch (fold) {
            .left => heading = heading.rotated(1),
            .right => heading = heading.rotated(-1),
        }
        envelope.walk(heading);
    }

    // Calculate drawing dimensions
    const add = std.math.add;
    const mul = std.math.mul;
    const width: u32 = try add(u32, 1, try mul(
        u32,
        segment_length,
        try add(u32, envelope.l, envelope.r),
    ));
    const height: u32 = try add(u32, 1, try mul(
        u32,
        segment_length,
        try add(u32, envelope.t, envelope.b),
    ));

    // Initialize the canvas
    var canvas: CanvasT = try .init(allocator, width, height);
    errdefer canvas.deinit();

    // Draw the fractal
    try canvas.placeBrush(segment_length * envelope.l, segment_length * envelope.t);
    heading = starting_direction;
    try canvas.moveBrush(heading, segment_length);
    it.reset();
    while (it.next()) |fold| {
        switch (fold) {
            .left => heading = heading.rotated(1),
            .right => heading = heading.rotated(-1),
        }
        try canvas.moveBrush(heading, segment_length);
    }

    return canvas;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    // Initialize stdout writer
    var stdout_buf: [1024]u8 = undefined;
    var stdout_fw: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_fw.interface;

    // Parse Arguments
    const args = try init.minimal.args.toSlice(allocator);
    const params: Arguments = parseArgsSlice(args[1..]) catch .{ .@"-h --help"=true };
    if (params.@"-h --help") {
        try stdout.writeAll(help_message);
        try stdout.flush();
        return;
    }

    // Generate folds
    const folds = Folds.generate(
        allocator,
        params.@"-n",
        if (params.@"m --mirror") .right else .left,
    ) catch |err| switch (err) {
        error.ExceedsLimit => {
            std.log.err(
                "exceeded iteration limit {} > {}",
                .{params.@"-n", n_limit}
            );
            return;
        },
        else => return err,
    };

    // Print fold sequence
    if (params.@"f --folds") {
        try folds.print(stdout);
        if (params.@"-s --style" != .none) try stdout.writeAll("\n");
    }

    // Print the fractal drawing
    switch (params.@"-s --style") {
        .none => {},

        // Styles that use a BinaryCanvas
        .ascii, .braille, .halfblocks, .quadrants => |style| {
            const canvas = drawDragon(
                BinaryCanvas,
                allocator,
                folds,
                params.@"-d --direction",
                params.@"-x --scale",
            ) catch |err| switch (err) {
                error.Overflow, error.CanvasTooBig => {
                    std.log.err("drawing is too big", .{});
                    return;
                },
                else => return err,
            };

            // Print the canvas
            switch (style) {
                .ascii => canvas.asciiPrint(stdout, params.@"-b --brush") catch |err| {
                    switch (err) {
                        error.InvalidBrush => {
                            std.log.err("invalid brush '{c}'", .{params.@"-b --brush"});
                            return;
                        },
                        else => return err,
                    }
                },
                .braille => try canvas.braillePrint(stdout),
                .halfblocks => try canvas.halfblocksPrint(stdout),
                .quadrants => try canvas.quadrantsPrint(stdout),
                else => unreachable,
            }
        },

        // Styles that use a JunctionCanvas
        .arcs, .box, .doublebox, .heavybox => |style| {
            const canvas = drawDragon(
                JunctionCanvas,
                allocator,
                folds,
                params.@"-d --direction",
                params.@"-x --scale",
            ) catch |err| switch (err) {
                error.Overflow, error.CanvasTooBig => {
                    std.log.err("drawing is too big", .{});
                    return;
                },
                else => return err,
            };

            // Print the canvas
            switch (style) {
                .arcs => try canvas.print(stdout, .arcs),
                .box => try canvas.print(stdout, .light),
                .doublebox => try canvas.print(stdout, .double),
                .heavybox => try canvas.print(stdout, .heavy),
                else => unreachable,
            }
        },
    }
}
