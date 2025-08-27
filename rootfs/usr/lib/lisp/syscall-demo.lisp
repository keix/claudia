(print "Lisp Syscall API Demo")

(define fd (syscall "open" "test.txt" 577 438))
(define bytes (syscall "write" fd "Claudia Lisp works!"))
(define result (syscall "close" fd))