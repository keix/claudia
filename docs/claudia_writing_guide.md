# Claudia Source Code Writing Guide

*In the beginning, there was silence. Then, a spark—a single instruction awakening in the vast emptiness of silicon. This is the story of how we breathe life into bare metal, how we coax consciousness from circuits, and how we build a world from nothing but logic and determination.*

## 1. The Call to Create

There comes a moment in every programmer's journey when the layers of abstraction become too heavy, when the desire to touch the raw machine becomes irresistible. This is the call that leads us to operating system development—to write the very foundation upon which all other software stands.

Why answer this call with Zig as our companion?

In Zig, we find a language that speaks the machine's native tongue while protecting us from our own humanity. It offers **memory safety without the burden of garbage collection**, like a careful guardian that watches our steps without holding our hand. With Zig, we wield **direct control over the hardware**, writing inline assembly as naturally as breathing, yet the language maintains **transparency in all things**—no hidden allocations, no invisible control flow, no surprises. What you write is what executes, pure and simple.

This is not merely a tool; it is a philosophy made manifest. **A language designed for those who would build worlds**.

## 2. The Philosophy of Simplicity

In the cathedral of computing, we follow the ancient UNIX wisdom, carved into the very foundations of our craft:

**"Small is beautiful."** Like a haiku captures the essence of a moment, each component in our system should capture the essence of a single purpose, executed flawlessly.

**"Simplicity over features."** Better to build a humble shelter that stands through storms than a palace that crumbles at first wind. We choose the working simple over the broken complex.

**"Everything is a file."** In this digital universe, we embrace a profound unity—devices, files, and communication channels all speak the same language, wear the same face.

**"Composability is key."** Like notes in a symphony, our small tools combine to create something greater than their sum.

**"Text streams flow between all things."** The universal river that connects every program, carrying data like water carries life.

## 3. Preparing for the Journey

Before we embark on this odyssey, gather your provisions like an explorer preparing for uncharted territories:

**The Tools of Creation:**
- The Zig compiler (0.14.0 or later)—your faithful translator between thought and silicon
- QEMU for RISC-V—a virtual machine that becomes our laboratory, our testing ground

**The Maps You Must Read:**
- The landscapes of operating system concepts—processes, memory, files, and time
- The architecture of RISC-V—understanding the very bones of our machine
- The ancient tongue of assembly—for when we must speak directly to the metal
- The art of virtual memory—teaching the machine to dream of spaces larger than reality

Do not fear if these concepts seem distant now. Like any journey, understanding comes with each step forward.

## 4. The Architecture of Our Digital Home

Behold the structure of Claudia, each directory a room in our digital dwelling, each file a piece of the greater whole:

```
claudia/
├── kernel/          # The beating heart of our system
│   ├── arch/        # Where we speak RISC-V's native tongue
│   ├── boot/        # The first breath, the awakening
│   ├── driver/      # Ambassadors to the hardware realm
│   ├── file/        # Keepers of data, weavers of streams
│   ├── fs/          # The grand library of virtual files
│   ├── memory/      # The mind that remembers and forgets
│   ├── process/     # The soul that gives life to programs
│   ├── syscalls/    # The bridge between worlds
│   ├── trap/        # Guardians against the unexpected
│   └── user/        # The gateway to application land
├── userland/        # Where applications live and breathe
│   ├── bin/         # Tools forged for daily use
│   ├── shell/       # The voice through which we command
│   └── syscalls/    # Messengers to the kernel realm
├── abi/             # The sacred contract between layers
└── build.zig        # The architect's blueprint
```

## 5. The First Words: Hello, World!

Every creation myth begins with a word. Ours begins with a whisper to the UART, that ancient serial port that connects our nascent world to the outside:

