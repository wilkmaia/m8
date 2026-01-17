//! This module implements the engine for running the CHIP-8 emulator.
//! It mostly follows the descriptions from http://devernay.free.fr/hacks/chip8/C8TECH10.HTM,
//! https://github.com/mattmikolay/chip-8/wiki/CHIP%E2%80%908-Instruction-Set and other online sources.

const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

const RAM_SIZE: usize = 0x1000;
const PC_START: usize = 0x200;
const STACK_SIZE: usize = 0x10;
const V_REGISTERS: usize = 0x10;

/// The memory and register layout for the CHIP-8.
const Memory = struct {
    ram: [RAM_SIZE]u8,
    v: [V_REGISTERS]u8,
    i: u16,
    dt: u8,
    st: u8,
    pc: u16,
    sp: u8,
    stack: [STACK_SIZE]u16,
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

/// Initialize the memory elements of the engine with sane defaults.
fn initializeMemory() Memory {
    return .{
        .ram = fonts ++ ([_]u8{0} ** (RAM_SIZE - 0x50)),
        .v = [_]u8{0} ** V_REGISTERS,
        .i = 0,
        .dt = 0,
        .st = 0,
        .pc = PC_START,
        .sp = 0,
        .stack = [_]u16{0} ** STACK_SIZE,
    };
}

// TODO: Maybe use an enum for the opcodes instead of u16?
fn getNextInstruction(memory: *Memory) u16 {
    assert(memory.pc > PC_START);
    assert(memory.pc < RAM_SIZE);

    var instruction: u16 = memory.ram[memory.pc] << 0x10;
    instruction += memory.ram[memory.pc + 1];

    memory.pc += 2;

    return instruction;
}

fn executeNextInstruction(memory: *Memory) void {
    const instruction = getNextInstruction(memory);

    switch (instruction) {
        0x00E0 => assert(false), // TODO: CLS - Clear the display
        0x00EE => {
            memory.pc = memory.stack[memory.sp];
            memory.sp -= 1; // TODO: Should we handle underflows?
        },
        0x1000...0x1FFF => {
            // TODO: Should we allow PC to be set to 0x000-0x1FF? Should we handle that or just let the world burn?
            memory.pc = instruction - 0x1000;
        },
        0x2000...0x2FFF => {
            memory.sp += 1; // TODO: Should we handle overflows?
            memory.stack[memory.sp] = memory.pc;
            memory.pc = instruction - 0x2000;
        },
        0x3000...0x3FFF => {
            const x: usize = (instruction >> 0x10) - 0x30;
            const vx = memory.v[x];
            const kk = instruction & 0x00FF;

            if (vx == kk) {
                memory.pc += 2;
            }
        },
        0x4000...0x4FFF => {
            const x: usize = (instruction >> 0x10) - 0x40;
            const vx = memory.v[x];
            const kk = instruction & 0x00FF;

            if (vx != kk) {
                memory.pc += 2;
            }
        },
        0x5000...0x5FF0 => {
            if (instruction & 0x000F == 0) {
                const x: usize = (instruction >> 0x10) - 0x50;
                const y: usize = (instruction & 0x00F0) >> 0x08;
                const vx = memory.v[x];
                const vy = memory.v[y];

                if (vx == vy) {
                    memory.pc += 2;
                }
            }
        },
        0x6000...0x6FFF => {
            const x: usize = (instruction >> 0x10) - 0x60;
            const kk = @as(u8, instruction & 0x00FF);

            memory.v[x] = kk;
        },
        0x7000...0x7FFF => {
            const x: usize = (instruction >> 0x10) - 0x70;
            const kk = @as(u8, instruction & 0x00FF);

            memory.v[x] += kk;
        },
        0x8000...0x8FFF => {
            const x: usize = (instruction >> 0x10) - 0x80;
            const y: usize = (instruction & 0x00F0) >> 0x08;

            const instruction_variant = instruction & 0x000F;
            switch (instruction_variant) {
                0x0 => {
                    memory.v[x] = memory.v[y];
                },
                0x1 => {
                    memory.v[x] |= memory.v[y];
                },
                0x2 => {
                    memory.v[x] &= memory.v[y];
                },
                0x3 => {
                    memory.v[x] ^= memory.v[y];
                },
                0x4 => {
                    const res, const carry = @addWithOverflow(memory.v[x], memory.v[y]);
                    memory.v[x] = res;
                    memory.v[0xF] = carry;
                },
                0x5 => {
                    const res, const carry = @subWithOverflow(memory.v[x], memory.v[y]);
                    memory.v[x] = res;
                    memory.v[0xF] = carry ^ 0x1; // TODO: Validate this!
                },
                0x6 => {
                    // According to Cowdog's http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#8xy6 this instruction
                    // sets Vx = Vx >> 1.
                    // On the other hand, Matthew Mikolay
                    // (https://github.com/mattmikolay/chip-8/wiki/CHIP%E2%80%908-Instruction-Set) says that's a mistake
                    // and the instruction should, instead, do `Vx = Vy >> 1`. We're following Matthew's documentation
                    // for the time being. If this proves to be inconsistent with a large number of roms out there this
                    // might be updated.
                    const vy_lsb = memory.v[y] & 0b00000001;
                    memory.v[x] = memory.v[y] >> 0x1;
                    memory.v[0xF] = vy_lsb;
                },
                0x7 => {
                    const res, const carry = @subWithOverflow(memory.v[y], memory.v[x]);
                    memory.v[x] = res;
                    memory.v[0xF] = carry ^ 0x1; // TODO: Validate this!
                },
                0xE => {
                    // Similarly to 0x6's case, there's a discrepancy in how this should be handled in online
                    // documentation sources. Again, we're following Matthew's take here and setting `Vx = Vy << 1`.
                    const vy_msb = memory.v[y] & 0b10000000;
                    memory.v[x] = memory.v[y] << 0x1;
                    memory.v[0xF] = vy_msb;
                },
            }
        },
        0x9000...0x9FF0 => {
            if (instruction & 0x000F == 0) {
                const x: usize = (instruction >> 0x10) - 0x90;
                const y: usize = (instruction & 0x00F0) >> 0x08;
                const vx = memory.v[x];
                const vy = memory.v[y];

                if (vx != vy) {
                    memory.pc += 2;
                }
            }
        },
        0xA000...0xAFFF => {
            memory.i = instruction - 0xA000;
        },
        0xB000...0xBFFF => {
            memory.pc = (instruction - 0xB000) + memory.v[0];
        },
        0xC000...0xCFFF => assert(false), // CXKK - TODO: This instruction depends on a random number generator.
        0xD000...0xDFFF => assert(false), // DXYN - TODO: This instruction depends on drawing to the screen.
        0xE000...0xEFFF => {
            const instruction_variant = instruction & 0x00FF;
            switch (instruction_variant) {
                0x9E => assert(false), // EX9E - TODO: This instruction depends on keyboard input.
                0xA1 => assert(false), // EXA1 - TODO: This instruction depends on keyboard input.
                else => unreachable,
            }
        },
        0xF000...0xFFFF => {
            const x: usize = (instruction >> 0x10) - 0xF0;
            const vx = &memory.v[x];

            const instruction_variant = instruction & 0x00FF;
            switch (instruction_variant) {
                0x07 => {
                    vx.* = memory.dt;
                },
                0x0A => assert(false), // FX0A - TODO: This instruction depends on keyboard input.
                0x15 => {
                    memory.dt = vx.*;
                },
                0x18 => {
                    memory.st = vx.*;
                },
                0x1E => {
                    memory.i += vx.*;
                },
                0x29 => {
                    // TODO: Should we handle cases for vx > 0x0F? For now we won't.
                    memory.i = 5 * vx.*;
                },
                0x33 => {
                    const hundreds = @as(u4, vx.* / 100);
                    const tens = @as(u4, (vx.* % 100) / 10);
                    const ones = @as(u4, vx.* % 10);

                    memory.ram[memory.i] = hundreds;
                    memory.ram[memory.i + 1] = tens;
                    memory.ram[memory.i + 2] = ones;
                },
                0x55 => {
                    for (0..x + 1) |n| {
                        memory.ram[memory.i + n] = memory.v[n];
                    }

                    // Another difference in documentation. According to Matthew we should ALSO adjust the I register
                    // at the end of this instruction.
                    memory.i += x + 1;
                },
                0x65 => {
                    for (0..x + 1) |n| {
                        memory.v[n] = memory.ram[memory.i + n];
                    }

                    // Another difference in documentation. According to Matthew we should ALSO adjust the I register
                    // at the end of this instruction.
                    memory.i += x + 1;
                },
                else => unreachable,
            }
        },
    }
}

test initializeMemory {
    const memory = initializeMemory();

    try expect(memory.ram.len == RAM_SIZE);
    for (memory.ram[0..0x50]) |byte| {
        try expect(byte != 0);
    }
    for (memory.ram[0x50..]) |byte| {
        try expect(byte == 0);
    }

    for (memory.v) |vx| {
        try expect(vx == 0);
    }

    try expect(memory.i == 0);
    try expect(memory.dt == 0);
    try expect(memory.st == 0);
    try expect(memory.pc == PC_START);
    try expect(memory.sp == 0);

    for (memory.stack) |stack_entry| {
        try expect(stack_entry == 0);
    }
}
