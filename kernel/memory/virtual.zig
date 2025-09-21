const std = @import("std");
const types = @import("types.zig");
const allocator = @import("allocator.zig");
const csr = @import("../arch/riscv/csr.zig");
const uart = @import("../driver/uart/core.zig");
const config = @import("../config.zig");
const user_memory = @import("../user/memory.zig");

const PAGE_SIZE = types.PAGE_SIZE;
const PAGE_SHIFT = types.PAGE_SHIFT;
const PAGE_ENTRIES = config.PageTable.ENTRIES_PER_TABLE; // Entries per page table

const VA_VPN2_SHIFT: u6 = 30;
const VA_VPN1_SHIFT: u6 = 21;
const VA_VPN0_SHIFT: u6 = 12;
const VA_VPN_MASK: u64 = 0x1FF;

// Memory management constants
const MAX_FREED_PAGES_TRACK = 256;
const USER_SPACE_BOUNDARY = 0x80000000;
const MAX_VALID_PHYS_ADDR = 0x100000000; // 4GB
const MMIO_START = 0x80000000;
const MMIO_END = 0x90000000;

pub const PTE_V = types.PTE_V;
pub const PTE_R = types.PTE_R;
pub const PTE_W = types.PTE_W;
pub const PTE_X = types.PTE_X;
pub const PTE_U = types.PTE_U;
pub const PTE_G = types.PTE_G;
pub const PTE_A = types.PTE_A;
pub const PTE_D = types.PTE_D;

pub const PageTableEntry = u64;

// Extract PPN from PTE
fn pteToAddr(pte: PageTableEntry) usize {
    return (pte >> 10) << PAGE_SHIFT;
}

// Create PTE from physical address and flags
fn addrToPte(addr: usize, flags: u64) PageTableEntry {
    return ((addr >> PAGE_SHIFT) << 10) | flags;
}

// Extract VPN components from virtual address
fn extractVPN(vaddr: usize) struct { vpn2: u64, vpn1: u64, vpn0: u64 } {
    return .{
        .vpn2 = (vaddr >> VA_VPN2_SHIFT) & VA_VPN_MASK,
        .vpn1 = (vaddr >> VA_VPN1_SHIFT) & VA_VPN_MASK,
        .vpn0 = (vaddr >> VA_VPN0_SHIFT) & VA_VPN_MASK,
    };
}