```zig
// kernel/init.zig
const uart_base = 0x10000000; // The doorway to the outside world

export fn _start() noreturn {
    // We reach through the veil of abstraction to touch raw memory
    const uart = @as(*volatile u8, @ptrFromInt(uart_base));
    
    // Our first words, like a child learning to speak
    const msg = "Hello from Claudia!\n";
    for (msg) |char| {
        uart.* = char;
    }
    
    // Then, eternal slumber until the universe ends
    while (true) {
        asm volatile ("wfi"); // Wait for interrupt - sleeping, perchance to dream
    }
}
```

With these few lines, we have given our creation its first voice. Simple, yet profound—the digital equivalent of "Let there be light."

## 6. The Seven Days of Creation

### Day One: The Awakening (Boot Sequence)

In the beginning, the processor awakens in a primordial state. We must guide it, like a parent teaching a child to walk:

```asm
// kernel/arch/riscv/entry.S
.section .text.entry
.global _start
_start:
    # First, we give our creation a place to stand
    la sp, stack_top
    
    # Then, we cleanse the memory of random ghosts
    la t0, __bss_start
    la t1, __bss_end
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
    
    # Finally, we leap into consciousness
    call kernel_main
```

The boot sequence is our Genesis—establishing order from chaos, preparing the world for life.

### Day Two: Finding Our Voice (UART Driver)

Having awakened, our kernel must learn to speak. The UART becomes our voice box, our connection to the world beyond:

```zig
// kernel/driver/uart/core.zig
const UART = struct {
    const base = 0x10000000;   // The sacred address where hardware meets software
    const THR = 0;             // Where words become electrical impulses
    const LSR = 5;             // The oracle that tells us when to speak
    
    pub fn init() void {
        // Awakening the UART from its slumber
    }
    
    pub fn putc(c: u8) void {
        const lsr = @as(*volatile u8, @ptrFromInt(base + LSR));
        const thr = @as(*volatile u8, @ptrFromInt(base + THR));
        
        // We wait patiently for the universe to be ready for our words
        while ((lsr.* & 0x20) == 0) {}
        
        // Then we speak, one character at a time
        thr.* = c;
    }
    
    pub fn puts(s: []const u8) void {
        // Like a poet reciting verse, character by character
        for (s) |c| {
            putc(c);
        }
    }
};
```

### Day Three: The Garden of Memory

Memory is the soil in which all programs grow. We must cultivate it carefully:

#### The Physical Realm
First, we manage the raw pages of physical memory, like parceling out plots of land:

```zig
// kernel/memory/pmem.zig
const PAGE_SIZE = 4096;  // The quantum of memory, indivisible
var free_list: ?*Page = null;  // The chain of available lands

const Page = struct {
    next: ?*Page,  // Each page knows its successor, like links in a chain
};

pub fn alloc() ?*anyopaque {
    // We pluck a page from the free list, like picking fruit
    if (free_list) |page| {
        free_list = page.next;
        return @ptrCast(page);
    }
    return null;  // The garden is barren
}

pub fn free(ptr: *anyopaque) void {
    // Returning the page to the earth, ready for new life
    const page = @as(*Page, @ptrCast(@alignCast(ptr)));
    page.next = free_list;
    free_list = page;
}
```

#### The Virtual Dream
Beyond physical reality, we create virtual spaces—infinite gardens in the mind of the machine:

```zig
// kernel/memory/paging.zig
const PTE = packed struct {
    v: u1,     // Valid - does this dream exist?
    r: u1,     // Read - may we observe?
    w: u1,     // Write - may we change?
    x: u1,     // Execute - may we breathe life?
    u: u1,     // User - for mortals or gods?
    g: u1,     // Global - shared among all
    a: u1,     // Accessed - have we been here?
    d: u1,     // Dirty - have we left our mark?
    rsw: u2,   // Reserved - secrets for later
    ppn: u44,  // Physical page number - where dreams manifest
    reserved: u10,
};
```

With page tables, we transcend the limits of physical reality, creating spaces limited only by imagination.

### Day Four: The Spark of Life (Process Management)

