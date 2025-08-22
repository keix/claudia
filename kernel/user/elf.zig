// ELF64 parser for RISC-V user programs
const std = @import("std");

// ELF64 header structure
pub const Elf64Header = extern struct {
    e_ident: [16]u8, // ELF identification
    e_type: u16, // Object file type
    e_machine: u16, // Machine architecture
    e_version: u32, // Object file version
    e_entry: u64, // Entry point virtual address
    e_phoff: u64, // Program header table file offset
    e_shoff: u64, // Section header table file offset
    e_flags: u32, // Processor-specific flags
    e_ehsize: u16, // ELF header size in bytes
    e_phentsize: u16, // Program header table entry size
    e_phnum: u16, // Program header table entry count
    e_shentsize: u16, // Section header table entry size
    e_shnum: u16, // Section header table entry count
    e_shstrndx: u16, // Section header string table index
};

// ELF64 program header
pub const Elf64ProgramHeader = extern struct {
    p_type: u32, // Segment type
    p_flags: u32, // Segment flags
    p_offset: u64, // Segment file offset
    p_vaddr: u64, // Segment virtual address
    p_paddr: u64, // Segment physical address
    p_filesz: u64, // Segment size in file
    p_memsz: u64, // Segment size in memory
    p_align: u64, // Segment alignment
};

// ELF constants
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

// Parse ELF header and validate
pub fn parseElfHeader(data: []const u8) ElfError!Elf64Header {
    if (data.len < @sizeOf(Elf64Header)) {
        return ElfError.InvalidHeader;
    }

    const header = @as(*const Elf64Header, @ptrCast(@alignCast(data.ptr))).*;

    // Check ELF magic
    if (!std.mem.eql(u8, header.e_ident[0..4], &ELF_MAGIC)) {
        return ElfError.InvalidMagic;
    }

    // Check for 64-bit
    if (header.e_ident[4] != ELF_CLASS_64) {
        return ElfError.UnsupportedClass;
    }

    // Check endianness (little-endian)
    if (header.e_ident[5] != ELF_DATA_LSB) {
        return ElfError.UnsupportedEndianness;
    }

    // Check version
    if (header.e_ident[6] != ELF_VERSION_CURRENT) {
        return ElfError.UnsupportedVersion;
    }

    // Check machine type (RISC-V)
    if (header.e_machine != ELF_MACHINE_RISCV) {
        return ElfError.UnsupportedMachine;
    }

    // Check file type (executable)
    if (header.e_type != ELF_TYPE_EXEC) {
        return ElfError.UnsupportedType;
    }

    return header;
}

// Get loadable segments from program headers
pub fn getLoadableSegments(data: []const u8, header: Elf64Header) ?[]const Elf64ProgramHeader {
    if (header.e_phoff == 0 or header.e_phnum == 0) {
        return null;
    }

    const ph_offset = header.e_phoff;
    const ph_size = @as(u64, header.e_phentsize) * @as(u64, header.e_phnum);

    if (ph_offset + ph_size > data.len) {
        return null;
    }

    const ph_data = data[ph_offset .. ph_offset + ph_size];
    const ph_array = @as([*]const Elf64ProgramHeader, @ptrCast(@alignCast(ph_data.ptr)))[0..header.e_phnum];

    return ph_array;
}

// Load ELF segments into user memory
pub fn loadSegments(data: []const u8, segments: []const Elf64ProgramHeader, copy_fn: fn (dest: u64, src: []const u8) bool) bool {
    for (segments) |segment| {
        if (segment.p_type != PT_LOAD) continue;

        if (segment.p_offset + segment.p_filesz > data.len) {
            return false;
        }

        const segment_data = data[segment.p_offset .. segment.p_offset + segment.p_filesz];

        if (!copy_fn(segment.p_vaddr, segment_data)) {
            return false;
        }
    }

    return true;
}