// Page table structure
pub const PageTable = struct {
    root_ppn: u64, // Root page table physical page number

    const Self = @This();

    // Helper function to safely clear a page table
    fn clearPageTable(table_addr: usize) void {
        const table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));

        // Check if this is kernel init end - it might already have data!
        if (table_addr == config.MemoryLayout.KERNEL_INIT_END) {
            // Special case: KERNEL_INIT_END
            var has_data = false;
            for (0..PAGE_ENTRIES) |i| {
                if (table[i] != 0) {
                    has_data = true;
                    break;
                }
            }
            if (!has_data) {
                for (0..PAGE_ENTRIES) |i| {
                    @atomicStore(u64, &table[i], 0, .monotonic);
                }
            }
        } else {
            // Normal clear
            for (0..PAGE_ENTRIES) |i| {
                @atomicStore(u64, &table[i], 0, .monotonic);
            }
        }
        asm volatile ("fence rw, rw" ::: "memory");
    }

    // Initialize a new page table
    pub fn init(self: *Self) !void {
        // Allocate a page for root page table
        const root_page = allocator.allocFrame() orelse return error.OutOfMemory;
        self.root_ppn = root_page >> PAGE_SHIFT;

        // SAFETY CHECK: Ensure we're not clearing beyond the page
        if (PAGE_ENTRIES * @sizeOf(PageTableEntry) > PAGE_SIZE) {
            return error.PageTableTooBig;
        }

        // Clear the page table
        clearPageTable(root_page);

        // Write a marker to verify this page table
        const root_table = @as([*]volatile PageTableEntry, @ptrFromInt(root_page));
        const marker_offset = PAGE_ENTRIES - 1; // Last entry
        root_table[marker_offset] = config.MemoryLayout.PAGE_TABLE_DEBUG_MARKER;
    }

    // Deinitialize page table and free all allocated pages
    pub fn deinit(self: *Self) void {
        if (self.root_ppn == 0) return;

        // Track freed pages to avoid double frees from copied entries
        // This is necessary because buildKernelGlobalMappings() copies page table
        // entries as a hardware workaround, creating multiple references to the same
        // L1/L0 page tables. Without tracking, we'd try to free them multiple times.
        var freed_pages: [MAX_FREED_PAGES_TRACK]u64 = undefined;
        var freed_count: usize = 0;

        // Walk the page table tree and free all allocated pages
        self.freePageTableRecursiveWithTracking(self.root_ppn, 2, &freed_pages, &freed_count);

        self.root_ppn = 0;
    }

    // Recursively free page table pages with tracking to avoid double frees
    fn freePageTableRecursiveWithTracking(self: *Self, ppn: u64, level: u32, freed_pages: []u64, freed_count: *usize) void {
        const table_addr = ppn << PAGE_SHIFT;

        // Check if this page was already freed (due to copied entries)
        for (0..freed_count.*) |i| {
            if (freed_pages[i] == table_addr) {
                return; // Already freed, skip
            }
        }

        const table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));

        // If not at leaf level, recursively free child tables
        if (level > 0) {
            for (0..PAGE_ENTRIES) |i| {
                const pte = table[i];
                if ((pte & PTE_V) != 0 and (pte & (PTE_R | PTE_W | PTE_X)) == 0) {
                    // This is a pointer to next level table
                    const child_addr = pteToAddr(pte);
                    const child_ppn = child_addr >> PAGE_SHIFT;
                    self.freePageTableRecursiveWithTracking(child_ppn, level - 1, freed_pages, freed_count);
                }
            }
        }

        // Track this page as freed
        if (freed_count.* < freed_pages.len) {
            freed_pages[freed_count.*] = table_addr;
            freed_count.* += 1;
        }

        // Free this table page
        allocator.freeFrame(table_addr);
    }

    // Map a virtual address to physical address
    pub fn map(self: *Self, vaddr: usize, paddr: usize, flags: u64) !void {
        // Check alignment
        if ((vaddr & (PAGE_SIZE - 1)) != 0 or (paddr & (PAGE_SIZE - 1)) != 0) {
            return error.Misaligned;
        }

        // Extract VPN levels
        const vpn = extractVPN(vaddr);

        // Walk/create page tables
        var table_addr = self.root_ppn << PAGE_SHIFT;

        // Level 2 (root)
        var table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        var pte = &table[vpn.vpn2];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;
            errdefer allocator.freeFrame(new_page);

            if (new_page == config.MemoryLayout.KERNEL_INIT_START) {
                return error.InvalidPageAddress;
            }

            clearPageTable(new_page);
            pte.* = addrToPte(new_page, PTE_V);
        }

        // Level 1
        table_addr = pteToAddr(pte.*);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn.vpn1];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;
            errdefer allocator.freeFrame(new_page);

            if (new_page == config.MemoryLayout.KERNEL_INIT_START) {
                return error.InvalidPageAddress;
            }

            clearPageTable(new_page);
            pte.* = addrToPte(new_page, PTE_V);
        }

        // Level 0 (leaf)
        table_addr = pteToAddr(pte.*);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn.vpn0];

        // Set the mapping
        const new_pte = addrToPte(paddr, flags | PTE_V);

        const old_pte = @atomicLoad(u64, pte, .seq_cst);
        if (old_pte != 0 and new_pte == 0 and vaddr >= config.MemoryLayout.USER_KERNEL_BOUNDARY) {
            return; // Don't clear kernel mapping
        }
        if (old_pte != 0 and (old_pte & PTE_V) != 0 and new_pte != old_pte) {
            // Overwriting a valid mapping - this might be intentional but worth noting
            // In production code, this could log a warning
        }

        @atomicStore(u64, pte, new_pte, .seq_cst);
        asm volatile ("sfence.vma %[addr], zero"
            :
            : [addr] "r" (vaddr),
            : "memory"
        );
    }

