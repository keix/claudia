(define fd (open "/lib/hello.lisp" 0 0))
(if (= fd -1)
    (print "open failed")
    (begin
        (write fd "Hello, World!\n" 14)))
