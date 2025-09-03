// kernel/syscalls/brk.zig - Program break (heap) management
const std = @import("std");
const defs = @import("abi");
const proc = @import("../process/core.zig");
const memory = @import("../memory/types.zig");
const virtual = @import("../memory/virtual.zig");
const allocator = @import("../memory/allocator.zig");

// sys_brk - Set program break (heap end)
// addr: New program break address (0 to query current break)
// Returns: New program break on success, current break on failure
pub fn sys_brk(addr: usize) isize {
    const process = proc.Scheduler.getCurrentProcess() orelse return defs.ESRCH;

    // If addr is 0, just return current break
    if (addr == 0) {
        return @intCast(process.heap_end);
    }

    // Validate new break is within heap bounds
    const new_addr = @as(u64, @intCast(addr));
    if (new_addr < process.heap_start) {
        // Trying to set break below heap start
        return @intCast(process.heap_end);
    }

    const heap_limit = process.heap_start + memory.USER_HEAP_SIZE;
    if (new_addr > heap_limit) {
        // Trying to set break beyond heap limit
        return @intCast(process.heap_end);
    }

    // Get the user's page table
    var pt = virtual.PageTable{ .root_ppn = process.page_table_ppn };

    // Calculate page-aligned boundaries
    const old_end_page = (process.heap_end + memory.PAGE_SIZE - 1) & ~@as(u64, memory.PAGE_SIZE - 1);
    const new_end_page = (new_addr + memory.PAGE_SIZE - 1) & ~@as(u64, memory.PAGE_SIZE - 1);

    if (new_end_page > old_end_page) {
        // Growing heap - allocate new pages
        var addr_iter = old_end_page;
        while (addr_iter < new_end_page) : (addr_iter += memory.PAGE_SIZE) {
            // Check if we're still within heap bounds
            if (addr_iter >= heap_limit) {
                // Can't grow beyond heap limit
                return @intCast(process.heap_end);
            }

            // Allocate a new physical frame
            const frame = allocator.allocFrame() orelse {
                // Out of physical memory - return current break
                // TODO: Should we unmap/free pages we already allocated?
                return @intCast(process.heap_end);
            };

            // Zero the page
            const page_ptr: [*]u8 = @ptrFromInt(frame);
            @memset(page_ptr[0..memory.PAGE_SIZE], 0);

            // Map it into user space as read/write
            pt.map(addr_iter, frame, virtual.PTE_U | virtual.PTE_R | virtual.PTE_W) catch {
                // Mapping failed - free the page and return current break
                allocator.freeFrame(frame);
                return @intCast(process.heap_end);
            };
        }
    } else if (new_end_page < old_end_page) {
        // Shrinking heap - free pages
        var addr_iter = new_end_page;
        while (addr_iter < old_end_page) : (addr_iter += memory.PAGE_SIZE) {
            // Get the physical address before unmapping
            if (pt.translate(addr_iter)) |phys_addr| {
                // Clear the mapping by remapping with invalid PTE
                // TODO: Implement proper unmap in PageTable
                pt.map(addr_iter, 0, 0) catch {};
                // Free the physical frame (translate returns full address, need page-aligned)
                const frame_addr = phys_addr & ~@as(u64, memory.PAGE_SIZE - 1);
                allocator.freeFrame(frame_addr);
            }
        }
    }

    // Update heap end
    process.heap_end = new_addr;

    return @intCast(new_addr);
}
