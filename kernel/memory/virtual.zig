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

// Page table structure
pub const PageTable = struct {
    root_ppn: u64, // Root page table physical page number
    debug_watchdog_active: bool = false, // Track if this is the watched page table

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
        // Initialize fields
        self.debug_watchdog_active = false;

        // Allocate a page for root page table
        const root_page = allocator.allocFrame() orelse return error.OutOfMemory;
        self.root_ppn = root_page >> PAGE_SHIFT;

        // SAFETY CHECK: Ensure we're not clearing beyond the page
        if (PAGE_ENTRIES * @sizeOf(PageTableEntry) > PAGE_SIZE) {
            return error.PageTableTooBig;
        }

        // Clear the page table
        clearPageTable(root_page);

        // Enable watchdog for debugging problematic page tables
        if (self.root_ppn == config.MemoryLayout.PAGE_TABLE_DEBUG_WATCHDOG_1 or
            self.root_ppn == config.MemoryLayout.PAGE_TABLE_DEBUG_WATCHDOG_2)
        {
            self.debug_watchdog_active = true;
        }

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
        var freed_pages: [256]u64 = undefined;
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
        const vpn2 = (vaddr >> VA_VPN2_SHIFT) & VA_VPN_MASK;
        const vpn1 = (vaddr >> VA_VPN1_SHIFT) & VA_VPN_MASK;
        const vpn0 = (vaddr >> VA_VPN0_SHIFT) & VA_VPN_MASK;

        // Walk/create page tables
        var table_addr = self.root_ppn << PAGE_SHIFT;

        // Level 2 (root)
        var table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        var pte = &table[vpn2];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse {
                return error.OutOfMemory;
            };

            if (new_page == config.MemoryLayout.KERNEL_INIT_START) {
                allocator.freeFrame(new_page);
                return error.OutOfMemory;
            }

            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            clearPageTable(new_page);
        }

        // Level 1
        table_addr = pteToAddr(pte.*);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn1];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;

            if (new_page == config.MemoryLayout.KERNEL_INIT_START) {
                allocator.freeFrame(new_page);
                return error.OutOfMemory;
            }

            pte.* = addrToPte(new_page, PTE_V);

            clearPageTable(new_page);
        }

        // Level 0 (leaf)
        table_addr = pteToAddr(pte.*);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn0];

        // Set the mapping
        const new_pte = addrToPte(paddr, flags | PTE_V);

        const old_pte = @atomicLoad(u64, pte, .seq_cst);
        if (old_pte != 0 and new_pte == 0 and vaddr >= config.MemoryLayout.USER_KERNEL_BOUNDARY) {
            return; // Don't clear kernel mapping
        }

        @atomicStore(u64, pte, new_pte, .seq_cst);
        asm volatile ("sfence.vma %[addr], zero"
            :
            : [addr] "r" (vaddr),
            : "memory"
        );
    }

    // Check if critical page table entries are still valid
    pub fn checkCriticalPTE(self: *Self, label: []const u8) void {
        if (!self.debug_watchdog_active) return;
        _ = label;

        const root_addr = self.root_ppn << PAGE_SHIFT;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const vpn2 = (0x8021b000 >> 30) & 0x1FF;
        const l2_pte = root_table[vpn2];

        if (l2_pte == 0) {
            // Halt immediately
            while (true) {
                asm volatile ("wfi" ::: "memory");
            }
        }
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
        var table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        var pte = table[vpn2];
        if ((pte & PTE_V) == 0) return null;

        // Level 1
        table_addr = pteToAddr(pte);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = table[vpn1];
        if ((pte & PTE_V) == 0) return null;

        // Level 0
        table_addr = pteToAddr(pte);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = table[vpn0];
        if ((pte & PTE_V) == 0) return null;

        // Return physical address
        return pteToAddr(pte) | offset;
    }
};

// Global kernel page table
pub var kernel_page_table: PageTable = undefined;

// Track if we're in kernel init phase
var kernel_init_complete: bool = false;

