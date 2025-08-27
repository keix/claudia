# Claudia Userland
Enter the shell — and Claudia answers with a single voice.  
A BusyBox-like POSIX core in one binary, and Lisp waiting behind it as the modern extension.

I invoke when you call:
```
claudia:/ # lisp
Minimal Lisp REPL for Claudia
Type 'quit' to exit

> (syscall "write" 1 "Hello, Claudia!\n")
Hello, Claudia!
```
