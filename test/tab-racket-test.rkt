#lang racket

(require rackunit
         rackunit/text-ui
         tab-racket/main)

;; Helper to parse a string through the reader
(define (parse-string str)
  (call-with-input-string str read))

;; =============================================================================
;; Basic Parsing Tests
;; =============================================================================

(define basic-parsing-tests
  (test-suite
   "Basic Parsing"

   (test-case "Single token on one line"
     (check-equal? (parse-string "foo") '(foo)))

   (test-case "Multiple tokens on one line become a list"
     (check-equal? (parse-string "+ 1 2") '((+ 1 2))))

   (test-case "Multiple lines at same indentation"
     (check-equal? (parse-string "foo\nbar\nbaz")
                   '(foo bar baz)))

   (test-case "Simple nested structure"
     (check-equal? (parse-string "define\n\tx 1")
                   '((define (x 1)))))

   (test-case "Two-level nesting"
     (check-equal? (parse-string "define\n\tfoo\n\t\tbar")
                   '((define (foo bar)))))

   (test-case "Multiple children at same level"
     (check-equal? (parse-string "define\n\ta\n\tb\n\tc")
                   '((define a b c))))

   (test-case "Empty lines are ignored"
     (check-equal? (parse-string "foo\n\nbar")
                   '(foo bar)))

   (test-case "Blank lines with only whitespace parsed correctly"
     (check-equal? (parse-string "foo\n\t\nbar")
                   '(foo bar)))))

;; =============================================================================
;; Function Definition Tests
;; =============================================================================

(define function-tests
  (test-suite
   "Function Definitions"

   (test-case "Simple function definition"
     (check-equal? (parse-string "define (foo)\n\t1")
                   '((define (foo) 1))))

   (test-case "Function with parameter"
     (check-equal? (parse-string "define (foo x)\n\tx")
                   '((define (foo x) x))))

   (test-case "Function with multiple parameters"
     (check-equal? (parse-string "define (add a b)\n\t+ a b")
                   '((define (add a b) (+ a b)))))

   (test-case "Function with multiple body expressions"
     (check-equal? (parse-string "define (foo)\n\tprintln \"hello\"\n\t42")
                   '((define (foo) (println "hello") 42))))))

;; =============================================================================
;; Control Flow Tests
;; =============================================================================

(define control-flow-tests
  (test-suite
   "Control Flow"

   (test-case "Simple if expression"
     (check-equal? (parse-string "if true\n\t1\n\t0")
                   '((if true 1 0))))

   (test-case "Cond expression"
     (check-equal? (parse-string "cond\n\t(= x 0) 0\n\t(= x 1) 1")
                   '((cond ((= x 0) 0) ((= x 1) 1)))))

   (test-case "Let binding - parsing"
     ;; Use parens for let bindings since [] now means vectors
     (check-equal? (parse-string "let\n\t((x 1))\n\tx")
                   '((let ((x 1)) x))))

   (test-case "Let with multiple bindings - parsing"
     ;; Use parens for let bindings since [] now means vectors
     (check-equal? (parse-string "let\n\t((x 1) (y 2))\n\t+ x y")
                   '((let ((x 1) (y 2)) (+ x y)))))))

;; =============================================================================
;; Clojure-style Literal Tests
;; =============================================================================

(define clojure-literal-tests
  (test-suite
   "Clojure-style Literals"

   (test-case "Empty vector"
     (check-equal? (parse-string "define v []")
                   '((define v #()))))

   (test-case "Vector with elements"
     (check-equal? (parse-string "define v [1 2 3]")
                   '((define v #(1 2 3)))))

   (test-case "Nested vectors"
     (check-equal? (parse-string "define v [[1 2] [3 4]]")
                   '((define v #(#(1 2) #(3 4))))))

   (test-case "Empty hash map"
     (check-equal? (parse-string "define m {}")
                   `((define m ,(hasheq)))))

   (test-case "Hash map with keyword keys"
     (let ([result (parse-string "define m {:a 1 :b 2}")])
       (check-equal? (car (car result)) 'define)
       (check-equal? (cadr (car result)) 'm)
       (check-true (hash? (caddr (car result))))
       (check-equal? (hash-ref (caddr (car result)) ':a) 1)
       (check-equal? (hash-ref (caddr (car result)) ':b) 2)))

   (test-case "Vector in hash map"
     (let ([result (parse-string "define m {:items [1 2 3]}")])
       (check-true (hash? (caddr (car result))))
       (check-equal? (hash-ref (caddr (car result)) ':items) '#(1 2 3))))

   (test-case "Hash map in vector"
     (let ([result (parse-string "define v [{:a 1} {:b 2}]")])
       (check-true (vector? (caddr (car result))))
       (check-true (hash? (vector-ref (caddr (car result)) 0)))))

   (test-case "Mutable vector syntax ![]"
     (let ([result (parse-string "define v ![1 2 3]")])
       ;; Should produce (define v (vector 1 2 3))
       (check-equal? (car (car result)) 'define)
       (check-equal? (cadr (car result)) 'v)
       (check-equal? (car (caddr (car result))) 'vector)))

   (test-case "Mutable hash syntax !{}"
     (let ([result (parse-string "define m !{:a 1}")])
       ;; Should produce (define m (make-hasheq ...))
       (check-equal? (car (car result)) 'define)
       (check-equal? (cadr (car result)) 'm)
       (check-equal? (car (caddr (car result))) 'make-hasheq)))

   (test-case "Bang symbol not confused with mutable literals"
     (let ([result (parse-string "displayln !important")])
       ;; !important should be a symbol, not a mutable literal
       (check-equal? result '((displayln !important)))))))

;; =============================================================================
;; String Handling Tests
;; =============================================================================

(define string-tests
  (test-suite
   "String Handling"

   (test-case "Simple string"
     (check-equal? (parse-string "displayln \"hello\"")
                   '((displayln "hello"))))

   (test-case "String with spaces"
     (check-equal? (parse-string "displayln \"hello world\"")
                   '((displayln "hello world"))))

   (test-case "Multiple strings"
     (check-equal? (parse-string "string-append \"a\" \"b\"")
                   '((string-append "a" "b"))))))

;; =============================================================================
;; Indentation Error Tests
;; =============================================================================

(define error-tests
  (test-suite
   "Indentation Errors"

   (test-case "Spaces cause error"
     (check-exn exn:fail?
                (lambda () (parse-string " foo"))))

   (test-case "Mixed tabs and spaces cause error"
     (check-exn exn:fail?
                (lambda () (parse-string "\t foo"))))))

;; =============================================================================
;; Complex/Integration Tests
;; =============================================================================

(define integration-tests
  (test-suite
   "Integration Tests"

   (test-case "Fibonacci-like structure"
     (check-equal?
      (parse-string "define (fib n)\n\tcond\n\t\t(= n 0) 0\n\t\t(= n 1) 1\n\t\telse\n\t\t\t+ 1 2")
      '((define (fib n) (cond ((= n 0) 0) ((= n 1) 1) (else (+ 1 2)))))))

   (test-case "Multiple top-level definitions"
     (check-equal?
      (parse-string "define x 1\ndefine y 2\n+ x y")
      '((define x 1) (define y 2) (+ x y))))

   (test-case "Deeply nested structure"
     (check-equal?
      (parse-string "a\n\tb\n\t\tc\n\t\t\td")
      '((a (b (c d))))))

   (test-case "Lambda expression"
     (check-equal?
      (parse-string "lambda (x)\n\t+ x 1")
      '((lambda (x) (+ x 1)))))))

;; =============================================================================
;; read-syntax Tests
;; =============================================================================

(define syntax-tests
  (test-suite
   "read-syntax Tests"

   (test-case "read-syntax produces module"
     (define result
       (syntax->datum (call-with-input-string "define x 1"
                                               (lambda (in) (read-syntax 'test in)))))
     (check-equal? (car result) 'module)
     (check-equal? (caddr result) 'racket))))

;; =============================================================================
;; Run all tests
;; =============================================================================

(define all-tests
  (test-suite
   "All tab-racket Tests"
   basic-parsing-tests
   function-tests
   control-flow-tests
   clojure-literal-tests
   string-tests
   error-tests
   integration-tests
   syntax-tests))

(run-tests all-tests 'verbose)