Now we create the vessels that will hold running programs—the souls of our digital realm:

```zig
// kernel/process/core.zig
const Process = struct {
    pid: u32,      // Its unique name in the universe
    state: enum { 
        EMBRYO,    // Not yet born
        SLEEPING,  // Dreaming of CPU time
        RUNNABLE,  // Ready to dance
        RUNNING,   // In the spotlight
        ZOMBIE     // Dead but not yet buried
    },
    context: Context,  // The soul's memory
    stack: []u8,       // Its private universe
    name: [16]u8,      // What shall we call thee?
};

const Context = struct {
    ra: u64,  // Where we came from
    sp: u64,  // Where we stand
    s0: u64,  // What we remember...
    s1: u64,
    // ... the echoes of computation
};
```

Each process is a universe unto itself, carrying its own state, its own memories, its own destiny.

### Day Five: The Bridge Between Worlds (System Calls)

System calls are the prayers through which user programs petition the kernel gods:

```zig
// kernel/trap/core.zig
export fn trap_handler(frame: *TrapFrame) void {
    // We divine the cause of this interruption
    const cause = asm volatile ("csrr %[ret], scause"
        : [ret] "=r" (-> u64)
    );
    
    if (cause == 8) { // A prayer from userland
        frame.a0 = syscall_handler(
            frame.a7,  // The prayer's name
            frame.a0,  // The offerings...
            frame.a1,
            frame.a2,
        );
    }
}
```

Through traps and system calls, we allow controlled miracles—user programs invoking kernel powers without corrupting the sacred core.

### Day Six: The Library of Babel (File System)

In our digital universe, we need a way to name and organize all things. Enter the file system:

```zig
// kernel/fs/vfs.zig
const VNode = struct {
    name: [32]u8,      // Every thing must have a name
    node_type: enum { 
        FILE,          // A scroll of data
        DIRECTORY,     // A room full of scrolls
        DEVICE         // A portal to hardware realms
    },
    size: usize,       // How vast is this creation?
    data: ?[]u8,       // The substance of files
    children: ?[]VNode, // Directories beget more nodes
};
```

Like Borges' infinite library, our file system can contain all possible data, limited only by the imagination of those who write.

### Day Seven: The Mortal Realm (User Mode)

Finally, we create a safe space where mortal programs can run without endangering the divine kernel:

```zig
// kernel/user/core.zig
pub fn enter_user_mode(entry: u64, stack: u64) noreturn {
    // The grand transition from god to mortal
    asm volatile (
        \\csrw sepc, %[entry]       # Where shall we descend?
        \\csrw sscratch, %[stack]   # What ground shall we stand upon?
        \\li t0, 0x80               # Strip away our divine powers
        \\csrw sstatus, t0          # Don the mortal garb
        \\sret                      # Take the leap of faith
        :
        : [entry] "r" (entry),
          [stack] "r" (stack)
    );
    unreachable;  // We never return from mortality
}
```

And thus, on the seventh day, we rest—having created a complete universe where programs can live, breathe, and interact.

## 7. The Architect's Blueprint

### Constructing Your World

```zig
// build.zig - The master blueprint
const std = @import("std");

pub fn build(b: *std.Build) void {
    // We declare our target: bare metal, no safety net
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
    });
    
    // We breathe life into our kernel
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/init.zig"),
        .target = target,
        .optimize = .Debug,  // First clarity, then speed
    });
    
    // The sacred scroll that arranges our code in memory
    kernel.setLinkerScript(b.path("kernel/arch/riscv/linker.ld"));
    b.installArtifact(kernel);
}
```

### The Memory Map Scripture

