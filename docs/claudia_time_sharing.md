

# Claudia Time Sharing
The Claudia scheduler implements a classic time-sharing system,
using preemptive round-robin scheduling with fixed time slices.

This document illustrates how Claudia realizes time sharing,
with diagrams and explanations covering process state transitions,
queue management, context switching, and timer-based preemption.

The design prioritizes simplicity and fairness,
ensuring that all processes receive equal CPU time while keeping the system responsive.

## Process State Transitions
Processes in Claudia transition through multiple states during their lifecycle.
Each state serves a specific purpose and transitions are triggered by well-defined conditions.

```
                ┌────────────┐
                │   UNUSED   │
                └─────┬──────┘
                      │ allocProcess()
                      ▼
                ┌────────────┐
                │   EMBRYO   │ (initializing)
                └─────┬──────┘
                      │ makeRunnable()
                      ▼
      ┌───────────────────────────────────────┐
      │                                       │
      ▼                                       │
┌─────────────┐  schedule()   ┌─────────────┐ │
│  RUNNABLE   │──────────────▶│   RUNNING   │ │
│(ready queue)│               │  (current)  │ │
└─────────────┘◀──────────────└───────┬─────┘ │
      ▲          yield()/timer        │       │
      │                               │       │
      │        ┌─────────────┐        │       │
      └────────│  SLEEPING   │◀───────┘       │
     wakeup()  │(wait queue) │ sleepOn()      │
               └─────────────┘                │
                                              │
               ┌─────────────┐                │
               │   ZOMBIE    │◀───────────────┘
               │  (awaiting  │      exit()
               │   reaping)  │
               └──────┬──────┘
                      │ reapZombies()
                      ▼
               ┌─────────────┐
               │   UNUSED    │
               └─────────────┘
```

## Ready Queue Structure

The Claudia scheduler uses a simple singly-linked list to manage runnable processes.
This structure implements FIFO (First-In-First-Out) ordering to ensure fair CPU time distribution.

```
ready_queue_head ──▶ [Process A] ──▶ [Process B] ──▶ [Process C] ──▶ NULL
                         next            next            next
                                                          ▲
                                                          │
ready_queue_tail ─────────────────────────────────────────┘
```

Operations:
- makeRunnable(proc): Adds to tail (FIFO order)
- dequeueRunnable(): Removes from head (Round-robin)

The ready queue design is intentionally simple.
New processes are always added to the tail of the queue, and the next process to run is always taken from the head.
This ensures all processes receive CPU time in order, preventing starvation.

## Scheduling Flow

The schedule() function is the heart of Claudia's scheduling system.
It determines which process should run next based on the current process state and ready queue status.
```
schedule(make_current_runnable: bool)
│
├─ current_process exists?
│   │
│   ├─ YES: Process current
│   │   │
│   │   ├─ Is IDLE && ready_queue empty?
│   │   │   └─ YES: Continue IDLE
│   │   │
│   │   ├─ make_current_runnable?
│   │   │   └─ YES: Add current to ready_queue
│   │   │
│   │   └─ Select next process
│   │       │
│   │       ├─ ready_queue has candidates?
│   │       │   ├─ YES: context_switch(old, new)
│   │       │   └─ NO: context_switch(old, idle)
│   │       │
│   │       └─ Switch address space (update satp)
│   │
│   └─ NO: Initial boot
│       │
│       ├─ ready_queue has candidates?
│       │   └─ YES: Select that process
│       │
│       └─ NO: Select IDLE process
│
└─ Return selected process
```

Key decisions in the schedule() function:

1. **Current Process Handling**: When make_current_runnable is true, the current process is added back to the ready queue. This is primarily used for timer-based preemption.

2. **IDLE Process Special Case**: When the ready queue is empty, the IDLE process is selected. It executes the WFI (Wait For Interrupt) instruction to enter a low-power state.

3. **Address Space Switching**: During context switches between processes, the SATP register is updated to switch virtual memory spaces.


## Timer-Based Preemption (100Hz = 10ms timeslice)

Claudia uses a 100Hz timer interrupt to implement preemptive multitasking. Each process receives a maximum of 10 milliseconds of CPU time before being forcibly switched to the next process.
```
Time:     0ms    10ms   20ms   30ms   40ms   50ms   60ms
         ┌──────┬──────┬──────┬──────┬──────┬──────┬──────▶
Process: │  A   │  B   │  C   │ IDLE │  A   │  B   │  C
         └──────┴──────┴──────┴──────┴──────┴──────┴──────
```

The timer interrupt processing flow:

1. **Hardware Timer**: Generates an interrupt every 10 milliseconds
2. **trap_handler**: Receives the interrupt and dispatches to the appropriate handler
3. **timer.handleInterrupt**: Executes timer-specific processing
4. **schedule(true)**: Moves the current process back to the ready queue, selects the next process, and performs a context switch

```
┌─────────────┐
│Timer (10ms) │
└──────┬──────┘
       │ Interrupt
       ▼
┌─────────────┐
│trap_handler │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│timer.handleInterrupt│
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────┐
│schedule(true)           │
│ - Current → ready_queue │
│ - Select next           │
│ - context_switch()      │
└─────────────────────────┘
```
This fixed time-slice approach ensures all processes receive fair CPU time and maintains system responsiveness for interactive applications.


## Sleep/Wakeup Mechanism

The sleep/wakeup mechanism allows processes to efficiently wait for specific events without consuming CPU cycles. Processes can wait for I/O completion or resource availability.

