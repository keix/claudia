(define i 1)
(while (<= i 100)
    (cond 
        ((and (= (mod i 3) 0) (= (mod i 5) 0)) (print "FizzBuzz"))
        ((= (mod i 3) 0)                       (print "Fizz"))
        ((= (mod i 5) 0)                       (print "Buzz"))
        (#t                                    (print i)))
    (set i (+ i 1)))
