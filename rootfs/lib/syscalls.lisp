;; POSIX-like system call wrappers in Lisp
(defun open (path flags mode)
  (syscall "open" path flags mode))

(defun read (fd count)
  (syscall "read" fd "" count))

(defun write (fd data)
  (syscall "write" fd data))

(defun close (fd)
  (syscall "close" fd))
