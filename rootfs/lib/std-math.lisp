; Math functions
(defun even (n) (= 0 (mod n 2)))
(defun odd (n) (= 1 (mod n 2)))

;(defun abs (n) (if (neg n) (- 0 n) n))
(defun inc (n) (+ n 1))
(defun dec (n) (- n 1))
(defun sq (x) (* x x))
(defun min (a b) (if (> a b) b a))
(defun max (a b) (if (> a b) a b))

(print "Math library loaded.")