// Walk page table and execute callback for each valid user page
    fn walkUserPages(self: *Self, callback: *const fn(vaddr: usize, paddr: usize, flags: u64) anyerror!void) !void {
        if (self.root_ppn == 0) return error.InvalidPageTable;
        const root_addr = self.root_ppn << PAGE_SHIFT;
        const root_table = @as([*]volatile PageTableEntry, @ptrFromInt(root_addr));

        // Walk L2 entries (1GB each)
        for (0..PAGE_ENTRIES) |l2_idx| {
            const l2_pte = root_table[l2_idx];
            if ((l2_pte & PTE_V) == 0) continue;

            // Check if this is user space (first 2GB)
            if (l2_idx >= 2) continue; // Skip kernel space

            // Skip leaf pages at L2 (1GB pages)
            if ((l2_pte & (PTE_R | PTE_W | PTE_X)) != 0) continue;

            const l1_addr = pteToAddr(l2_pte);
            if (l1_addr > MAX_VALID_PHYS_ADDR) continue;

            const l1_table = @as([*]volatile PageTableEntry, @ptrFromInt(l1_addr));

            // Walk L1 entries (2MB each)
            for (0..PAGE_ENTRIES) |l1_idx| {
                const l1_pte = l1_table[l1_idx];
                if ((l1_pte & PTE_V) == 0) continue;

                // Skip leaf pages at L1 (2MB pages)
                if ((l1_pte & (PTE_R | PTE_W | PTE_X)) != 0) continue;

                const l0_addr = pteToAddr(l1_pte);
                if (l0_addr > MAX_VALID_PHYS_ADDR) continue;

                const l0_table = @as([*]volatile PageTableEntry, @ptrFromInt(l0_addr));

                // Walk L0 entries (4KB each)
                for (0..PAGE_ENTRIES) |l0_idx| {
                    const l0_pte = l0_table[l0_idx];
                    if ((l0_pte & PTE_V) == 0) continue;
                    if ((l0_pte & (PTE_R | PTE_W | PTE_X)) == 0) continue;

                    const vaddr = (l2_idx << 30) | (l1_idx << 21) | (l0_idx << 12);
                    if (vaddr >= USER_SPACE_BOUNDARY) continue;

                    const paddr = pteToAddr(l0_pte);
                    const flags = l0_pte & 0x3FF;

                    try callback(vaddr, paddr, flags);
                }
            }
        }
    }

    // Translate virtual address to physical address
    pub fn translate(self: *Self, vaddr: usize) ?usize {
        // Extract VPN levels
        const vpn = extractVPN(vaddr);

        const offset = vaddr & (PAGE_SIZE - 1);

        // Walk page tables
        var table_addr = self.root_ppn << PAGE_SHIFT;

        // Level 2
        var table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        var pte = table[vpn.vpn2];
        if ((pte & PTE_V) == 0) return null;

        // Level 1
        table_addr = pteToAddr(pte);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = table[vpn.vpn1];
        if ((pte & PTE_V) == 0) return null;

        // Level 0
        table_addr = pteToAddr(pte);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = table[vpn.vpn0];
        if ((pte & PTE_V) == 0) return null;

        // Return physical address
        return pteToAddr(pte) | offset;
    }
};

// Global kernel page table
pub var kernel_page_table: PageTable = undefined;

// Track if we're in kernel init phase
var kernel_init_complete: bool = false;

// Common kernel mapping function
fn mapKernelRegions(page_table: *PageTable) !void {
    // Map kernel code/data (identity mapping)
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_END;
    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);
    }

    // Map kernel stack region
    addr = types.KERNEL_STACK_BASE;
    const stack_end = types.KERNEL_STACK_BASE + types.KERNEL_STACK_SIZE;
    while (addr < stack_end) : (addr += PAGE_SIZE) {
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_G);
    }

    // Map UART
    try page_table.map(types.UART_BASE, types.UART_BASE, PTE_R | PTE_W | PTE_G);

    // Map CLINT
    var clint_addr: usize = types.CLINT_BASE;
    const clint_end = types.CLINT_BASE + types.CLINT_SIZE;
    while (clint_addr < clint_end) : (clint_addr += PAGE_SIZE) {
        try page_table.map(clint_addr, clint_addr, PTE_R | PTE_W | PTE_G);
    }

    // Map PLIC
    var plic_addr: usize = types.PLIC_BASE;
    const plic_end = types.PLIC_BASE + types.PLIC_SIZE;
    while (plic_addr < plic_end) : (plic_addr += PAGE_SIZE) {
        try page_table.map(plic_addr, plic_addr, PTE_R | PTE_W | PTE_G);
    }

    // Map region after kernel for initrd
    var initrd_scan_addr = (types.KERNEL_END + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    const initrd_scan_end = initrd_scan_addr + config.MemoryLayout.INITRD_MAX_SCAN_SIZE;
    while (initrd_scan_addr < initrd_scan_end) : (initrd_scan_addr += PAGE_SIZE) {
        page_table.map(initrd_scan_addr, initrd_scan_addr, PTE_R | PTE_W | PTE_G) catch break;
    }
}

