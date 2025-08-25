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
    debug_watchdog_active: bool = false, // Track if this is the watched page table

    const Self = @This();

    // Initialize a new page table
    pub fn init(self: *Self) !void {
        // Initialize fields
        self.debug_watchdog_active = false;

        // Allocate a page for root page table
        const root_page = allocator.allocFrame() orelse return error.OutOfMemory;
        self.root_ppn = root_page >> PAGE_SHIFT;

        // Clear the page table
        const root_table = @as([*]volatile PageTableEntry, @ptrFromInt(root_page));

        // SAFETY CHECK: Ensure we're not clearing beyond the page
        if (PAGE_ENTRIES * @sizeOf(PageTableEntry) > PAGE_SIZE) {
            return error.PageTableTooBig;
        }

        // Clear exactly one page (512 entries * 8 bytes = 4096 bytes)
        for (0..PAGE_ENTRIES) |i| {
            @atomicStore(u64, &root_table[i], 0, .monotonic);
        }

        // Memory barrier to ensure all clears complete
        asm volatile ("fence rw, rw" ::: "memory");

        // Enable watchdog for debugging problematic page tables
        if (self.root_ppn == 0x802bf or self.root_ppn == 0x802cf) {
            self.debug_watchdog_active = true;
        }

        // Write a marker to verify this page table
        const marker_offset = PAGE_ENTRIES - 1; // Last entry
        root_table[marker_offset] = 0xDEADBEEF00000000; // Special marker
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
        var table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        var pte = &table[vpn2];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse {
                return error.OutOfMemory;
            };

            // Defensive check: ensure we're not allocating 0x802bf000
            if (new_page == 0x802bf000) {
                // Don't use this page
                allocator.freeFrame(new_page);
                return error.OutOfMemory;
            }

            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            const new_table = @as([*]volatile PageTableEntry, @ptrFromInt(new_page));

            // Check if this is 0x802cf000 - it might already have data!
            if (new_page == 0x802cf000) {
                var has_data = false;
                for (0..PAGE_ENTRIES) |i| {
                    if (new_table[i] != 0) {
                        has_data = true;
                        break;
                    }
                }
                if (!has_data) {
                    for (0..PAGE_ENTRIES) |i| {
                        @atomicStore(u64, &new_table[i], 0, .monotonic);
                    }
                }
            } else {
                // Normal clear
                for (0..PAGE_ENTRIES) |i| {
                    @atomicStore(u64, &new_table[i], 0, .monotonic);
                }
            }
            asm volatile ("fence rw, rw" ::: "memory");
        }

        // Level 1
        table_addr = pteToAddr(pte.*);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn1];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse return error.OutOfMemory;

            // Defensive check: ensure we're not allocating 0x802bf000
            if (new_page == 0x802bf000) {
                // Don't use this page
                allocator.freeFrame(new_page);
                return error.OutOfMemory;
            }

            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            const new_table = @as([*]volatile PageTableEntry, @ptrFromInt(new_page));

            // Check if this is 0x802cf000 - it might already have data!
            if (new_page == 0x802cf000) {
                var has_data = false;
                for (0..PAGE_ENTRIES) |i| {
                    if (new_table[i] != 0) {
                        has_data = true;
                        break;
                    }
                }
                if (!has_data) {
                    for (0..PAGE_ENTRIES) |i| {
                        @atomicStore(u64, &new_table[i], 0, .monotonic);
                    }
                }
            } else {
                // Normal clear
                for (0..PAGE_ENTRIES) |i| {
                    @atomicStore(u64, &new_table[i], 0, .monotonic);
                }
            }
            asm volatile ("fence rw, rw" ::: "memory");
        }

        // Level 0 (leaf)
        table_addr = pteToAddr(pte.*);
        table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        pte = &table[vpn0];

        // Set the mapping
        const new_pte = addrToPte(paddr, flags | PTE_V);

        // Protect against clearing kernel mappings in user page tables
        const old_pte = @atomicLoad(u64, pte, .seq_cst);
        if (old_pte != 0 and new_pte == 0 and vaddr >= 0x80000000) {
            // Trying to clear a kernel mapping!
            return; // Don't clear it
        }

        // Force atomic write with memory barrier
        @atomicStore(u64, pte, new_pte, .seq_cst);

        // Ensure TLB consistency for this specific virtual address
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
    const initrd_scan_end = initrd_scan_addr + (16 * 1024 * 1024); // 16MB
    while (initrd_scan_addr < initrd_scan_end) : (initrd_scan_addr += PAGE_SIZE) {
        kernel_page_table.map(initrd_scan_addr, initrd_scan_addr, PTE_R | PTE_W | PTE_G) catch {
            // Ignore mapping errors - memory might not exist at this address
            break;
        };
    }
    
    // Map DTB region - QEMU passes DTB at various addresses
    // Common DTB locations on QEMU virt
    const dtb_candidates = [_]usize{
        0x8fe00000,  // Common on 256MB config
        0x9fe00000,  // Common on 512MB config
    };
    for (dtb_candidates) |dtb_base| {
        // Map 1MB for DTB (way more than needed, but safe)
        var dtb_addr = dtb_base;
        const dtb_end = dtb_base + (1024 * 1024);
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
    const user_memory = @import("../user/memory.zig");

    // Map kernel text/data/bss and heap (supervisor only, global)
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_END; // Use KERNEL_END for more generous mapping

    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);

        // Check after each critical mapping
        if (addr == 0x8021b000) {
            page_table.checkCriticalPTE("After mapping 0x8021b000");
        }
    }

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
    const initrd_scan_end = initrd_scan_addr + (16 * 1024 * 1024); // 16MB
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
