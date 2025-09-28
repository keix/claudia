const std = @import("std");

pub const Elf64Header = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const Elf64ProgramHeader = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

pub const ELF_MAGIC = [4]u8{ 0x7F, 'E', 'L', 'F' };
pub const ELF_CLASS_64 = 2;
pub const ELF_DATA_LSB = 1;
pub const ELF_VERSION_CURRENT = 1;
pub const ELF_MACHINE_RISCV = 243;
pub const ELF_TYPE_EXEC = 2;
pub const PT_LOAD = 1;

pub const ElfError = error{
    InvalidMagic,
    UnsupportedClass,
    UnsupportedEndianness,
    UnsupportedVersion,
    UnsupportedMachine,
    UnsupportedType,
    InvalidHeader,
};

pub fn parseElfHeader(data: []const u8) ElfError!Elf64Header {
    if (data.len < @sizeOf(Elf64Header)) return ElfError.InvalidHeader;

    const header = @as(*const Elf64Header, @ptrCast(@alignCast(data.ptr))).*;

    if (!std.mem.eql(u8, header.e_ident[0..4], &ELF_MAGIC)) return ElfError.InvalidMagic;
    if (header.e_ident[4] != ELF_CLASS_64) return ElfError.UnsupportedClass;
    if (header.e_ident[5] != ELF_DATA_LSB) return ElfError.UnsupportedEndianness;
    if (header.e_ident[6] != ELF_VERSION_CURRENT) return ElfError.UnsupportedVersion;
    if (header.e_machine != ELF_MACHINE_RISCV) return ElfError.UnsupportedMachine;
    if (header.e_type != ELF_TYPE_EXEC) return ElfError.UnsupportedType;

    return header;
}

pub fn getLoadableSegments(data: []const u8, header: Elf64Header) ?[]const Elf64ProgramHeader {
    if (header.e_phoff == 0 or header.e_phnum == 0) return null;

    const ph_size = @as(u64, header.e_phentsize) * @as(u64, header.e_phnum);
    if (header.e_phoff + ph_size > data.len) return null;

    const ph_data = data[header.e_phoff .. header.e_phoff + ph_size];
    return @as([*]const Elf64ProgramHeader, @ptrCast(@alignCast(ph_data.ptr)))[0..header.e_phnum];
}

pub fn loadSegments(data: []const u8, segments: []const Elf64ProgramHeader, copy_fn: fn (dest: u64, src: []const u8) bool) bool {
    for (segments) |segment| {
        if (segment.p_type != PT_LOAD) continue;
        if (segment.p_offset + segment.p_filesz > data.len) return false;

        const segment_data = data[segment.p_offset .. segment.p_offset + segment.p_filesz];
        if (!copy_fn(segment.p_vaddr, segment_data)) return false;
    }
    return true;
}
