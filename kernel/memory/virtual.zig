const std = @import("std");
const types = @import("types.zig");
const allocator = @import("allocator.zig");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");

const PAGE_SIZE = types.PAGE_SIZE;
const PAGE_SHIFT = types.PAGE_SHIFT;
const PAGE_ENTRIES: usize = 512; // 2^9 entries per page table

// Virtual address breakdown for Sv39
const VA_VPN2_SHIFT: u6 = 30;
const VA_VPN1_SHIFT: u6 = 21;
const VA_VPN0_SHIFT: u6 = 12;
const VA_VPN_MASK: u64 = 0x1FF; // 9 bits

// Re-export PTE flags from types
pub const PTE_V = types.PTE_V;
pub const PTE_R = types.PTE_R;
pub const PTE_W = types.PTE_W;
pub const PTE_X = types.PTE_X;
pub const PTE_U = types.PTE_U;
pub const PTE_G = types.PTE_G;
pub const PTE_A = types.PTE_A;
pub const PTE_D = types.PTE_D;

// Page table entry type
pub const PageTableEntry = u64;

// Extract PPN from PTE
fn pteToAddr(pte: PageTableEntry) usize {
    return (pte >> 10) << PAGE_SHIFT;
}

// Create PTE from physical address and flags
fn addrToPte(addr: usize, flags: u64) PageTableEntry {
    return ((addr >> PAGE_SHIFT) << 10) | flags;
}

// Page table structure
pub const PageTable = struct {
    root_ppn: u64, // Root page table physical page number

    const Self = @This();

    // Initialize a new page table
    pub fn init(self: *Self) !void {
        // Allocate a page for root page table
        const root_page = allocator.allocFrame() orelse return error.OutOfMemory;
        self.root_ppn = root_page >> PAGE_SHIFT;

        // Clear the page table
        const root_table = @as([*]PageTableEntry, @ptrFromInt(root_page));
        for (0..PAGE_ENTRIES) |i| {
            root_table[i] = 0;
        }
    }

    // Deinitialize page table and free all allocated pages
    pub fn deinit(self: *Self) void {
        // TODO: Walk the page table tree and free all L2, L1, L0 pages
        // For now, just free the root page
        allocator.freeFrame(self.root_ppn << PAGE_SHIFT);
        self.root_ppn = 0;
    }

    // Map a virtual address to physical address
    pub fn map(self: *Self, vaddr: usize, paddr: usize, flags: u64) !void {
        // Check alignment
        if ((vaddr & (PAGE_SIZE - 1)) != 0 or (paddr & (PAGE_SIZE - 1)) != 0) {
            return error.Misaligned;
        }

        // Extract VPN levels
        const vpn2 = (vaddr >> VA_VPN2_SHIFT) & VA_VPN_MASK;
        const vpn1 = (vaddr >> VA_VPN1_SHIFT) & VA_VPN_MASK;
        const vpn0 = (vaddr >> VA_VPN0_SHIFT) & VA_VPN_MASK;

        // Walk/create page tables
        var table_addr = self.root_ppn << PAGE_SHIFT;

        // Level 2 (root)
        var table = @as([*]PageTableEntry, @ptrFromInt(table_addr));
        var pte = &table[vpn2];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;
            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            const new_table = @as([*]PageTableEntry, @ptrFromInt(new_page));
            for (0..PAGE_ENTRIES) |i| {
                new_table[i] = 0;
            }
        }

        // Level 1
        table_addr = pteToAddr(pte.*);
        table = @as([*]PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn1];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;
            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            const new_table = @as([*]PageTableEntry, @ptrFromInt(new_page));
            for (0..PAGE_ENTRIES) |i| {
                new_table[i] = 0;
            }
        }

        // Level 0 (leaf)
        table_addr = pteToAddr(pte.*);
        table = @as([*]PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn0];

        // Set the mapping
        pte.* = addrToPte(paddr, flags | PTE_V);
    }

    // Translate virtual address to physical address
    pub fn translate(self: *Self, vaddr: usize) ?usize {
        // Extract VPN levels
        const vpn2 = (vaddr >> VA_VPN2_SHIFT) & VA_VPN_MASK;
        const vpn1 = (vaddr >> VA_VPN1_SHIFT) & VA_VPN_MASK;
        const vpn0 = (vaddr >> VA_VPN0_SHIFT) & VA_VPN_MASK;
        const offset = vaddr & (PAGE_SIZE - 1);

        // Walk page tables
        var table_addr = self.root_ppn << PAGE_SHIFT;

        // Level 2
        var table = @as([*]PageTableEntry, @ptrFromInt(table_addr));
        var pte = table[vpn2];
        if ((pte & PTE_V) == 0) return null;

        // Level 1
        table_addr = pteToAddr(pte);
        table = @as([*]PageTableEntry, @ptrFromInt(table_addr));
        pte = table[vpn1];
        if ((pte & PTE_V) == 0) return null;

        // Level 0
        table_addr = pteToAddr(pte);
        table = @as([*]PageTableEntry, @ptrFromInt(table_addr));
        pte = table[vpn0];
        if ((pte & PTE_V) == 0) return null;

        // Return physical address
        return pteToAddr(pte) | offset;
    }
};