// Setup kernel page table with initial mappings
pub fn setupKernelPageTable() !void {
    try kernel_page_table.init();

    // Map kernel code/data (identity mapping for now)
    // Map entire kernel region generously
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_END;
    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        try kernel_page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);
    }

    // Map kernel stack region

    addr = types.KERNEL_STACK_BASE;
    const stack_end = types.KERNEL_STACK_BASE + types.KERNEL_STACK_SIZE;
    while (addr < stack_end) : (addr += PAGE_SIZE) {
        try kernel_page_table.map(addr, addr, PTE_R | PTE_W | PTE_G);
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

    // Map region after kernel for initrd - QEMU loads initrd after kernel
    // Map 16MB region after kernel to cover various initrd placements
    var initrd_scan_addr = (types.KERNEL_END + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    const initrd_scan_end = initrd_scan_addr + config.MemoryLayout.INITRD_MAX_SCAN_SIZE;
    while (initrd_scan_addr < initrd_scan_end) : (initrd_scan_addr += PAGE_SIZE) {
        kernel_page_table.map(initrd_scan_addr, initrd_scan_addr, PTE_R | PTE_W | PTE_G) catch {
            // Ignore mapping errors - memory might not exist at this address
            break;
        };
    }

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
    // Start building kernel mappings
    // Map kernel text/data/bss and heap (supervisor only, global)
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_END; // Use KERNEL_END for more generous mapping

    // Mapping kernel region

    var page_count: u32 = 0;
    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        page_count += 1;
        // Progress tracking
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);

        // Check after each critical mapping
        if (addr == 0x8021b000) {
            page_table.checkCriticalPTE("After mapping 0x8021b000");
        }
    }
    // Kernel mapping complete

    // Final check before continuing
    page_table.checkCriticalPTE("After kernel mapping complete");

    // Map kernel stack region

    addr = types.KERNEL_STACK_BASE;
    const stack_end = types.KERNEL_STACK_BASE + types.KERNEL_STACK_SIZE;
    while (addr < stack_end) : (addr += PAGE_SIZE) {
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_G);
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

    // Map region after kernel for initrd - QEMU loads initrd after kernel
    // Map 16MB region after kernel to cover various initrd placements
    var initrd_scan_addr = (types.KERNEL_END + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    const initrd_scan_end = initrd_scan_addr + config.MemoryLayout.INITRD_MAX_SCAN_SIZE;
    while (initrd_scan_addr < initrd_scan_end) : (initrd_scan_addr += PAGE_SIZE) {
        page_table.map(initrd_scan_addr, initrd_scan_addr, PTE_R | PTE_W | PTE_G) catch {
            // Ignore mapping errors - memory might not exist at this address
            break;
        };
    }

    // Map kernel stack (supervisor only, global) - CRITICAL for trap handling
    try user_memory.mapKernelStackToPageTable(page_table);

    // Final check after all mappings
    page_table.checkCriticalPTE("buildKernelGlobalMappings complete");

    // WORKAROUND: Hardware seems to expect kernel at different VPN
    // Map critical kernel pages at the locations hardware expects
    // NOTE: Skip this for child process page tables to avoid memory leak
    if (page_table == &kernel_page_table) {
        const critical_addr: u64 = 0x8021c000;
        const hw_vpn2: u64 = 0x1c; // Hardware expects this

        // Get the L2 page table
        const root_addr = page_table.root_ppn << 12;
        const root_table = @as([*]volatile u64, @ptrFromInt(root_addr));

        // Check if hw_vpn2 entry exists
        if (root_table[hw_vpn2] == 0) {
            // Copy the L2 entry from where we put it to where hardware expects it
            const our_vpn2 = (critical_addr >> 30) & 0x1FF; // Should be 2
            if (root_table[our_vpn2] != 0) {
                root_table[hw_vpn2] = root_table[our_vpn2];
            }
        }
    }
}