**sleepOn(&wait_queue) operation**:
1. Change the current running process state to SLEEPING
2. Add the process to the specified wait queue
3. Call schedule() to switch to another process
```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Process A  │      │  Process A  │      │ Wait Queue  │
│   RUNNING   │ ───▶ │  SLEEPING   │ ───▶ │ ┌─────────┐ │
└─────────────┘      └─────────────┘      │ │    A    │ │
                                          │ └─────────┘ │
                                          └─────────────┘
```

**wakeup(&wait_queue) operation**:
1. Remove all processes from the specified wait queue
2. Change each process state to RUNNABLE
3. Add each process to the ready queue
```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│ Wait Queue  │      │  Process A  │      │ Ready Queue │
│ ┌─────────┐ │      │  Process B  │      │  ┌───┬───┐  │
│ │  A,B,C  │ │ ───▶ │  Process C  │ ───▶ │  │ A │ B │  │
│ └─────────┘ │      │  RUNNABLE   │      │  └───┴───┘  │
└─────────────┘      └─────────────┘      └─────────────┘
```

This mechanism allows processes to wait efficiently for required resources, optimizing overall system CPU utilization.


## Fork Scheduling Behavior

The fork() system call creates a complete copy of the current process. Claudia's scheduler is designed to ensure both parent and child processes receive fair CPU time.

```
Parent Process              Child Process
     │                           │
     │   fork() system call      │
     ├──────────────────────▶    │ Created (EMBRYO)
     │                           │
     │                           │ Initialize
     │                           │
     │                           │ makeRunnable()
     │                           ├──▶ Ready Queue
     │◀─── Return child PID      │
     │                           │
     ▼                           │
  Continue                       │
  execution                    Wait in
                              ready queue
```

Fork execution flow and scheduling impact:

1. **Parent Process**: Issues the fork() system call and begins child creation
2. **Child Creation**: A new process is created in EMBRYO state, copying the parent's memory space, file descriptors, and other state
3. **Child Ready**: makeRunnable() adds the child process to the tail of the ready queue
4. **Parent Continues**: fork() returns the child's PID, and the parent continues execution
5. **Child Execution**: When the scheduler selects the child process, it begins execution (returning 0 from fork())

This design allows the parent to continue immediately after creating the child, while ensuring the child gets a fair opportunity for CPU time.


## Process Table Structure

The process table is a fixed-size array that manages all processes in the system. Claudia supports up to 64 processes, with each slot holding complete process state information.


Process Table (Array):
```
┌─────┬─────────────────────────────────────┐
│ PID │            Process Info             │
├─────┼─────────────────────────────────────┤
│  0  │ IDLE process (special)              │
│  1  │ init (first user process)           │
│  2  │ shell (SLEEPING on tty.read_wait)   │
│  3  │ user_app (RUNNABLE in ready_queue)  │
│  4  │ [UNUSED SLOT]                       │
│ ... │ ...                                 │
│ 63  │ [UNUSED SLOT]                       │
└─────┴─────────────────────────────────────┘
```

current_process ───▶ Process[1] (init)

Key features of the process table:

1. **PID 0 - IDLE Process**: A special process that runs when no other processes are runnable. It executes the WFI instruction to enter power-saving mode.

2. **PID 1 - init Process**: The first user process and ancestor of all other processes. It handles system initialization and becomes the parent of orphaned processes.

3. **Process Slots**: Each slot contains process state, memory mappings, open files, parent-child relationships, and other metadata.

4. **current_process Pointer**: Points to the process currently executing on the CPU. The scheduler updates this pointer to implement process switching.



## Scheduler Characteristics

Algorithm:
  - Round-robin scheduling
  - Fixed 10ms time slice
  - No priority levels (all processes equal)

Performance:
  - O(1) scheduling decision
  - Simple FIFO ready queue
  - Minimal overhead

Features:
  - Preemptive multitasking
  - Fair CPU distribution
  - IDLE process for power saving (WFI instruction)
  - Simple and understandable (~400 lines)

Limitations:
  - No priority scheduling
  - No CPU affinity (single core)
  - No real-time guarantees
  - Fixed time slice

## Context Switch Detail

Context switching is the low-level operation that transfers CPU execution state from one process to another.
Claudia follows RISC-V calling conventions to save and restore only the necessary registers.

```
context_switch(&old_context, &new_context):

  Old Process                            New Process
┌─────────────┐                        ┌─────────────┐
│  Registers  │                        │  Registers  │
│  ra: 0x1234 │     Save to memory     │  ra: 0x5678 │
│  sp: 0x2000 │ ─────────────────────▶ │  sp: 0x3000 │
│  s0-s11: .. │                        │  s0-s11: .. │
│  ...        │ ◀───────────────────── │  ...        │
└─────────────┘   Restore from memory  └─────────────┘
```

Assembly operations:
1. Save all callee-saved registers (ra, sp, s0-s11)
2. Store old stack pointer
3. Load new stack pointer
4. Restore all registers from new context
5. Return to new process's ra (return address)

Context switch details:

1. **Saved Registers**: Following RISC-V calling conventions, only callee-saved registers (ra, sp, s0-s11) are saved. Caller-saved registers are already preserved by the calling code.

2. **Stack Pointer Switch**: One of the most critical operations - each process has its own kernel stack.

3. **Efficient Implementation**: Implemented in assembly language with minimal instructions to complete the context switch.

4. **Transparent Switching**: From a process perspective, the context_switch() call simply returns. In reality, execution resumes in a different process context.

This efficient context switching enables Claudia to perform high-frequency (100Hz) process switching with low overhead.

