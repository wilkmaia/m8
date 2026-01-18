//! This module implements the engine for running the CHIP-8 emulator.
//! It mostly follows the descriptions from http://devernay.free.fr/hacks/chip8/C8TECH10.HTM,
//! https://github.com/mattmikolay/chip-8/wiki/CHIP%E2%80%908-Instruction-Set and other online sources.

const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

const MEMORY_SIZE: usize = 0x1000;
const PC_START: usize = 0x200;
const STACK_SIZE: usize = 0x10;
const V_REGISTERS: usize = 0x10;

pub const SOUND_SAMPLE_RATE: f64 = 44_100;
pub const SOUND_SAMPLE_FREQUENCY: f64 = 440;
pub const SAMPLES: usize = 187_425; // 4.25 * 44_100
pub const RawSoundWave = [SAMPLES]i16;

pub const FRAMEBUFFER_WIDTH: usize = 0x40;
pub const FRAMEBUFFER_HEIGHT: usize = 0x20;

pub const Framebuffer = [FRAMEBUFFER_WIDTH][FRAMEBUFFER_HEIGHT]u1;

pub const Keypad = enum(u4) {
    k_0 = 0x0,
    k_1 = 0x1,
    k_2 = 0x2,
    k_3 = 0x3,
    k_4 = 0x4,
    k_5 = 0x5,
    k_6 = 0x6,
    k_7 = 0x7,
    k_8 = 0x8,
    k_9 = 0x9,
    k_A = 0xA,
    k_B = 0xB,
    k_C = 0xC,
    k_D = 0xD,
    k_E = 0xE,
    k_F = 0xF,
};

const ExecutionState = enum(u4) {
    running = 0x0,
    waiting_for_keypress = 0x1,
};

