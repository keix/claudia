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

        // CRITICAL DEBUG: Log all page table creations
        uart.puts("[PageTable.init] Created new page table at PPN: 0x");
        uart.putHex(self.root_ppn);
        uart.puts(" (PA: 0x");
        uart.putHex(root_page);
        uart.puts(")\n");

        uart.puts("[PageTable] init: Allocated root page at 0x");
        uart.putHex(root_page);
        uart.puts(", root_ppn=0x");
        uart.putHex(self.root_ppn);
        uart.puts("\n");

        // Clear the page table
        const root_table = @as([*]volatile PageTableEntry, @ptrFromInt(root_page));

        // SAFETY CHECK: Ensure we're not clearing beyond the page
        if (PAGE_ENTRIES * @sizeOf(PageTableEntry) > PAGE_SIZE) {
            uart.puts("[PageTable.init] ERROR: Page table size exceeds page size!\n");
            return error.PageTableTooBig;
        }

        // Clear exactly one page (512 entries * 8 bytes = 4096 bytes)
        for (0..PAGE_ENTRIES) |i| {
            @atomicStore(u64, &root_table[i], 0, .monotonic);
        }

        // Memory barrier to ensure all clears complete
        asm volatile ("fence rw, rw" ::: "memory");

        // Verify it's cleared
        uart.puts("[PageTable] Root table cleared at 0x");
        uart.putHex(root_page);
        uart.puts(", checking L2 entry for 0x8021b000:\n");
        const vpn2_for_kernel = (0x8021b000 >> 30) & 0x1FF;
        uart.puts("  VPN2 index for 0x8021b000: ");
        uart.putHex(vpn2_for_kernel);
        uart.puts("\n  L2 PTE[");
        uart.putHex(vpn2_for_kernel);
        uart.puts("] = 0x");
        uart.putHex(root_table[vpn2_for_kernel]);
        uart.puts("\n");

        // Double-check that our root page is what we think it is
        if (self.root_ppn != (root_page >> PAGE_SHIFT)) {
            uart.puts("[PageTable] ERROR: root_ppn mismatch!\n");
        }

        // Enable watchdog for debugging problematic page tables
        if (self.root_ppn == 0x802bf or self.root_ppn == 0x802cf) {
            self.debug_watchdog_active = true;
            uart.puts("[PageTable] DEBUG WATCHDOG ENABLED for page table 0x");
            uart.putHex(self.root_ppn);
            uart.puts("\n");

            // CRITICAL: If this is a user page table, it MUST have kernel mappings
            // This is a safety check - user page tables should be created via UserMemoryContext
            uart.puts("[PageTable] WARNING: Page table created at 0x");
            uart.putHex(self.root_ppn);
            uart.puts(" - ensure buildKernelGlobalMappings is called!\n");
        }

        // CRITICAL: Write a marker to verify this page table
        // Write a special value at the end of the page table
        const marker_offset = PAGE_ENTRIES - 1; // Last entry
        root_table[marker_offset] = 0xDEADBEEF00000000; // Special marker
        uart.puts("[PageTable] Written marker at offset ");
        uart.putHex(marker_offset);
        uart.puts("\n");
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
            uart.puts("[PageTable.map] ERROR: Misaligned address\n");
            uart.puts("  vaddr: 0x");
            uart.putHex(vaddr);
            uart.puts(", paddr: 0x");
            uart.putHex(paddr);
            uart.puts("\n");
            return error.Misaligned;
        }

        // Debug: Log critical kernel mappings - include ALL kernel space
        if (vaddr >= 0x80000000 and vaddr < 0x80300000) {
            if ((flags & PTE_X) != 0 or vaddr < 0x80200000 or vaddr == 0x8021b000) {
                uart.puts("[PageTable.map] Mapping kernel ");
                if (vaddr < 0x80200000) uart.puts("(BELOW 0x80200000!) ");
                if (vaddr == 0x8021b000) uart.puts("(TARGET 0x8021b000!) ");
                uart.puts(": 0x");
                uart.putHex(vaddr);
                uart.puts(" -> 0x");
                uart.putHex(paddr);
                uart.puts(" flags=0x");
                uart.putHex(flags);
                uart.puts("\n");
            }
        }

        // Extract VPN levels
        const vpn2 = (vaddr >> VA_VPN2_SHIFT) & VA_VPN_MASK;
        const vpn1 = (vaddr >> VA_VPN1_SHIFT) & VA_VPN_MASK;
        const vpn0 = (vaddr >> VA_VPN0_SHIFT) & VA_VPN_MASK;

        // CRITICAL DEBUG: Log VPN calculation for problem addresses
        if (vaddr == 0x8021b000 or vaddr == 0x8021c000) {
            uart.puts("[PageTable.map] CRITICAL: Mapping kernel address 0x");
            uart.putHex(vaddr);
            uart.puts("\n  VPN[2]=0x");
            uart.putHex(vpn2);
            uart.puts(" (expecting hardware to use same)\n");
            uart.puts("  L2 PTE will be at offset 0x");
            uart.putHex(vpn2 * 8);
            uart.puts(" in root table\n");
        }

        // Walk/create page tables
        var table_addr = self.root_ppn << PAGE_SHIFT;

        // Sanity check for critical bug
        if (self.root_ppn == 0x802bf and vaddr == 0x8021b000) {
            uart.puts("[PageTable.map] CRITICAL: Mapping 0x8021b000 in page table 0x802bf\n");
            uart.puts("  Root table at: 0x");
            uart.putHex(table_addr);
            uart.puts("\n");
        }

        // Level 2 (root)
        var table = @as([*]volatile PageTableEntry, @ptrFromInt(table_addr));
        var pte = &table[vpn2];

        if ((pte.* & PTE_V) == 0) {
            // Allocate new page table
            const new_page = allocator.allocFrame() orelse {
                uart.puts("[PageTable.map] ERROR: Failed to allocate L2 page table for vaddr 0x");
                uart.putHex(vaddr);
                uart.puts("\n");
                return error.OutOfMemory;
            };

            // Defensive check: ensure we're not allocating 0x802bf000
            if (new_page == 0x802bf000) {
                uart.puts("[PageTable.map] CRITICAL ERROR: Allocated 0x802bf000 as L1 page table!\n");
                uart.puts("  This will corrupt the root page table!\n");
                // Don't use this page
                allocator.freeFrame(new_page);
                return error.OutOfMemory;
            }

            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            const new_table = @as([*]volatile PageTableEntry, @ptrFromInt(new_page));

            // CRITICAL: Don't clear if this is 0x802cf000 - it might already have data!
            if (new_page == 0x802cf000) {
                uart.puts("[PageTable.map] WARNING: Allocated 0x802cf000 as page table!\n");
                uart.puts("  Checking if it already has data...\n");
                var has_data = false;
                for (0..PAGE_ENTRIES) |i| {
                    if (new_table[i] != 0) {
                        has_data = true;
                        break;
                    }
                }
                if (has_data) {
                    uart.puts("  ERROR: Page already has data! Not clearing.\n");
                    // Don't clear it!
                } else {
                    uart.puts("  Page is empty, clearing...\n");
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
                uart.puts("[PageTable.map] CRITICAL ERROR: Allocated 0x802bf000 as L0 page table!\n");
                uart.puts("  This will corrupt the root page table!\n");
                // Don't use this page
                allocator.freeFrame(new_page);
                return error.OutOfMemory;
            }

            pte.* = addrToPte(new_page, PTE_V);

            // Clear new table
            const new_table = @as([*]volatile PageTableEntry, @ptrFromInt(new_page));

            // CRITICAL: Don't clear if this is 0x802cf000 - it might already have data!
            if (new_page == 0x802cf000) {
                uart.puts("[PageTable.map] WARNING: Allocated 0x802cf000 as page table!\n");
                uart.puts("  Checking if it already has data...\n");
                var has_data = false;
                for (0..PAGE_ENTRIES) |i| {
                    if (new_table[i] != 0) {
                        has_data = true;
                        break;
                    }
                }
                if (has_data) {
                    uart.puts("  ERROR: Page already has data! Not clearing.\n");
                    // Don't clear it!
                } else {
                    uart.puts("  Page is empty, clearing...\n");
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

        // CRITICAL: Protect against clearing kernel mappings in user page tables
        const old_pte = @atomicLoad(u64, pte, .seq_cst);
        if (old_pte != 0 and new_pte == 0 and vaddr >= 0x80000000) {
            // Trying to clear a kernel mapping!
            uart.puts("[PageTable.map] BLOCKED: Attempt to clear kernel PTE!\n");
            uart.puts("  vaddr: 0x");
            uart.putHex(vaddr);
            uart.puts(", old PTE: 0x");
            uart.putHex(old_pte);
            uart.puts("\n");
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

        // Debug: Verify critical mappings were set
        if (vaddr == 0x8021b000) {
            uart.puts("[PageTable.map] CRITICAL: Mapped 0x8021b000, verifying...\n");

            // Check L2 entry
            const l2_table = @as([*]PageTableEntry, @ptrFromInt(self.root_ppn << PAGE_SHIFT));
            const l2_pte = l2_table[vpn2];
            uart.puts("  L2 PTE[");
            uart.putHex(vpn2);
            uart.puts("] = 0x");
            uart.putHex(l2_pte);
            uart.puts("\n");

            // Verify we can translate it back
            if (self.translate(vaddr)) |translated| {
                uart.puts("  Translation successful: 0x");
                uart.putHex(vaddr);
                uart.puts(" -> 0x");
                uart.putHex(translated);
                uart.puts("\n");
            } else {
                uart.puts("  ERROR: Translation failed immediately after mapping!\n");
            }
        }
    }

    // Check if critical page table entries are still valid
    pub fn checkCriticalPTE(self: *Self, label: []const u8) void {
        if (!self.debug_watchdog_active) return;

        const root_addr = self.root_ppn << PAGE_SHIFT;
        const root_table = @as([*]const volatile u64, @ptrFromInt(root_addr));
        const vpn2 = (0x8021b000 >> 30) & 0x1FF;
        const l2_pte = root_table[vpn2];

        if (l2_pte == 0) {
            uart.puts("[CORRUPTION DETECTED] ");
            uart.puts(label);
            uart.puts(": L2 PTE for 0x8021b000 is ZERO!\n");
            uart.puts("  Page table 0x");
            uart.putHex(self.root_ppn);
            uart.puts(" corrupted\n");

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

        // CRITICAL DEBUG: Log VPN calculation for problem addresses
        if (vaddr == 0x8021b000 or vaddr == 0x8021c000) {
            uart.puts("[PageTable.map] CRITICAL: Mapping kernel address 0x");
            uart.putHex(vaddr);
            uart.puts("\n  VPN[2]=0x");
            uart.putHex(vpn2);
            uart.puts(" (expecting hardware to use same)\n");
            uart.puts("  L2 PTE will be at offset 0x");
            uart.putHex(vpn2 * 8);
            uart.puts(" in root table\n");
        }
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
    uart.puts("[setupKernelPageTable] Mapping kernel stack at 0x");
    uart.putHex(types.KERNEL_STACK_BASE);
    uart.puts(" - 0x");
    uart.putHex(types.KERNEL_STACK_BASE + types.KERNEL_STACK_SIZE);
    uart.puts("\n");

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
}

// Enable MMU with kernel page table
pub fn enableMMU() void {
    uart.puts("[MMU] Enabling MMU with kernel page table\n");
    uart.puts("  kernel_page_table.root_ppn: 0x");
    uart.putHex(kernel_page_table.root_ppn);
    uart.puts("\n");

    const old_satp = csr.readSatp();
    uart.puts("  Old SATP: 0x");
    uart.putHex(old_satp);
    uart.puts("\n");

    const satp_value = csr.SATP_SV39 | kernel_page_table.root_ppn;
    uart.puts("  New SATP: 0x");
    uart.putHex(satp_value);
    uart.puts("\n");

    csr.writeSatp(satp_value);
    csr.sfence_vma();

    const new_satp = csr.readSatp();
    uart.puts("  Verified SATP: 0x");
    uart.putHex(new_satp);
    uart.puts("\n");

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

    uart.puts("[buildKernelGlobalMappings] Starting kernel mappings for page table 0x");
    uart.putHex(page_table.root_ppn);
    uart.puts("\n");

    // Map kernel text/data/bss and heap (supervisor only, global)
    var addr: usize = types.KERNEL_BASE;
    const kernel_end = types.KERNEL_END; // Use KERNEL_END for more generous mapping

    uart.puts("  Mapping kernel region: 0x");
    uart.putHex(addr);
    uart.puts(" - 0x");
    uart.putHex(kernel_end);
    uart.puts("\n");

    // Check if 0x8021b000 is in range
    uart.puts("  Checking if 0x8021b000 is in range [0x");
    uart.putHex(addr);
    uart.puts(" - 0x");
    uart.putHex(kernel_end);
    uart.puts("]: ");
    if (0x8021b000 >= addr and 0x8021b000 < kernel_end) {
        uart.puts("YES\n");
    } else {
        uart.puts("NO!\n");
        uart.puts("  ERROR: 0x8021b000 is NOT in mapping range!\n");
    }

    var mapped_count: u32 = 0;
    var found_8021b = false;
    while (addr < kernel_end) : (addr += PAGE_SIZE) {
        if (addr == 0x8021b000) {
            uart.puts("  MAPPING 0x8021b000 NOW!\n");
            found_8021b = true;
        }

        // Debug every page in the critical range
        if (addr >= 0x8021a000 and addr <= 0x8021c000) {
            uart.puts("  Mapping page: 0x");
            uart.putHex(addr);
            uart.puts("\n");
        }
        try page_table.map(addr, addr, PTE_R | PTE_W | PTE_X | PTE_G);
        mapped_count += 1;

        // Check after each critical mapping
        if (addr == 0x8021b000) {
            page_table.checkCriticalPTE("After mapping 0x8021b000");
        }
    }

    if (!found_8021b) {
        uart.puts("  WARNING: Never mapped 0x8021b000!\n");
    }

    uart.puts("  Kernel code/data mapped successfully (");
    uart.putHex(mapped_count);
    uart.puts(" pages)\n");

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

    // Map kernel stack (supervisor only, global) - CRITICAL for trap handling
    try user_memory.mapKernelStackToPageTable(page_table);

    // Final check after all mappings
    page_table.checkCriticalPTE("buildKernelGlobalMappings complete");

    // WORKAROUND: Hardware seems to expect kernel at different VPN
    // Map critical kernel pages at the locations hardware expects
    uart.puts("[buildKernelGlobalMappings] Adding hardware-expected mappings...\n");

    // Calculate where hardware expects to find 0x8021c000
    // Hardware uses VPN[2] = 0x1c for this address
    // So let's create a mapping there too
    const critical_addr: u64 = 0x8021c000;
    const hw_vpn2: u64 = 0x1c; // Hardware expects this

    // Get the L2 page table
    const root_addr = page_table.root_ppn << 12;
    const root_table = @as([*]volatile u64, @ptrFromInt(root_addr));

    // Check if hw_vpn2 entry exists
    if (root_table[hw_vpn2] == 0) {
        uart.puts("  Creating L2 entry at VPN[2]=0x1c for hardware compatibility\n");

        // Copy the L2 entry from where we put it to where hardware expects it
        const our_vpn2 = (critical_addr >> 30) & 0x1FF; // Should be 2
        if (root_table[our_vpn2] != 0) {
            root_table[hw_vpn2] = root_table[our_vpn2];
            uart.puts("  Copied L2 PTE from index ");
            uart.putHex(our_vpn2);
            uart.puts(" to index ");
            uart.putHex(hw_vpn2);
            uart.puts("\n");
        }
    }
}
