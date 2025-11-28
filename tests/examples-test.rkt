#lang racket

;; Integration tests that verify all examples run correctly

(require rackunit
									rackunit/text-ui)

;; Get the directory containing this test file, then go up one level to project root
(define project-root
		(path->string (simplify-path (build-path (path-only (syntax-source #'here)) ".."))))

;; Build path relative to project root
(define (example-path relative-path)
		(build-path project-root relative-path))

;; Helper to run an example as subprocess and capture output
(define (run-example path)
		(define-values (proc stdout stdin stderr)
				(subprocess #f #f #f (find-executable-path "racket") path))
		(close-output-port stdin)
		(define output (port->string stdout))
		(define errors (port->string stderr))
		(subprocess-wait proc)
		(define exit-code (subprocess-status proc))
		(close-input-port stdout)
		(close-input-port stderr)
		(values output errors exit-code))

;; Helper to check if example runs without error
(define (example-runs? path)
		(define-values (output errors exit-code) (run-example path))
		(= exit-code 0))

;; =============================================================================
;; Example Tests
;; =============================================================================

(define example-tests
		(test-suite
			"Example Programs"

			(test-case "hello.tab runs"
					(check-true (example-runs? (example-path "examples/hello.trk"))
																	"hello.tab should run without errors"))

			(test-case "hello.tab output"
					(define-values (output errors exit-code) (run-example (example-path "examples/hello.trk")))
					(check-equal? exit-code 0 "hello.tab should exit cleanly")
					(check-true (string-contains? output "Hello")
																	"hello.tab should print Hello"))

			(test-case "fibonacci.tab runs and computes fib(10)=55"
					(define-values (output errors exit-code) (run-example (example-path "examples/fibonacci.trk")))
					(check-equal? exit-code 0 "fibonacci.tab should exit cleanly")
					(check-true (string-contains? output "55")
																	"fibonacci.tab should compute fib(10)=55"))

			(test-case "fibonacci-typed.trk runs and computes fib(10)=55"
					(define-values (output errors exit-code) (run-example (example-path "examples/fibonacci-typed.trk")))
					(check-equal? exit-code 0 "fibonacci-typed.trk should exit cleanly")
					(check-true (string-contains? output "55")
																	"fibonacci-typed.trk should compute fib(10)=55"))

			(test-case "counter-typed.trk runs and counts correctly"
					(define-values (output errors exit-code) (run-example (example-path "examples/counter-typed.trk")))
					(check-equal? exit-code 0 "counter-typed.trk should exit cleanly")
					(check-true (string-contains? output "Count of 'the': 3")
																	"counter-typed.trk should count 'the' as 3")
					(check-true (string-contains? output "Demo complete!")
																	"counter-typed.trk should complete demo"))

			(test-case "arc-cache.trk runs"
					(define-values (output errors exit-code) (run-example (example-path "examples/arc-cache.trk")))
					(check-equal? exit-code 0 "arc-cache.trk should exit cleanly")
					(check-true (string-contains? output "ARC Cache Demo (Typed)")
																	"arc-cache.trk should print demo header")
					(check-true (string-contains? output "T2 now contains :d: #t")
																	"arc-cache.trk should promote frequently accessed items to T2")
					(check-true (string-contains? output "Demo complete!")
																	"arc-cache.trk should complete successfully"))

			(test-case "s3fifo-cache.trk runs"
					(define-values (output errors exit-code) (run-example (example-path "examples/s3fifo-cache.trk")))
					(check-equal? exit-code 0 "s3fifo-cache.trk should exit cleanly")
					(check-true (string-contains? output "S3-FIFO Cache Demo (Typed)")
																	"s3fifo-cache.trk should print demo header")
					(check-true (string-contains? output "Demo complete!")
																	"s3fifo-cache.trk should complete successfully"))))

;; =============================================================================
;; Run all tests
;; =============================================================================

(run-tests example-tests 'verbose)
