;; Simple API test for Claudia Lisp
;; Using only supported features: define, foreign-call, print

(print "=== Simple Foreign Call Test ===")

;; Define constants
(define O_RDONLY 0)
(define O_WRONLY 1)
(define O_CREAT 64)
(define O_TRUNC 512)

;; Test 1: Write to stdout
(print "Test 1: Direct write to stdout")
(define stdout 1)
(define msg "Hello from foreign-call!\n")
(define result (foreign-call "write" stdout msg))
(print "Write result:")
(print result)

;; Test 2: Create and write a file
(print "\nTest 2: Create and write file")
(define path "/tmp/test.txt")
(define flags (+ O_WRONLY (+ O_CREAT O_TRUNC)))
(define fd (foreign-call "open" path flags 438))
(print "Open result:")
(print fd)

(if (>= fd 0)
    (define data "Test data from Lisp\n")
    (define write-result (foreign-call "write" fd data))
    (print "Write result:")
    (print write-result)
    (foreign-call "close" fd))

;; Test 3: Read the file back
(print "\nTest 3: Read file")
(define read-fd (foreign-call "open" path O_RDONLY 0))
(print "Open for read:")
(print read-fd)

(if (>= read-fd 0)
    (define content (foreign-call "read" read-fd "" 100))
    (print "Read content:")
    (print content)
    (foreign-call "close" read-fd))

(print "\n=== Test Complete ===")