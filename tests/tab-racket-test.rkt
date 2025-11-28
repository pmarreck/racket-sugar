#lang racket

(require rackunit
									rackunit/text-ui
									tab-racket/main
									(prefix-in hamt: "../hamt/main.rkt"))

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

			;; NOTE: [] and {} now produce runtime expressions (pvector ...) and (hamt ...)
			;; rather than read-time literal values. This allows variables to work inside literals.

			(test-case "Empty vector"
					(let ([result (parse-string "define v []")])
							(check-equal? (car (car result)) 'define)
							(check-equal? (cadr (car result)) 'v)
							;; Should produce (pvector) expression
							(check-equal? (caddr (car result)) '(pvector))))

			(test-case "Vector with elements"
					(let ([result (parse-string "define v [1 2 3]")])
							(check-equal? (car (car result)) 'define)
							(check-equal? (cadr (car result)) 'v)
							;; Should produce (pvector 1 2 3) expression
							(check-equal? (caddr (car result)) '(pvector 1 2 3))))

			(test-case "Nested vectors"
					(let ([result (parse-string "define v [[1 2] [3 4]]")])
							(check-equal? (car (car result)) 'define)
							(check-equal? (cadr (car result)) 'v)
							;; Should produce nested (pvector ...) expressions
							(let ([def-body (caddr (car result))])
									(check-equal? (car def-body) 'pvector)
									(check-equal? (cadr def-body) '(pvector 1 2))
									(check-equal? (caddr def-body) '(pvector 3 4)))))

			(test-case "Empty hash map"
					(let ([result (parse-string "define m {}")])
							(check-equal? (car (car result)) 'define)
							(check-equal? (cadr (car result)) 'm)
							;; Should produce (hamt) expression
							(check-equal? (caddr (car result)) '(hamt))))

			(test-case "Hash map with keyword keys"
					(let ([result (parse-string "define m {:a 1 :b 2}")])
							(check-equal? (car (car result)) 'define)
							(check-equal? (cadr (car result)) 'm)
							;; Should produce (hamt ':a 1 ':b 2) - keywords are quoted
							(let ([def-body (caddr (car result))])
									(check-equal? (car def-body) 'hamt)
									(check-equal? (cadr def-body) '':a)
									(check-equal? (caddr def-body) 1)
									(check-equal? (cadddr def-body) '':b))))

			(test-case "Vector in hash map"
					(let ([result (parse-string "define m {:items [1 2 3]}")])
							;; Should produce (hamt ':items (pvector 1 2 3))
							(let ([def-body (caddr (car result))])
									(check-equal? (car def-body) 'hamt)
									(check-equal? (cadr def-body) '':items)
									(check-equal? (caddr def-body) '(pvector 1 2 3)))))

			(test-case "Hash map in vector"
					(let ([result (parse-string "define v [{:a 1} {:b 2}]")])
							;; Should produce (pvector (hamt ':a 1) (hamt ':b 2))
							(let ([def-body (caddr (car result))])
									(check-equal? (car def-body) 'pvector)
									(check-equal? (car (cadr def-body)) 'hamt)
									(check-equal? (car (caddr def-body)) 'hamt))))

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
;; Runtime Variable Evaluation Tests
;; =============================================================================

(define runtime-literal-tests
		(test-suite
			"Runtime Variable Evaluation in Literals"

			;; These tests verify that variables inside {} and [] are evaluated at runtime,
			;; not captured as symbols at read-time.

			(test-case "Variable in hash map literal - should produce runtime expression"
					;; When we write {:key x} where x is a variable, it should parse to
					;; a form that evaluates x at runtime, not store the symbol 'x
					(let ([result (parse-string "define m {:val x}")])
							;; The value should be a runtime expression, not a literal HAMT
							;; After the fix, this should produce (define m (hamt ':val x))
							;; Currently it produces a literal HAMT with 'x as the value (FAILS)
							(let ([def-body (caddr (car result))])
									;; Should be a list starting with 'hamt (runtime expression)
									(check-true (list? def-body)
																					"Hash literal with variable should produce a list expression")
									(check-equal? (car def-body) 'hamt
																							"Should produce (hamt ...) form for runtime evaluation"))))

			(test-case "Variable in vector literal - should produce runtime expression"
					;; When we write [x y z] where these are variables, it should parse to
					;; a form that evaluates them at runtime
					(let ([result (parse-string "define v [a b c]")])
							(let ([def-body (caddr (car result))])
									;; Should be a list starting with 'pvector (runtime expression)
									(check-true (list? def-body)
																					"Vector literal with variables should produce a list expression")
									(check-equal? (car def-body) 'pvector
																							"Should produce (pvector ...) form for runtime evaluation"))))

			(test-case "Mixed literals and variables in hash map"
					;; {:a 1 :b x} should evaluate x but keep 1 as literal
					(let ([result (parse-string "define m {:a 1 :b x}")])
							(let ([def-body (caddr (car result))])
									(check-true (list? def-body))
									(check-equal? (car def-body) 'hamt))))

			(test-case "Mixed literals and variables in vector"
					;; [1 x 3] should evaluate x but keep 1 and 3 as literals
					(let ([result (parse-string "define v [1 x 3]")])
							(let ([def-body (caddr (car result))])
									(check-true (list? def-body))
									(check-equal? (car def-body) 'pvector))))

			(test-case "Nested structures with variables"
					;; {:items [x y]} should produce nested runtime expressions
					(let ([result (parse-string "define m {:items [x y]}")])
							(let ([def-body (caddr (car result))])
									(check-true (list? def-body))
									(check-equal? (car def-body) 'hamt))))

			(test-case "Function call result in literal"
					;; {:result (+ 1 2)} should evaluate the expression
					(let ([result (parse-string "define m {:result (+ 1 2)}")])
							(let ([def-body (caddr (car result))])
									(check-true (list? def-body))
									(check-equal? (car def-body) 'hamt))))))

;; =============================================================================
;; Self-Evaluating Keyword Tests
;; =============================================================================

(define self-evaluating-keyword-tests
		(test-suite
			"Self-Evaluating Keywords"

			;; Keywords (symbols starting with :) should be auto-quoted by the reader,
			;; making them self-evaluating like in Clojure/Ruby/Elixir.
			;; This allows writing (hamt-ref m :key) instead of (hamt-ref m ':key)

			(test-case "Keyword in function call is auto-quoted"
					;; (hamt-ref m :key) should parse with :key quoted
					(let ([result (parse-string "hamt-ref m :key")])
							;; Should produce (hamt-ref m ':key) - keyword is quoted
							;; Position: 0=hamt-ref, 1=m, 2=:key
							(check-equal? (caddr (car result)) '':key
																					"Keyword :key should be auto-quoted in function call")))

			(test-case "Multiple keywords in function call"
					;; (hamt-set m :key :value) - both should be quoted
					(let ([result (parse-string "hamt-set m :key :value")])
							(let ([expr (car result)])
									;; Position: 0=hamt-set, 1=m, 2=:key, 3=:value
									(check-equal? (list-ref expr 2) '':key)
									(check-equal? (list-ref expr 3) '':value))))

			(test-case "Keyword as standalone expression"
					;; Just :foo by itself should be quoted
					(let ([result (parse-string ":foo")])
							(check-equal? (car result) '':foo
																					"Standalone keyword should be auto-quoted")))

			(test-case "Keyword in nested expression"
					;; (eq? x :done) - :done should be quoted
					;; Position: 0=eq?, 1=x, 2=:done
					(let ([result (parse-string "eq? x :done")])
							(check-equal? (caddr (car result)) '':done)))

			(test-case "Keyword vs regular symbol"
					;; :key should be quoted, but key should not
					(let ([result (parse-string "list :key key")])
							(let ([expr (car result)])
									;; Position: 0=list, 1=:key, 2=key
									;; :key is quoted (keyword)
									(check-equal? (cadr expr) '':key)
									;; key is not quoted (variable reference)
									(check-equal? (caddr expr) 'key))))

			(test-case "Keywords still work in hash literals"
					;; {:a 1} should still work - keywords quoted in literals
					(let ([result (parse-string "define m {:a 1}")])
							(let ([def-body (caddr (car result))])
									(check-equal? (car def-body) 'hamt)
									(check-equal? (cadr def-body) '':a))))

			(test-case "Keywords still work in vector literals"
					;; [:a :b :c] - all keywords should be quoted
					(let ([result (parse-string "define v [:a :b :c]")])
							(let ([def-body (caddr (car result))])
									(check-equal? (car def-body) 'pvector)
									(check-equal? (cadr def-body) '':a)
									(check-equal? (caddr def-body) '':b)
									(check-equal? (cadddr def-body) '':c))))))

;; =============================================================================
;; Infix Operator Tests (~func syntax)
;; =============================================================================

(define infix-operator-tests
		(test-suite
			"Infix Operator Syntax (~func)"

			;; The ~func syntax transforms to Racket's dot-infix: (a . func . b)
			;; This allows (a ~+ b) instead of (+ a b) for binary operations

			(test-case "Simple infix addition"
					;; (1 ~+ 2) should parse to (1 . + . 2) which Racket evaluates as (+ 1 2)
					(let ([result (parse-string "(1 ~+ 2)")])
							(check-equal? (car result) '(1 . + . 2)
																					"~+ should transform to dot-infix notation")))

			(test-case "Simple infix subtraction"
					(let ([result (parse-string "(10 ~- 3)")])
							(check-equal? (car result) '(10 . - . 3))))

			(test-case "Simple infix comparison"
					(let ([result (parse-string "(x ~< y)")])
							(check-equal? (car result) '(x . < . y))))

			(test-case "Infix with function name"
					;; (a ~mod b) -> (a . mod . b)
					(let ([result (parse-string "(a ~mod b)")])
							(check-equal? (car result) '(a . mod . b))))

			(test-case "Nested infix expressions"
					;; (1 ~+ (2 ~* 3)) -> (1 . + . (2 . * . 3))
					(let ([result (parse-string "(1 ~+ (2 ~* 3))")])
							(check-equal? (car result) '(1 . + . (2 . * . 3)))))

			(test-case "Infix arrow for type annotations"
					;; (Integer ~-> Integer) -> (Integer . -> . Integer)
					(let ([result (parse-string "(Integer ~-> Integer)")])
							(check-equal? (car result) '(Integer . -> . Integer))))

			(test-case "Infix in tab-indented code"
					;; Multi-line with infix
					(let ([result (parse-string "define x\n\t(1 ~+ 2)")])
							(check-equal? (car result) '(define x (1 . + . 2)))))

			(test-case "Infix with variables"
					(let ([result (parse-string "(a ~+ b)")])
							(check-equal? (car result) '(a . + . b))))

			(test-case "Multiple infix in one expression"
					;; ((a ~+ b) ~* c) -> ((a . + . b) . * . c)
					(let ([result (parse-string "((a ~+ b) ~* c)")])
							(check-equal? (car result) '((a . + . b) . * . c))))

			(test-case "Tilde not followed by identifier stays as-is"
					;; ~ by itself or ~123 should not transform
					;; (For now, just test that valid infix works - edge cases later)
					(let ([result (parse-string "(1 ~+ 2)")])
							(check-true (pair? (car result)))))))

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
			syntax-tests
			runtime-literal-tests
			self-evaluating-keyword-tests
			infix-operator-tests))

(run-tests all-tests 'verbose)