/// Data modeling for the CHIP-8 architecture. It contains references to its registers, the stack and memory.
pub const Chip8 = struct {
    state: ExecutionState,

    memory: [MEMORY_SIZE]u8,
    v: [V_REGISTERS]u8,
    i: u16,
    dt: u8,
    st: u8,
    pc: u16,
    sp: u8,
    stack: [STACK_SIZE]u16,
    framebuffer: Framebuffer,

    next_key_x: usize,
    raw_sound_wave: RawSoundWave,

    isKeyDown: *const fn (key: Keypad) bool,
    getKeyPressed: *const fn () ?Keypad,
    getRandomNumber: *const fn (min: i32, max: i32) i32,

    pub fn loadRom(self: *Chip8, rom: []u8, size: u64) void {
        if (size > MEMORY_SIZE - PC_START) {
            std.debug.panic("Tried loading {} bytes of memory. Max allowed: {}.\n", .{ size, MEMORY_SIZE - PC_START });
        }

        std.mem.copyForwards(u8, self.memory[0x200..], rom);
    }

    pub fn decreaseDelayTimer(self: *Chip8) void {
        if (self.dt == 0) {
            return;
        }

        self.dt -= 1;
    }

    pub fn decreaseSoundTimer(self: *Chip8) void {
        if (self.st == 0) {
            return;
        }

        self.st -= 1;
    }

    pub fn step(self: *Chip8) void {
        switch (self.state) {
            .running => {
                self.executeNextInstruction();
            },
            .waiting_for_keypress => {
                if (self.getKeyPressed()) |key| {
                    self.v[self.next_key_x] = @intFromEnum(key);
                    self.state = .running;
                }
            },
        }
    }

    // TODO: Maybe use an enum for the opcodes instead of u16?
    fn getNextInstruction(self: *Chip8) u16 {
        assert(self.pc >= PC_START);
        assert(self.pc < MEMORY_SIZE);

        var instruction: u16 = @as(u16, self.memory[self.pc]) << 0x08;
        instruction += self.memory[self.pc + 1];

        self.pc += 2;

        return instruction;
    }

    fn executeNextInstruction(self: *Chip8) void {
        const instruction = self.getNextInstruction();

        switch (instruction) {
            0x00E0 => {
                self.framebuffer = getClearedFramebuffer();
            },
            0x00EE => {
                self.pc = self.stack[self.sp];
                self.sp -= 1; // TODO: Should we handle underflows?
            },
            0x1000...0x1FFF => {
                // TODO: Should we allow PC to be set to 0x000-0x1FF? Should we handle that or just let the world burn?
                self.pc = instruction - 0x1000;
            },
            0x2000...0x2FFF => {
                self.sp += 1; // TODO: Should we handle overflows?
                self.stack[self.sp] = self.pc;
                self.pc = instruction - 0x2000;
            },
            0x3000...0x3FFF => {
                const x: usize = (instruction >> 0x08) - 0x30;
                const kk = instruction & 0x00FF;

                if (self.v[x] == kk) {
                    self.pc += 2;
                }
            },
            0x4000...0x4FFF => {
                const x: usize = (instruction >> 0x08) - 0x40;
                const kk = instruction & 0x00FF;

                if (self.v[x] != kk) {
                    self.pc += 2;
                }
            },
            0x5000...0x5FF0 => {
                if (instruction & 0x000F == 0) {
                    const x: usize = (instruction >> 0x08) - 0x50;
                    const y: usize = (instruction & 0x00F0) >> 0x04;

                    if (self.v[x] == self.v[y]) {
                        self.pc += 2;
                    }
                }
            },
            0x6000...0x6FFF => {
                const x: usize = (instruction >> 0x08) - 0x60;
                const kk: u8 = @intCast(instruction & 0x00FF);

                self.v[x] = kk;
            },
            0x7000...0x7FFF => {
                const x: usize = (instruction >> 0x08) - 0x70;
                const kk: u8 = @intCast(instruction & 0x00FF);

                self.v[x] +%= kk;
            },
            0x8000...0x8FFF => {
                const x: usize = (instruction >> 0x08) - 0x80;
                const y: usize = (instruction & 0x00F0) >> 0x04;

                const instruction_variant = instruction & 0x000F;
                switch (instruction_variant) {
                    0x0 => {
                        self.v[x] = self.v[y];
                    },
                    0x1 => {
                        self.v[x] |= self.v[y];
                    },
                    0x2 => {
                        self.v[x] &= self.v[y];
                    },
                    0x3 => {
                        self.v[x] ^= self.v[y];
                    },
                    0x4 => {
                        const res, const carry = @addWithOverflow(self.v[x], self.v[y]);
                        self.v[x] = res;
                        self.v[0xF] = carry;
                    },
                    0x5 => {
                        const res, const carry = @subWithOverflow(self.v[x], self.v[y]);
                        self.v[x] = res;
                        self.v[0xF] = carry ^ 0x1; // TODO: Validate this!
                    },
                    0x6 => {
                        // According to Cowdog's http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#8xy6 this instruction
                        // sets Vx = Vx >> 1.
                        // On the other hand, Matthew Mikolay
                        // (https://github.com/mattmikolay/chip-8/wiki/CHIP%E2%80%908-Instruction-Set) says that's a mistake
                        // and the instruction should, instead, do `Vx = Vy >> 1`. We're following Matthew's documentation
                        // for the time being. If this proves to be inconsistent with a large number of roms out there this
                        // might be updated.
                        const vy_lsb = self.v[y] & 0b00000001;
                        self.v[x] = self.v[y] >> 0x1;
                        self.v[0xF] = vy_lsb;
                    },
                    0x7 => {
                        const res, const carry = @subWithOverflow(self.v[y], self.v[x]);
                        self.v[x] = res;
                        self.v[0xF] = carry ^ 0x1; // TODO: Validate this!
                    },
                    0xE => {
                        // Similarly to 0x6's case, there's a discrepancy in how this should be handled in online
                        // documentation sources. Again, we're following Matthew's take here and setting `Vx = Vy << 1`.
                        const vy_msb = self.v[y] & 0b10000000;
                        self.v[x] = self.v[y] << 0x1;
                        self.v[0xF] = vy_msb;
                    },
                    else => unreachable,
                }
            },
            0x9000...0x9FF0 => {
                if (instruction & 0x000F == 0) {
                    const x: usize = (instruction >> 0x08) - 0x90;
                    const y: usize = (instruction & 0x00F0) >> 0x04;

                    if (self.v[x] != self.v[y]) {
                        self.pc += 2;
                    }
                }
            },
            0xA000...0xAFFF => {
                self.i = instruction - 0xA000;
            },
            0xB000...0xBFFF => {
                self.pc = (instruction - 0xB000) + self.v[0];
            },
            0xC000...0xCFFF => {
                const x: usize = (instruction >> 0x08) - 0xC0;
                const n: u8 = @intCast(instruction & 0x00FF);
                const rnd: u8 = @intCast(self.getRandomNumber(0x00, 0xFF));

                self.v[x] = rnd & n;
            },
            0xD000...0xDFFF => {
                const x: usize = (instruction >> 0x08) - 0xD0;
                const y: usize = (instruction & 0x00F0) >> 0x04;
                const n: u4 = @intCast(instruction & 0x000F);

                const vx = self.v[x];
                const vy = self.v[y];

                var collision_detected = false;
                for (0..n) |y_offset| {
                    // TODO: What is `I + fb_y` goes beyond memory?
                    const sprite = self.memory[self.i + y_offset];

                    for (0..8) |x_offset| {
                        const bitshift_operand: u3 = @intCast(x_offset);
                        const sprite_pixel: u1 = @intCast(sprite >> (0x07 - bitshift_operand) & 0x01);
                        const fb_x = (vx + x_offset) % FRAMEBUFFER_WIDTH;
                        const fb_y = (vy + y_offset) % FRAMEBUFFER_WIDTH;
                        const fb_pixel = &self.framebuffer[fb_x][fb_y];

                        if (sprite_pixel == 1 and fb_pixel.* == 1) {
                            collision_detected = true;
                        }

                        fb_pixel.* ^= sprite_pixel;
                    }
                }

                if (collision_detected) {
                    self.v[0xF] = 1;
                }
            },
            0xE000...0xEFFF => {
                const x: usize = (instruction >> 0x08) - 0xE0;

                const instruction_variant = instruction & 0x00FF;
                switch (instruction_variant) {
                    0x9E => {
                        const key: Keypad = @enumFromInt(self.v[x]);
                        if (self.isKeyDown(key)) {
                            self.pc += 2;
                        }
                    },
                    0xA1 => {
                        const key: Keypad = @enumFromInt(self.v[x]);
                        if (!self.isKeyDown(key)) {
                            self.pc += 2;
                        }
                    },
                    else => unreachable,
                }
            },
            0xF000...0xFFFF => {
                const x: usize = (instruction >> 0x08) - 0xF0;

                const instruction_variant = instruction & 0x00FF;
                switch (instruction_variant) {
                    0x07 => {
                        self.v[x] = self.dt;
                    },
                    0x0A => {
                        self.state = .waiting_for_keypress;
                        self.next_key_x = x;
                    },
                    0x15 => {
                        self.dt = self.v[x];
                    },
                    0x18 => {
                        self.st = self.v[x];
                    },
                    0x1E => {
                        self.i += self.v[x];
                    },
                    0x29 => {
                        // TODO: Should we handle cases for vx > 0x0F? For now we won't.
                        self.i = 5 * self.v[x];
                    },
                    0x33 => {
                        const vx = self.v[x];
                        const hundreds: u4 = @intCast(vx / 100);
                        const tens: u4 = @intCast((vx % 100) / 10);
                        const ones: u4 = @intCast(vx % 10);

                        const i = self.i;
                        self.memory[i] = hundreds;
                        self.memory[i + 1] = tens;
                        self.memory[i + 2] = ones;
                    },
                    0x55 => {
                        for (0..x + 1) |n| {
                            self.memory[self.i + n] = self.v[n];
                        }

                        // Another difference in documentation. According to Matthew we should ALSO adjust the I register
                        // at the end of this instruction.
                        self.i += @as(u16, @intCast(x)) + 1;
                    },
                    0x65 => {
                        for (0..x + 1) |n| {
                            self.v[n] = self.memory[self.i + n];
                        }

                        // Another difference in documentation. According to Matthew we should ALSO adjust the I register
                        // at the end of this instruction.
                        self.i += @as(u16, @intCast(x)) + 1;
                    },
                    else => unreachable,
                }
            },
            else => unreachable,
        }
    }
};

