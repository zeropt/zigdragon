// zigdragon.zig
// Author: Riley Mann
//
// using Zig version 0.16.0
//
// try `zig run zigdragon.zig -- -h`
//
// Created on 18 Jul 2026

const std = @import("std");

const n_limit = 23; // Keeps the fractal below 10M folds
const canvas_limit = 16777216; // limit the drawing size
const help_message =
    \\Usage: zigdragon [-mfD] [-n <iteration>]...
    \\
    \\zigdragon is a Heighway curve generator.
    \\
    \\Options:
    \\  -m, --mirror                Generate a right instead of left-handed curve
    \\  -f, --folds                 Output the sequence of folds
    \\  -D, --draw                  Draw the fractal (drawn by default)
    \\  -n <iteration>              Number of iterations the pattern is folded
    \\                              (default: 10)
    \\  -x, --scale <len>           Segment length between each fold (default: 1)
    \\  -b, --brush <char>          Ascii character to draw with (default: '#')
    \\  -d, --direction <heading>   Cardinal direction to start the curve with
    \\                              e.g. N, S, E, W (default: S)
    \\  -h, --help                  Show help
    \\
;

const Cardinal = enum(u2) {
    east,
    north,
    west,
    south,

    // Rotates the value (positive: E->N->W->S->E)
    fn rotate(self: *@This(), by: i32) void {
        if (by == 0) return;
        var heading: u2 = @intFromEnum(self.*);
        heading +%= @as(u2, @intCast(@mod(by, 4)));
        self.* = @enumFromInt(heading);
    }
};

// Command line options
// The name of each field is a template to compare args with
// Single character names are for flags
const Arguments = struct {
    @"m --mirror": bool = false,
    @"f --folds": bool = false,
    @"D --draw": bool = false,
    @"-n": u32 = 10,
    @"-x --scale": u32 = 1,
    @"-b --brush": u8 = '#',
    @"-d --direction": Cardinal = .south,
    @"-h --help": bool = false,
};

// Checks if the arg string is in the template string
// Ignores patterns of length 1 since those are flags
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
        }
    };
    if (i == 1 or i < arg.len) matches = false;

    return matches;
}

// Checks if the flag is in the template string
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
        }
    };

    return matches;
}

test "argInTemplate, flagInTemplate functions" {
    try std.testing.expect(argInTemplate("-n", "-n"));
    try std.testing.expect(!argInTemplate("n", "-n"));

    try std.testing.expect(argInTemplate("-x", "-x --scale"));
    try std.testing.expect(argInTemplate("--scale", "-x --scale"));
    try std.testing.expect(!argInTemplate("--x", "-x --scale"));

    try std.testing.expect(!argInTemplate("r", "r --right"));

    try std.testing.expect(flagInTemplate('r', "r --right"));
    try std.testing.expect(flagInTemplate('r', "--right r"));
    try std.testing.expect(!flagInTemplate('n', "--right r"));
    try std.testing.expect(!flagInTemplate('r', "--right rar"));
}

const ArgsError = error { InvalidArgument };

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
                    continue :argloop;
                }

                // Other types read the following argument as the parameter
                args_i += 1;
                if (args_i >= args.len) {
                    std.log.err("missing value for {s}", .{arg});
                    return ArgsError.InvalidArgument;
                }
                const val = args[args_i];

                // Currently implemented parameter types:
                // u8, u32, i32, Cardinal
                @field(results, field.name) = switch (field.type) {
                    u8 => if (val.len == 1) val[0]
                        else ArgsError.InvalidArgument,
                    u32, i32 => std.fmt.parseInt(field.type, val, 10),
                    Cardinal => ascardinal: {
                        const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
                        if (eqlIgnoreCase(val, "w") or
                            eqlIgnoreCase(val, "west")) {
                            break :ascardinal Cardinal.west;
                        } else if (eqlIgnoreCase(val, "e") or
                            eqlIgnoreCase(val, "east")) {
                            break :ascardinal Cardinal.east;
                        } else if (eqlIgnoreCase(val, "n") or
                            eqlIgnoreCase(val, "north")) {
                            break :ascardinal Cardinal.north;
                        } else if (eqlIgnoreCase(val, "s") or
                            eqlIgnoreCase(val, "south")) {
                            break :ascardinal Cardinal.south;
                        } else {
                            break :ascardinal ArgsError.InvalidArgument;
                        }
                    },
                    else => {
                        @compileLog(field.type);
                        @compileError("unimplemented arg type");
                    }
                } catch {
                    std.log.err("invalid value {s} '{s}'", .{arg, val});
                    return ArgsError.InvalidArgument;
                };

                continue :argloop;
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
                                continue :flagloop;
                            }
                        }
                    }

                    // If no templates matched
                    std.log.err("unknown flag '{c}' in '{s}'", .{flag, arg});
                    return ArgsError.InvalidArgument;
                }

                continue :argloop;
            }
        }

        // If nothing matched, it's an invalid argument
        std.log.err("unknown option '{s}'", .{arg});
        return ArgsError.InvalidArgument;
    }

    return results;
}

const Fold = enum(u1) {
    left,
    right,

    fn reversed(self: @This()) @This() {
        return @enumFromInt(~@intFromEnum(self));
    }
};

const FoldsError = error { ExceedsLimit, OutOfMemory };

