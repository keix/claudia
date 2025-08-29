# Claudia Lisp Language Specification

## Table of Contents

1. [Overview](#overview)
2. [Lexical Structure](#lexical-structure)
3. [Data Types](#data-types)
4. [Special Forms](#special-forms)
5. [Built-in Functions](#built-in-functions)
6. [Evaluation Rules](#evaluation-rules)
7. [Memory Model](#memory-model)
8. [Standard Library](#standard-library)
9. [Implementation Limits](#implementation-limits)
10. [Examples](#examples)

## Overview

Claudia Lisp is a minimal Lisp interpreter embedded in the Claudia shell. It provides a simple, educational implementation of core Lisp concepts within the constraints of a small operating system.

### Design Goals

1. **Minimal Memory Footprint**: Runs within 32KB of memory
2. **Educational Clarity**: Simple implementation for learning
3. **Core Lisp Features**: Essential forms and functions
4. **REPL Integration**: Interactive development in the shell

### Language Family

Claudia Lisp follows Scheme/Lisp-1 conventions:
- Single namespace for functions and variables
- Lexical scoping (limited implementation)
- Tail recursion (not optimized)
- First-class functions

## Lexical Structure

### Comments

```lisp
; This is a comment that extends to end of line
(+ 1 2)  ; Comments can appear after code
```

### Tokens

1. **Numbers**: Signed 64-bit integers
   ```lisp
   42
   -17
   0
   ```

2. **Symbols**: Alphanumeric identifiers and operators
   ```lisp
   foo
   list?
   +
   <=
   ```

3. **Booleans**: True and false literals
   ```lisp
   #t  ; true
   #f  ; false
   ```

4. **Lists**: Parenthesized sequences
   ```lisp
   ()              ; empty list (nil)
   (1 2 3)         ; list of numbers
   (+ 1 (* 2 3))   ; nested lists
   ```

5. **Strings**: Double-quoted text (limited support)
   ```lisp
   "Hello, World!"
   ```

### Whitespace

Space, tab, newline, and carriage return are treated as delimiters.

## Data Types

### Primitive Types

1. **Number**: 64-bit signed integers
   ```zig
   Number: i64
   ```

2. **Symbol**: Interned strings for identifiers
   ```zig
   Symbol: []const u8
   ```

3. **Boolean**: True or false values
   ```zig
   Boolean: bool
   ```

4. **Nil**: Empty list or null value
   ```zig
   Nil: void
   ```

### Composite Types

1. **List**: Linked list of values
   ```zig
   List: struct {
       items: [32]LispValue,
       len: usize,
   }
   ```

2. **Function**: User-defined functions
   ```zig
   Function: struct {
       params: *List,
       body: *LispValue,
       env: *Environment,
   }
   ```



## Special Forms

### define

Binds a value to a symbol in the current environment.

```lisp
(define x 42)           ; bind variable
(define (f x) (+ x 1))  ; syntactic sugar for function definition
```

Equivalent expansion:
```lisp
(define f (lambda (x) (+ x 1)))
```

### lambda

Creates an anonymous function.

```lisp
(lambda (x) (* x x))              ; square function
(lambda (x y) (+ x y))            ; addition function
((lambda (x) (+ x 1)) 5)          ; immediate application => 6
```

### defun

Defines a named function (convenience form).

```lisp
(defun square (x) (* x x))
```

### if

Conditional evaluation.

```lisp
(if (> x 0)
    "positive"
    "non-positive")
```

Only the selected branch is evaluated.

### quote

Prevents evaluation of an expression.

```lisp
(quote x)          ; => x (symbol)
(quote (1 2 3))    ; => (1 2 3) (list)
```

## Built-in Functions

### Arithmetic

```lisp
(+ a b ...)      ; addition (variadic)
(- a b)          ; subtraction
(* a b ...)      ; multiplication (variadic)
(/ a b)          ; integer division
(% a b)          ; modulo
```

Examples:
```lisp
(+ 1 2 3)        ; => 6
(- 10 3)         ; => 7
(* 2 3 4)        ; => 24
(/ 10 3)         ; => 3
(% 10 3)         ; => 1
```

### Comparison

```lisp
(= a b)          ; numeric equality
(< a b)          ; less than
(> a b)          ; greater than
(<= a b)         ; less than or equal
(>= a b)         ; greater than or equal
```

### List Operations

```lisp
(cons a lst)     ; construct list with a as head
(car lst)        ; first element (head)
(cdr lst)        ; rest of list (tail)
(list a b ...)   ; create list from elements
```

Examples:
```lisp
(cons 1 '(2 3))  ; => (1 2 3)
(car '(1 2 3))   ; => 1
(cdr '(1 2 3))   ; => (2 3)
(list 1 2 3)     ; => (1 2 3)
```

### Logical Operations

```lisp
(not x)          ; logical negation
(and a b ...)    ; logical and (short-circuit)
(or a b ...)     ; logical or (short-circuit)
```

### I/O Functions

```lisp
(print expr)     ; print expression and return it
(load "file")    ; load and evaluate file
```

## Evaluation Rules

### Evaluation Order

1. **Numbers**: Self-evaluating
   ```lisp
   42  ; => 42
   ```

2. **Booleans**: Self-evaluating
   ```lisp
   #t  ; => #t
   ```

3. **Symbols**: Look up in environment
   ```lisp
   x   ; => value bound to x
   ```

4. **Lists**: Apply first element to rest
   ```lisp
   (+ 1 2)  ; => 3
   ```

### Function Application

1. Evaluate function position
2. Evaluate arguments left-to-right
3. Apply function to arguments

```lisp
((lambda (x) (* x x)) 5)
; 1. Evaluate lambda => function
; 2. Evaluate 5 => 5  
; 3. Apply function to 5 => 25
```

### Special Form Evaluation

Special forms have custom evaluation rules:

```lisp
(if #f 
    (/ 1 0)      ; not evaluated
    "safe")      ; evaluated => "safe"
```

## Memory Model

### Memory Layout

```
Global Memory (32KB):
+------------------+
|  Global Buffer   |  <- Fixed allocation pool
+------------------+
|  Environments    |  <- Variable bindings
+------------------+
|  Lists           |  <- Cons cells
+------------------+
|  Functions       |  <- Lambda closures
+------------------+
```

### Allocation Strategy

- Bump allocator with alignment
- No garbage collection
- Memory reset between REPL iterations
- Maximum 32KB total usage

### Environment Model

```lisp
Global Environment:
  + -> <builtin-function>
  - -> <builtin-function>
  x -> 42
  |
  +-- Local Environment (function call):
      n -> 5
      factorial -> <function>
```

## Standard Library

Located at `/lib/std.lisp`:

```lisp
; Boolean constants
(define true #t)
(define false #f)

; Logical functions
(defun not (x) (if x #f #t))
(defun or (a b) (if a a b))
(defun and (a b) (if a b #f))

; List predicates
(defun null (x) (= x '()))
(defun pair (x) (and (list? x) (not (null? x))))

; etc...
```

## Implementation Limits

### Hard Limits

1. **Memory**: 32KB total allocation
2. **List Size**: Maximum 32 elements
3. **Recursion**: ~100 levels (stack limited)
4. **Symbol Length**: 255 characters
5. **Environment Depth**: ~10 levels
6. **Input Line**: 512 characters

### Soft Limits

1. **Number Range**: -2^63 to 2^63-1
2. **Function Parameters**: Recommended < 10
3. **Expression Nesting**: Recommended < 20

## Examples

### Basic Arithmetic

```lisp
lisp> (+ 1 2 3)
6
lisp> (* (+ 2 3) (- 10 6))
20
```

### Function Definition

```lisp
lisp> (defun square (x) (* x x))
<function>
lisp> (square 5)
25
```

### FizzBuzz

```lisp
lisp> (defun fizzbuzz (n)
        (defun fb (i)
          (if (> i n)
              '()
              (cons
                (if (= (% i 15) 0) "FizzBuzz"
                    (if (= (% i 3) 0) "Fizz"
                        (if (= (% i 5) 0) "Buzz" i)))
                (fb (+ i 1)))))
        (fb 1))
<function>
lisp> (fizzbuzz 15)
(1 2 "Fizz" 4 "Buzz" "Fizz" 7 8 "Fizz" "Buzz" 11 "Fizz" 13 14 "FizzBuzz")
```

## Future Enhancements

### Planned Features

1. **Proper Lexical Scoping**: Full closure support
2. **Tail Call Optimization**: Eliminate recursion limits
3. **Macros**: Code transformation support
4. **Strings**: Full string manipulation
5. **Error Handling**: try/catch mechanisms
6. **Module System**: Namespace support

### Potential Optimizations

1. **Garbage Collection**: Mark-and-sweep or generational
2. **Bytecode Compilation**: Faster execution
3. **Hash Table Symbols**: O(1) lookup
4. **Variable-Length Lists**: Remove 32-element limit

## Debugging

### REPL Commands

```lisp
lisp> (load "/lib/std.lisp")    ; Load standard library
lisp> (define debug #t)          ; Enable debug mode (future)
lisp> (quit)                     ; Exit REPL
```

### Common Errors

1. **Unbound Variable**
   ```lisp
   lisp> x
   Error: Unbound variable: x
   ```

2. **Type Mismatch**
   ```lisp
   lisp> (+ 1 "two")
   Error: Type mismatch in +
   ```

3. **Arity Mismatch**
   ```lisp
   lisp> (defun f (x y) (+ x y))
   lisp> (f 1)
   Error: Wrong number of arguments
   ```

4. **Memory Exhausted**
   ```lisp
   lisp> (define x '(1 2 3 ... 40 elements ...))
   Error: Out of memory
   ```

## References

- Structure and Interpretation of Computer Programs (SICP)
- Lisp 1.5 Programmer's Manual
- Scheme R5RS Specification
- Common Lisp the Language