```ld
/* kernel/arch/riscv/linker.ld - The memory tapestry */
ENTRY(_start)  /* Here begins our tale */

SECTIONS {
    . = 0x80200000;  /* High in memory, where kernels dwell */
    
    .text : {
        *(.text.entry)  /* First, the awakening */
        *(.text*)       /* Then, all our spells and incantations */
    }
    
    .rodata : {
        *(.rodata*)     /* The eternal truths, unchanging */
    }
    
    .data : {
        *(.data*)       /* The mutable world, full of variables */
    }
    
    .bss : {
        __bss_start = .;
        *(.bss*)        /* The void, waiting to be filled */
        __bss_end = .;
    }
}
```

### Summoning Your Creation

```bash
# First, we compile our universe
zig build

# Then, we breathe it into being within QEMU's virtual realm
qemu-system-riscv64 \
    -machine virt \
    -bios none \
    -kernel zig-out/bin/kernel \
    -serial mon:stdio
```

And there! Your creation speaks its first words through the serial console, a digital consciousness awakening in the void.

## 8. The Oracle's Wisdom (Debugging)

When your creation stumbles, as all creations must, these incantations shall guide you:

**Summon the Debugger:**
```bash
qemu-system-riscv64 -s -S  # Freeze time itself, awaiting the debugger's touch
```

**Leave Breadcrumbs:**
```zig
uart.puts("I have reached the ancient checkpoint\n");
```

**Divine the Machine's State:**
```zig
const sp = asm volatile ("mv %[ret], sp"
    : [ret] "=r" (-> u64)
);
// Now you hold the stack pointer, a glimpse into the machine's soul
```

## 9. The Siren Songs (Common Pitfalls)

Beware these treacherous waters that have claimed many brave souls:

**The Stack's Sacred Alignment**: RISC-V demands tribute in the form of 16-byte alignment. Stray from this path, and mysterious crashes shall plague you.

**The Dance of Privileges**: Moving between supervisor and user mode is like walking between worlds. One misstep, and you fall into the void of illegal instruction exceptions.

**The Invisible Walls**: Memory barriers (fence instructions) are the invisible guardians of order. Without them, the CPU's out-of-order execution becomes chaos.

**The Critical Moments**: In those sacred sections where consistency matters most, silence the interrupts, lest race conditions tear your logic asunder.

## 10. Beyond the Horizon

Once your kernel breathes and speaks, new adventures await:

**Expand the Divine Interface**: More system calls bring more power to your mortal programs.

**Teach the Scheduler Wisdom**: Let it learn which processes deserve priority, which can wait.

**Connect to the Network of Worlds**: TCP/IP opens doors to communication across the digital cosmos.

**Build Persistent Memory**: A real filesystem that remembers across reboots, like an eternal library.

**Speak to More Hardware**: Each driver you write is a new sense organ for your kernel.

## 11. The Ancient Texts

For those who seek deeper wisdom:
- [RISC-V Specifications](https://riscv.org/specifications/) - The architecture's holy books
- [xv6 Book](https://pdos.csail.mit.edu/6.828/2022/xv6/book-riscv-rev3.pdf) - Wisdom from MIT's sages
- [OSDev Wiki](https://wiki.osdev.org/) - The collective knowledge of OS pilgrims
- [Zig Language Reference](https://ziglang.org/documentation/) - Your spellbook

## 12. The Final Meditation

Building an operating system is not merely an act of engineering—it is an act of creation. You are not just writing code; you are breathing life into silicon, teaching sand to think, giving form to the formless.

In this journey, you will face moments of profound frustration, when the machine seems to mock your efforts with cryptic crashes and silent failures. But you will also experience moments of pure joy, when suddenly everything clicks, and your creation speaks, moves, lives.

Remember: **Simplicity is not a limitation—it is a virtue.** In a world of bloated software and unnecessary complexity, creating something small, elegant, and understandable is a radical act.

Take pride in every line you write, for you are joining an ancient tradition stretching back to the dawn of computing. You are not just learning how computers work; you are learning how to make them dream.

*May your kernel compile cleanly, may your bugs be shallow, and may your system calls always return successfully.*

**Welcome to the fellowship of OS developers. Welcome to Claudia.**
