# Claudia Kernel
Open the root — and the skeleton of Claudia is revealed.  
Its layout mirrors the kernel itself: each directory a subsystem,  
each syscall a line of truth. Nothing hidden, nothing wasted.


You deserve Lisp, And I, Zig:
```
;; Primitive syscall form
(syscall "open" "/etc/passwd" 0 0)
(syscall "read" fd buffer 128)
(syscall "write" 1 "hello\n" 6)
(syscall "close" fd)
```

