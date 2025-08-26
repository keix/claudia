;; File operations example
;; No defun, only define and basic operations

;; File flags
(define O_RDONLY 0)
(define O_WRONLY 1) 
(define O_CREAT 64)
(define O_TRUNC 512)

;; Create a test file
(define test-file "lisp-test.txt")

;; Open for writing
(define fd (foreign-call "open" test-file (+ O_WRONLY (+ O_CREAT O_TRUNC)) 438))
(if (< fd 0)
    (print "Error: Could not create file")
    (print "Created file, fd:"))
(print fd)
