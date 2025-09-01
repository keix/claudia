# Claudia Commands and Utilities
A shell is but a whisper to the kernel.  
Each command, a small spell, shaping the machine.

This document describes the commands available in Claudia's shell environment. All commands are implemented as part of the shell binary (busybox-style) and executed within the shell process itself.

## Process Model

Claudia implements a simplified UNIX process model:
- **init (PID 1)**: The first process, started by the kernel
- **shell**: Currently runs as the init process itself (not a separate process)
- **Built-in commands**: Execute directly within the shell process
- **fork()**: Creates a child process that shares the parent's memory space (simplified implementation)
- **exec()**: Currently only supports executing "shell" - replaces the process image

Note: The current implementation has limitations:
- Child processes share the parent's page table (no copy-on-write)
- exec() only supports loading the shell binary
- No support for external programs yet

## Available Commands

| Command | Description | Usage | Notes |
|---------|-------------|-------|-------|
| `cat` | Display file contents | `cat <file>...` | Supports multiple files |
| `cd` | Change directory | `cd [directory]` | No arg = home dir |
| `date` | Display current date and time | `date` | Uses hardware timer (CSR readTime) |
| `echo` | Print text | `echo [text]...` | Basic text output |
| `exit` | Exit shell | `exit` | Returns to init |
| `fstat` | Show file information | `fstat <file>` | Shows type, size, permissions |
| `help` | List available commands | `help` | Shows command list |
| `id` | Show user/group IDs | `id` | Always shows root (uid=0 gid=0) |
| `lisp` | Run Lisp interpreter | `lisp [file]` | Interactive REPL or run file |
| `ls` | List directory contents | `ls [directory]` | Color support, shows file types |
| `mkdir` | Create directory | `mkdir <directory>...` | Creates in VFS |
| `pid` | Show current process ID | `pid` | Shows current PID |
| `ppid` | Show parent process ID | `ppid` | Shows parent PID |
| `pwd` | Print working directory | `pwd` | Shows absolute path |
| `rm` | Remove files or directories | `rm <file>...` | Removes from VFS |
| `seek` | Demonstrate file seeking | `seek` | Shows lseek functionality |
| `sleep` | Delay for specified seconds | `sleep <seconds>` | Uses nanosleep system call |
| `touch` | Create files or update timestamps | `touch <file>...` | Creates empty files |

## Command Details

### File Operations
- **cat**: Reads and displays file contents to stdout
- **touch**: Creates empty files in VFS, updates timestamps if exists
- **fstat**: Shows file metadata (type, size, permissions)
- **rm**: Removes files or empty directories from VFS

### Directory Operations  
- **ls**: Lists directory contents with color coding
  - Blue: Directories (with `/` suffix)
  - Green: Executable files (.lisp files)
  - Yellow: Device files
  - Regular: Normal files
- **cd**: Changes current working directory
- **pwd**: Prints current working directory path
- **mkdir**: Creates new directories in VFS

### System Information
- **date**: Shows current date/time using hardware timer
- **id**: Shows user and group IDs (always root in single-user system)
- **pid**: Displays current process ID
- **ppid**: Displays parent process ID

### Process Management
- **fork_test**: Demonstrates fork system call
- **fork_demo**: More advanced fork demonstration
- **sleep**: Suspends execution for specified number of seconds
- Note: `fork()` creates a child process, `exec()` replaces the current process image

### Programming
- **lisp**: Launches the Lisp interpreter
  - Without arguments: Interactive REPL mode
  - With filename: Executes Lisp script

### Shell Built-ins
- **echo**: Prints arguments to stdout
- **help**: Lists all available commands
- **exit**: Exits the shell and returns to init
- **seek**: Demonstrates file seeking operations

## Planned Commands

| Command | Description | Priority |
|---------|-------------|----------|
| `cp` | Copy files | High |
| `mv` | Move/rename files | Medium |
| `ps` | List processes | Medium |
| `wait` | Wait for child process | Medium |
| `kill` | Send signals to processes | Low |
| `head` | Display first lines | Low |
| `tail` | Display last lines | Low |
| `wc` | Count lines/words/chars | Low |
| `chmod` | Change file permissions | Low |
| `ln` | Create links | Low |