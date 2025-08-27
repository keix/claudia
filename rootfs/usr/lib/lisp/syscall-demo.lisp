(print "Lisp Syscall API Demo")

(define fd (syscall "open" "test.txt" 577 438))
(print "Created file fd:")
(print fd)

(define bytes (syscall "write" fd "Claudia Lisp works!"))
(print "Wrote bytes:")
(print bytes)

(define result (syscall "close" fd))）

(print "All tests passed!")
