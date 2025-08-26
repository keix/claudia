;; Simple API test
(print "Testing foreign-call API")

;; Test stdout write
(define msg "Hello from Lisp\n")
(foreign-call "write" 1 msg)

;; Test file operations
(define fd (foreign-call "open" "test.txt" 577 438))
(print "File descriptor:")
(print fd)

(foreign-call "write" fd "Test data\n")
(foreign-call "close" fd)

;; Read it back
(define rfd (foreign-call "open" "test.txt" 0 0))
(define data (foreign-call "read" rfd "" 50))
(print "Read:")
(print data)
(foreign-call "close" rfd)

(print "Done")