// Global kernel page table
var kernel_page_table: PageTable = undefined;

// Setup kernel page table with initial mappings
pub fn setupKernelPageTable() !void {
    uart.puts("[memory] Setting up kernel page table\n");

    try kernel_page_table.init();

    // Map kernel code/data (identity mapping for now)
    // Includes kernel heap region
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_HEAP_BASE + types.KERNEL_HEAP_SIZE;
    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        try kernel_page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);
    }

    // Map UART
    try kernel_page_table.map(types.UART_BASE, types.UART_BASE, PTE_R | PTE_W | PTE_G);

    // Map CLINT
    var clint_addr: usize = types.CLINT_BASE;
    const clint_end = types.CLINT_BASE + types.CLINT_SIZE;
    while (clint_addr < clint_end) : (clint_addr += PAGE_SIZE) {
        try kernel_page_table.map(clint_addr, clint_addr, PTE_R | PTE_W | PTE_G);
    }

    // Map PLIC
    var plic_addr: usize = types.PLIC_BASE;
    const plic_end = types.PLIC_BASE + types.PLIC_SIZE;
    while (plic_addr < plic_end) : (plic_addr += PAGE_SIZE) {
        try kernel_page_table.map(plic_addr, plic_addr, PTE_R | PTE_W | PTE_G);
    }

    uart.puts("[memory] Kernel page table initialized\n");
}

// Enable MMU with kernel page table
pub fn enableMMU() void {
    const satp_value = csr.SATP_SV39 | kernel_page_table.root_ppn;
    csr.writeSatp(satp_value);
    csr.sfence_vma();

    uart.puts("[memory] MMU enabled with Sv39\n");
}

// Get current page table root
pub fn getCurrentPageTable() *PageTable {
    return &kernel_page_table;
}

// Build global kernel mappings for any page table (including user page tables)
pub fn buildKernelGlobalMappings(page_table: *PageTable) !void {
    const user_memory = @import("../user/memory.zig");

    // Map kernel text/data/bss and heap (supervisor only, global)
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_HEAP_BASE + types.KERNEL_HEAP_SIZE;
    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);
    }

    // Map UART (supervisor only, global)
    try page_table.map(types.UART_BASE, types.UART_BASE, PTE_R | PTE_W | PTE_G);

    // Map CLINT for timer interrupts (supervisor only, global)
    var clint_addr: usize = types.CLINT_BASE;
    const clint_end = types.CLINT_BASE + types.CLINT_SIZE;
    while (clint_addr < clint_end) : (clint_addr += PAGE_SIZE) {
        try page_table.map(clint_addr, clint_addr, PTE_R | PTE_W | PTE_G);
    }

    // Map PLIC for external interrupts (supervisor only, global)
    var plic_addr: usize = types.PLIC_BASE;
    const plic_end = types.PLIC_BASE + types.PLIC_SIZE;
    while (plic_addr < plic_end) : (plic_addr += PAGE_SIZE) {
        try page_table.map(plic_addr, plic_addr, PTE_R | PTE_W | PTE_G);
    }

    // Map kernel stack (supervisor only, global) - CRITICAL for trap handling
    try user_memory.mapKernelStackToPageTable(page_table);
}
