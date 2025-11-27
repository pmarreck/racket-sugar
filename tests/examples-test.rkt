#lang racket

;; Integration tests that verify all examples run correctly

(require rackunit
         rackunit/text-ui)

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
     (check-true (example-runs? "examples/hello.tab")
                 "hello.tab should run without errors"))

   (test-case "hello.tab output"
     (define-values (output errors exit-code) (run-example "examples/hello.tab"))
     (check-equal? exit-code 0 "hello.tab should exit cleanly")
     (check-true (string-contains? output "Hello")
                 "hello.tab should print Hello"))

   (test-case "fibonacci.tab runs and computes fib(10)=55"
     (define-values (output errors exit-code) (run-example "examples/fibonacci.tab"))
     (check-equal? exit-code 0 "fibonacci.tab should exit cleanly")
     (check-true (string-contains? output "55")
                 "fibonacci.tab should compute fib(10)=55"))

   (test-case "fibonacci-typed.tab runs and computes fib(10)=55"
     (define-values (output errors exit-code) (run-example "examples/fibonacci-typed.tab"))
     (check-equal? exit-code 0 "fibonacci-typed.tab should exit cleanly")
     (check-true (string-contains? output "55")
                 "fibonacci-typed.tab should compute fib(10)=55"))

   (test-case "counter-typed.tab runs and counts correctly"
     (define-values (output errors exit-code) (run-example "examples/counter-typed.tab"))
     (check-equal? exit-code 0 "counter-typed.tab should exit cleanly")
     (check-true (string-contains? output "Count of 'the': 3")
                 "counter-typed.tab should count 'the' as 3")
     (check-true (string-contains? output "Demo complete!")
                 "counter-typed.tab should complete demo"))

   (test-case "arc-cache.tab runs"
     (define-values (output errors exit-code) (run-example "examples/arc-cache.tab"))
     (check-equal? exit-code 0 "arc-cache.tab should exit cleanly"))

   (test-case "arc-cache.tab demo functionality"
     (define-values (output errors exit-code) (run-example "examples/arc-cache.tab"))
     (check-true (string-contains? output "ARC Cache Demo")
                 "arc-cache.tab should print demo header")
     (check-true (string-contains? output "Cache size after 5 inserts (capacity 3): 3")
                 "arc-cache.tab should respect capacity")
     (check-true (string-contains? output "T2 now contains :d: #t")
                 "arc-cache.tab should promote frequently accessed items to T2")
     (check-true (string-contains? output "Found :a: #f")
                 "arc-cache.tab should evict old items")
     (check-true (string-contains? output ":a now in T2 (promoted): #t")
                 "arc-cache.tab should promote ghost list hits")
     (check-true (string-contains? output "Demo complete!")
                 "arc-cache.tab should complete successfully"))

   (test-case "arc-cache-typed.tab runs"
     (define-values (output errors exit-code) (run-example "examples/arc-cache-typed.tab"))
     (check-equal? exit-code 0 "arc-cache-typed.tab should exit cleanly")
     (check-true (string-contains? output "ARC Cache Demo (Typed)")
                 "arc-cache-typed.tab should print typed demo header"))

   (test-case "s3fifo-cache.tab runs"
     (define-values (output errors exit-code) (run-example "examples/s3fifo-cache.tab"))
     (check-equal? exit-code 0 "s3fifo-cache.tab should exit cleanly")
     (check-true (string-contains? output "S3-FIFO Cache Demo")
                 "s3fifo-cache.tab should print demo header"))

   (test-case "s3fifo-cache-typed.tab runs"
     (define-values (output errors exit-code) (run-example "examples/s3fifo-cache-typed.tab"))
     (check-equal? exit-code 0 "s3fifo-cache-typed.tab should exit cleanly")
     (check-true (string-contains? output "S3-FIFO Cache Demo (Typed)")
                 "s3fifo-cache-typed.tab should print typed demo header"))))

;; =============================================================================
;; Run all tests
;; =============================================================================

(run-tests example-tests 'verbose)
