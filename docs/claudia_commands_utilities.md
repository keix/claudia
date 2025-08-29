# Claudia Commands and Utilities
A shell is but a whisper to the kernel.  
Each command, a small spell, shaping the machine.

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
| `ls` | List directory contents | `ls [directory]` | Color support, shows file types |
| `mkdir` | Create directory | `mkdir <directory>...` | Creates in VFS |
| `pid` | Show current process ID | `pid` | Shows current PID |
| `pwd` | Print working directory | `pwd` | Shows absolute path |
| `seek` | Test file seeking | `seek` | File seek demonstration |
| `touch` | Create files or update timestamps | `touch <file>...` | Creates empty files |

## Command Details

### File Operations
- **cat**: Reads and displays file contents to stdout
- **touch**: Creates empty files in VFS, updates timestamps if exists
- **fstat**: Shows file metadata (type, size, permissions)

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

### Shell Built-ins
- **echo**: Prints arguments to stdout
- **help**: Lists all available commands
- **exit**: Exits the shell and returns to init

## Planned Commands

| Command | Description | Priority |
|---------|-------------|----------|
| `cp` | Copy files | High |
| `rm` | Remove files | High |
| `mv` | Move/rename files | Medium |
| `ps` | List processes | Medium |
| `kill` | Send signals to processes | Low |
| `head` | Display first lines | Low |
| `tail` | Display last lines | Low |
| `wc` | Count lines/words/chars | Low |