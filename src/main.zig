const std = @import("std");
const rl = @import("raylib");
const m8 = @import("engine.zig");

const PIXEL_SIZE: u32 = 0x10;
const PIXEL_ACTIVE_COLOR: rl.Color = .white;
const PIXEL_INACTIVE_COLOR: rl.Color = .black;

const TARGET_FRAME_RATE: i32 = 60;

pub fn main() !void {
    // TODO: To be configurable by the user.
    rl.setConfigFlags(.{ .vsync_hint = true });

    const screenWidth = m8.FRAMEBUFFER_WIDTH * PIXEL_SIZE;
    const screenHeight = m8.FRAMEBUFFER_HEIGHT * PIXEL_SIZE;
    rl.initWindow(screenWidth, screenHeight, "m8 - CHIP-8 Emulator");
    defer rl.closeWindow();

    // TODO: To be configurable by the user.
    rl.setTargetFPS(TARGET_FRAME_RATE);

    var chip8 = m8.initializeChip8(isKeyDown, getKeyPressed, getRandomNumber);

    while (!rl.windowShouldClose()) {
        for (0..11) |_| {
            m8.step(&chip8);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        clearScreen();

        drawFramebuffer(&chip8.framebuffer);
    }
}

fn drawFramebuffer(framebuffer: *m8.Framebuffer) void {
    for (framebuffer, 0..) |col, x| {
        for (col, 0..) |pixel, y| {
            drawPixelOnScreen(@intCast(x), @intCast(y), pixel == 1);
        }
    }
}

/// Draws a game-pixel on the screen. Pixels can either be "active" or "inactive", indicated by the `isActive` flag.
/// The pixel color will be defined by whether it's active or not.
fn drawPixelOnScreen(x: i32, y: i32, isActive: bool) void {
    const color = if (isActive) PIXEL_ACTIVE_COLOR else PIXEL_INACTIVE_COLOR;
    rl.drawRectangle(x * PIXEL_SIZE, y * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE, color);
}

/// Clears the screen by filling it with game-pixels with the inactive color.
fn clearScreen() void {
    rl.clearBackground(PIXEL_INACTIVE_COLOR);
}

/// Checks whether a given key is currently being pressed.
fn isKeyDown(key: m8.Keypad) bool {
    const keyboard_key: rl.KeyboardKey = switch (key) {
        .k_0 => .kp_0,
        .k_1 => .kp_1,
        .k_2 => .kp_2,
        .k_3 => .kp_3,
        .k_4 => .kp_4,
        .k_5 => .kp_5,
        .k_6 => .kp_6,
        .k_7 => .kp_7,
        .k_8 => .kp_8,
        .k_9 => .kp_9,
        .k_A => .kp_decimal,
        .k_B => .kp_enter,
        .k_C => .kp_add,
        .k_D => .kp_subtract,
        .k_E => .kp_multiply,
        .k_F => .kp_divide,
    };

    return rl.isKeyDown(keyboard_key);
}

/// Returns the key that's currently being pressed by the user.
fn getKeyPressed() ?m8.Keypad {
    const key = rl.getKeyPressed();

    // TODO: Allow user to map keys. For now we'll use the numpad.
    return switch (key) {
        .kp_0 => .k_0,
        .kp_1 => .k_1,
        .kp_2 => .k_2,
        .kp_3 => .k_3,
        .kp_4 => .k_4,
        .kp_5 => .k_5,
        .kp_6 => .k_6,
        .kp_7 => .k_7,
        .kp_8 => .k_8,
        .kp_9 => .k_9,
        .kp_decimal => .k_A,
        .kp_enter => .k_B,
        .kp_add => .k_C,
        .kp_subtract => .k_D,
        .kp_multiply => .k_E,
        .kp_divide => .k_F,
        else => null,
    };
}

fn getRandomNumber(min: i32, max: i32) i32 {
    return rl.getRandomValue(min, max);
}
