; Syscall wrapper functions
(defun open (path flags mode)
  (syscall "open" path flags mode))

(defun read (fd count)
  (syscall "read" fd "" count))

(defun write (fd data)
  (syscall "write" fd data))

(defun close (fd)
  (syscall "close" fd))

; Convenience functions
(defun stdout-write (msg)
  (write 1 msg))

(defun stderr-write (msg)
  (write 2 msg))

(print "Syscalls library loaded.")