// Clone user space mappings from one page table to another
// This creates a simple copy of all user pages (no COW yet)
pub fn cloneUserSpace(src_pt: *PageTable, dst_pt: *PageTable) !void {

    // Walk the source page table and copy user mappings
    const src_root_addr = src_pt.root_ppn << PAGE_SHIFT;
    const src_root = @as([*]volatile PageTableEntry, @ptrFromInt(src_root_addr));

    const dst_root_addr = dst_pt.root_ppn << PAGE_SHIFT;
    const dst_root = @as([*]volatile PageTableEntry, @ptrFromInt(dst_root_addr));

    // Walk through all L2 entries
    var valid_entries: u32 = 0;
    var pages_copied: u32 = 0;
    // Walk L2 entries

    for (0..PAGE_ENTRIES) |i| {
        const l2_pte = src_root[i];
        if ((l2_pte & PTE_V) == 0) continue;

        valid_entries += 1;

        // Check if this is a user-accessible page or in user address range
        // Note: Some systems may not set PTE_U properly, so also check address range
        const is_user_range = i < 4; // VPN2 0-3 covers 0x0 - 0x40000000 (1GB each)

        // Process user entries

        if ((l2_pte & PTE_U) != 0 or is_user_range) {
            // Processing user L2 entry

            // This is a user mapping, we need to copy it
            if ((l2_pte & (PTE_R | PTE_W | PTE_X)) != 0) {
                // Leaf page at L2 (1GB page) - not typically used for user space
                continue;
            }

            // Allocate L1 table for destination if not already present
            // Check if dst_root already has an entry

            if ((dst_root[i] & PTE_V) == 0) {
                const l1_page = allocator.allocFrame() orelse return error.OutOfMemory;
                PageTable.clearPageTable(l1_page);
                dst_root[i] = addrToPte(l1_page, PTE_V);
            } else {
                // dst_root already has valid entry
            }

            // Walk L1 table
            const src_l1_addr = pteToAddr(l2_pte);
            // Sanity check - this address seems way too high
            if (src_l1_addr > 0x100000000) { // > 4GB
                continue;
            }

            const src_l1 = @as([*]volatile PageTableEntry, @ptrFromInt(src_l1_addr));

            const dst_l1_addr = pteToAddr(dst_root[i]);
            // Get destination L1 table
            const dst_l1 = @as([*]volatile PageTableEntry, @ptrFromInt(dst_l1_addr));

            // Walk L1 entries
            for (0..PAGE_ENTRIES) |j| {
                const l1_pte = src_l1[j];
                if ((l1_pte & PTE_V) == 0) continue;

                // For user space pages, copy regardless of PTE_U bit
                if (true) { // Always process L1 entries in user range
                    if ((l1_pte & (PTE_R | PTE_W | PTE_X)) != 0) {
                        // Leaf page at L1 (2MB page) - not typically used
                        continue;
                    }

                    // Allocate L0 table for destination if not already present
                    if ((dst_l1[j] & PTE_V) == 0) {
                        const l0_page = allocator.allocFrame() orelse return error.OutOfMemory;
                        PageTable.clearPageTable(l0_page);
                        dst_l1[j] = addrToPte(l0_page, PTE_V);
                    }

                    // Walk L0 table and copy user pages
                    const src_l0_addr = pteToAddr(l1_pte);

                    // Sanity check L0 address
                    if (src_l0_addr > 0x100000000) {
                        continue;
                    }

                    const src_l0 = @as([*]volatile PageTableEntry, @ptrFromInt(src_l0_addr));

                    const dst_l0_addr = pteToAddr(dst_l1[j]);
                    const dst_l0 = @as([*]volatile PageTableEntry, @ptrFromInt(dst_l0_addr));

                    for (0..PAGE_ENTRIES) |k| {
                        const l0_pte = src_l0[k];
                        if ((l0_pte & PTE_V) == 0) continue;

                        // Copy any valid page in user address range
                        if ((l0_pte & PTE_V) != 0 and (l0_pte & (PTE_R | PTE_W | PTE_X)) != 0) {
                            // Calculate virtual address
                            const vaddr = (i << 30) | (j << 21) | (k << 12);

                            // Skip kernel addresses
                            if (vaddr >= 0x80000000) {
                                continue;
                            }

                            // This is a user page - allocate new physical page and copy data
                            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;

                            // Copy page data
                            const src_page_addr = pteToAddr(l0_pte);

                            // Validate source address - skip if it's in MMIO range or invalid
                            if (src_page_addr < 0x80000000 or src_page_addr >= 0x90000000) {
                                // Skip this page - it might be MMIO or invalid
                                allocator.freeFrame(new_page);
                                continue;
                            }

                            const src_data = @as([*]const u8, @ptrFromInt(src_page_addr));
                            const dst_data = @as([*]u8, @ptrFromInt(new_page));
                            @memcpy(dst_data[0..PAGE_SIZE], src_data[0..PAGE_SIZE]);

                            // Map the new page with same permissions but ensure PTE_U is set
                            dst_l0[k] = addrToPte(new_page, (l0_pte & 0x3FF) | PTE_U); // Keep flags and ensure user bit
                            pages_copied += 1;
                        }
                    }
                }
            }
        }
    }

    // Ensure all changes are visible
    asm volatile ("sfence.vma" ::: "memory");
}