fn generateFolds(
    allocator: std.mem.Allocator,
    n: u32,
    hand: Fold,
) FoldsError![]Fold {
    if (n > n_limit) return FoldsError.ExceedsLimit;

    // Calculate the required array length and initialize the array
    const n_folds: usize = foldsmath: {
        var result: usize = 0;
        for (0..n) |_| result = (result << 1) + 1;
        break :foldsmath result;
    };
    var folds: []Fold = try allocator.alloc(Fold, n_folds);
    // if further errors are possible: errdefer allocator.free(folds);

    // Generate the fractal
    var i: usize = 0;
    var pattern_end: usize = 0;
    for (0..n) |_| {
        folds[i] = hand;
        i += 1;
        for (0..pattern_end) |pattern_i| {
            folds[i] = folds[pattern_end - pattern_i - 1].reversed();
            i += 1;
        }
        pattern_end = i;
    }

    return folds;
}

fn printFolds(w: *std.Io.Writer, folds: []Fold) std.Io.Writer.Error!void {
    for (folds) |fold| switch (fold) {
        .left => try w.writeAll("L"),
        .right => try w.writeAll("R"),
    };
    try w.writeAll("\n");
    try w.flush();
}

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

const CanvasError = error { OffCanvas, CanvasTooBig };

const Canvas = struct {
    allocator: std.mem.Allocator,
    canvas: []u8,
    width: u32,
    height: u32,
    x: u32 = 0,
    y: u32 = 0,

    // Allocates and fills the canvas with spaces
    fn init(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
    ) !@This() {
        const canvas_size = try std.math.mul(
            u32,
            try std.math.add(u32, width, 1),
            height
        );
        if (canvas_size > canvas_limit) return CanvasError.CanvasTooBig;
        var canvas: []u8 = try allocator.alloc(u8, canvas_size);
        errdefer allocator.free(canvas);

        // Clean canvas with newlines at the end of each row
        for (0..canvas.len) |i| {
            canvas[i] = if ((i + 1) % (width + 1) == 0) '\n' else ' ';
        }

        return .{
            .allocator = allocator,
            .canvas = canvas,
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.canvas);
    }

    // Sets x, y and draws at that point
    fn placeBrush(
        self: *@This(),
        x: u32,
        y: u32,
        brush: u8,
    ) CanvasError!void {
        if (x >= self.width or y >= self.height) {
            return CanvasError.OffCanvas;
        }

        self.x = x;
        self.y = y;
        self.canvas[x + y * (self.width + 1)] = brush;
    }

    // Moves the brush along a cardinal direction while drawing
    fn moveBrush(
        self: *@This(),
        heading: Cardinal,
        distance: u32,
        brush: u8,
    ) CanvasError!void {
        for (0..distance) |_| {
            switch (heading) {
                .west => {
                    if (self.x == 0) return CanvasError.OffCanvas;
                    try self.placeBrush(self.x - 1, self.y, brush);
                },
                .east => try self.placeBrush(self.x + 1, self.y, brush),
                .north => {
                    if (self.y == 0) return CanvasError.OffCanvas;
                    try self.placeBrush(self.x, self.y - 1, brush);
                },
                .south => try self.placeBrush(self.x, self.y + 1, brush),
            }
        }
    }

    // Prints the drawing to a Writer
    fn print(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll(self.canvas);
        try w.flush();
    }
};

fn printDragon(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    folds: []Fold,
    starting_direction: Cardinal,
    brush: u8,
    segment_length: u32,
) !void {
    // Walk along the fractal for drawing dimensions and starting position
    var envelope: Envelope = .{};
    var heading = starting_direction;
    envelope.walk(heading);
    for (folds) |fold| {
        switch (fold) {
            .left => heading.rotate(1),
            .right => heading.rotate(-1),
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
    var canvas: Canvas = try .init(allocator, width, height);
    defer canvas.deinit();

    // Draw the fractal
    try canvas.placeBrush(
        segment_length * envelope.l,
        segment_length * envelope.t,
        brush,
    );
    heading = starting_direction;
    try canvas.moveBrush(heading, segment_length, brush);
    for (folds) |fold| {
        switch (fold) {
            .left => heading.rotate(1),
            .right => heading.rotate(-1),
        }
        try canvas.moveBrush(heading, segment_length, brush);
    }

    try canvas.print(w);
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
    const params: Arguments = parseArgsSlice(args[1..]) catch .{
        .@"-h --help"=true
    };
    if (params.@"-h --help") {
        try stdout.writeAll(help_message);
        try stdout.flush();
        return;
    }

    // Generate the array of folds
    const folds: []Fold = generateFolds(
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
        else => return err
    };

    // Print fold sequence
    if (params.@"f --folds") {
        try printFolds(stdout, folds);
        if (params.@"D --draw") try stdout.writeAll("\n");
    }

    // Print fractal drawing
    if (params.@"D --draw" or (!params.@"f --folds"
        and !params.@"D --draw")) {
        printDragon(
            allocator,
            stdout,
            folds,
            params.@"-d --direction",
            params.@"-b --brush",
            params.@"-x --scale",
        ) catch |err| switch (err) {
            error.Overflow, error.CanvasTooBig => {
                std.log.err("drawing is too big", .{});
                return;
            },
            else => return err
        };
    }
}