/// An 8x5 representation of the default fonts for the CHIP-8 emulator.
const fonts = [0x50]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // "0"
    0x20, 0x60, 0x20, 0x20, 0x70, // "1"
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // "2"
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // "3"
    0x90, 0x90, 0xF0, 0x10, 0x10, // "4"
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // "5"
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // "6"
    0xF0, 0x10, 0x20, 0x40, 0x40, // "7"
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // "8"
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // "9"
    0xF0, 0x90, 0xF0, 0x90, 0x90, // "A"
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // "B"
    0xF0, 0x80, 0x80, 0x80, 0xF0, // "C"
    0xE0, 0x90, 0x90, 0x90, 0xE0, // "D"
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // "E"
    0xF0, 0x80, 0xF0, 0x80, 0x80, // "F"
};

fn getClearedFramebuffer() Framebuffer {
    return std.mem.zeroes(Framebuffer);
}

/// Initialize the data model elements of the engine with sane defaults.
pub fn initializeChip8(is_key_down_fn: *const fn (key: Keypad) bool, get_key_pressed_fn: *const fn () ?Keypad, get_random_number_fn: *const fn (min: i32, max: i32) i32) Chip8 {
    var raw_sound_wave: RawSoundWave = .{0} ** SAMPLES;
    for (0..SAMPLES) |n| {
        raw_sound_wave[n] = @intFromFloat(std.math.maxInt(i16) * std.math.sin(2 * std.math.pi * SOUND_SAMPLE_FREQUENCY * @as(f32, @floatFromInt(n)) / SOUND_SAMPLE_RATE));
    }

    return .{
        .state = .running,
        .memory = fonts ++ ([_]u8{0} ** (MEMORY_SIZE - fonts.len)),
        .v = [_]u8{0} ** V_REGISTERS,
        .i = 0,
        .dt = 0,
        .st = 0,
        .pc = PC_START,
        .sp = 0,
        .stack = [_]u16{0} ** STACK_SIZE,
        .framebuffer = getClearedFramebuffer(),

        .next_key_x = 0,
        .raw_sound_wave = raw_sound_wave,

        .isKeyDown = is_key_down_fn,
        .getKeyPressed = get_key_pressed_fn,
        .getRandomNumber = get_random_number_fn,
    };
}
