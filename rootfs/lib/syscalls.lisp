;; System call wrappers for Claudia Lisp

(defun open (path flags mode)
  (foreign-call "open" path flags mode))

(defun read (fd count)
  (foreign-call "read" fd "" count))

(defun write (fd data)
  (foreign-call "write" fd data))

(defun close (fd)
  (foreign-call "close" fd))

;; Higher-level file operations
(defun read-file (path)
  (define fd (open path 0 0))  ; O_RDONLY = 0
  (if (< fd 0)
    #f
    (define content (read fd 1024))
    (close fd)
    content))

(defun write-file (path data)
  (define fd (open path 65 438))  ; O_WRONLY|O_CREAT = 65, mode = 0666 (octal) = 438
  (if (< fd 0)
    #f
    (define result (write fd data))
    (close fd)
    result))

;; Constants for file flags
(define O_RDONLY 0)
(define O_WRONLY 1)
(define O_RDWR 2)
(define O_CREAT 64)
(define O_TRUNC 512)

;; Example usage:
;; (define fd (open "/test.txt" O_RDONLY 0))
;; (print (read fd 100))
;; (close fd)