// Setup kernel page table with initial mappings
pub fn setupKernelPageTable() !void {
    try kernel_page_table.init();
    try mapKernelRegions(&kernel_page_table);

    // Map DTB region - QEMU passes DTB at various addresses
    // Common DTB locations on QEMU virt
    const dtb_candidates = [_]usize{
        config.MemoryLayout.DTB_CANDIDATE_1, // Common on 256MB config
        config.MemoryLayout.DTB_CANDIDATE_2, // Common on 512MB config
    };
    for (dtb_candidates) |dtb_base| {
        // Map 1MB for DTB (way more than needed, but safe)
        var dtb_addr = dtb_base;
        const dtb_end = dtb_base + config.MemoryLayout.DTB_MAP_SIZE;
        while (dtb_addr < dtb_end) : (dtb_addr += PAGE_SIZE) {
            kernel_page_table.map(dtb_addr, dtb_addr, PTE_R | PTE_G) catch {
                break;
            };
        }
    }
}

// Enable MMU with kernel page table
pub fn enableMMU() void {
    const satp_value = csr.SATP_SV39 | kernel_page_table.root_ppn;

    csr.writeSatp(satp_value);
    csr.sfence_vma();

    // Mark kernel init as complete
    kernel_init_complete = true;
}

// Get current page table root
pub fn getCurrentPageTable() *PageTable {
    return &kernel_page_table;
}

// Build global kernel mappings for any page table (including user page tables)
pub fn buildKernelGlobalMappings(page_table: *PageTable) !void {
    try mapKernelRegions(page_table);

    // Map kernel stack (supervisor only, global) - CRITICAL for trap handling
    try user_memory.mapKernelStackToPageTable(page_table);
}

// Clone user space mappings from one page table to another
// This creates a simple copy of all user pages (no COW yet)
pub fn cloneUserSpace(src_pt: *PageTable, dst_pt: *PageTable) !void {
    const src_root_addr = src_pt.root_ppn << PAGE_SHIFT;
    const src_root = @as([*]volatile PageTableEntry, @ptrFromInt(src_root_addr));

    // Walk L2 entries (1GB each)
    for (0..PAGE_ENTRIES) |l2_idx| {
        const l2_pte = src_root[l2_idx];
        if ((l2_pte & PTE_V) == 0) continue;

        // Check if this is user space (first 2GB)
        if (l2_idx >= 2) continue; // Skip kernel space

        // Skip leaf pages at L2 (1GB pages)
        if ((l2_pte & (PTE_R | PTE_W | PTE_X)) != 0) continue;

        const l1_addr = pteToAddr(l2_pte);
        if (l1_addr > MAX_VALID_PHYS_ADDR) continue;

        const l1_table = @as([*]volatile PageTableEntry, @ptrFromInt(l1_addr));

        // Walk L1 entries (2MB each)
        for (0..PAGE_ENTRIES) |l1_idx| {
            const l1_pte = l1_table[l1_idx];
            if ((l1_pte & PTE_V) == 0) continue;

            // Skip leaf pages at L1 (2MB pages)
            if ((l1_pte & (PTE_R | PTE_W | PTE_X)) != 0) continue;

            const l0_addr = pteToAddr(l1_pte);
            if (l0_addr > MAX_VALID_PHYS_ADDR) continue;

            const l0_table = @as([*]volatile PageTableEntry, @ptrFromInt(l0_addr));

            // Walk L0 entries (4KB each)
            for (0..PAGE_ENTRIES) |l0_idx| {
                const l0_pte = l0_table[l0_idx];
                if ((l0_pte & PTE_V) == 0) continue;
                if ((l0_pte & (PTE_R | PTE_W | PTE_X)) == 0) continue;

                const vaddr = (l2_idx << 30) | (l1_idx << 21) | (l0_idx << 12);
                if (vaddr >= USER_SPACE_BOUNDARY) continue;

                const paddr = pteToAddr(l0_pte);

                // Validate source address - skip if it's in MMIO range or invalid
                if (paddr < USER_SPACE_BOUNDARY or paddr >= MMIO_END) {
                    continue; // Skip MMIO or invalid addresses
                }

                // Allocate new physical page
                const new_page = allocator.allocFrame() orelse return error.OutOfMemory;
                errdefer allocator.freeFrame(new_page);

                // Copy page data
                const src_data = @as([*]const u8, @ptrFromInt(paddr));
                const dst_data = @as([*]u8, @ptrFromInt(new_page));
                @memcpy(dst_data[0..PAGE_SIZE], src_data[0..PAGE_SIZE]);

                // Map the new page with same permissions but ensure PTE_U is set
                const flags = l0_pte & 0x3FF;
                try dst_pt.map(vaddr, new_page, flags | PTE_U);
            }
        }
    }

    // Ensure all changes are visible
    asm volatile ("sfence.vma" ::: "memory");
}
