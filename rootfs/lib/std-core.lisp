; Core definitions
(define true #t)
(define false #f)

(defun not (x) (if x #f #t))
(defun or (a b) (if a a b))
(defun id (x) x)

(defun zero (n) (= n 0))
(defun pos (n) (> n 0))
(defun neg (n) (> 0 n))

(print "Core library loaded.")