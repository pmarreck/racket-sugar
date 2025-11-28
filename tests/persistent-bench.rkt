#lang racket/base

;; Benchmark suite for persistent data structures
;; Measures HAMT and PVector performance for optimization tracking

(require racket/format
				 "../hamt/main.rkt"
				 "../pvector/main.rkt")

;; =============================================================================
;; Timing utilities
;; =============================================================================

(define (time-thunk thunk iterations)
	"Run thunk iterations times, return total ms and per-op μs"
	(collect-garbage)
	(collect-garbage)
	(let ([start (current-inexact-milliseconds)])
		(for ([_ (in-range iterations)])
			(thunk))
		(let* ([elapsed (- (current-inexact-milliseconds) start)]
					 [per-op (* 1000 (/ elapsed iterations))])
			(values elapsed per-op))))

(define (format-row label size time-ms per-op-us)
	(printf "~a~a~a~a\n"
					(~a label #:width 30)
					(~a size #:width 12)
					(~a (~r time-ms #:precision 3) #:width 15)
					(~a (~r per-op-us #:precision 3) #:width 15)))

(define (print-header)
	(printf "~a~a~a~a\n"
					(~a "Operation" #:width 30)
					(~a "Size" #:width 12)
					(~a "Time (ms)" #:width 15)
					(~a "Per-op (μs)" #:width 15))
	(displayln (make-string 72 #\-)))

;; =============================================================================
;; HAMT Benchmarks
;; =============================================================================

(define (bench-hamt-build n)
	"Build HAMT of size n"
	(define-values (ms us)
		(time-thunk
		 (lambda ()
			 (for/fold ([h (empty-hamt)])
								 ([i (in-range n)])
				 (hamt-set h i i)))
		 1))
	(values ms us))

(define (bench-hamt-lookup n iterations)
	"Lookup in HAMT of size n"
	(define h (for/fold ([h (empty-hamt)])
											([i (in-range n)])
							(hamt-set h i i)))
	(define-values (ms us)
		(time-thunk
		 (lambda () (hamt-ref h (random n)))
		 iterations))
	(values ms us))

(define (bench-hamt-update n iterations)
	"Update same key in HAMT of size n"
	(define h (for/fold ([h (empty-hamt)])
											([i (in-range n)])
							(hamt-set h i i)))
	(define-values (ms us)
		(time-thunk
		 (lambda () (hamt-set h 0 999))
		 iterations))
	(values ms us))

;; =============================================================================
;; PVector Benchmarks
;; =============================================================================

(define (bench-pvector-build n)
	"Build PVector of size n"
	(define-values (ms us)
		(time-thunk
		 (lambda ()
			 (for/fold ([v (empty-pvector)])
								 ([i (in-range n)])
				 (pvector-push v i)))
		 1))
	(values ms us))

(define (bench-pvector-lookup n iterations)
	"Lookup in PVector of size n"
	(define v (for/fold ([v (empty-pvector)])
											([i (in-range n)])
							(pvector-push v i)))
	(define-values (ms us)
		(time-thunk
		 (lambda () (pvector-ref v (random n)))
		 iterations))
	(values ms us))

(define (bench-pvector-update n iterations)
	"Update index 0 in PVector of size n"
	(define v (for/fold ([v (empty-pvector)])
											([i (in-range n)])
							(pvector-push v i)))
	(define-values (ms us)
		(time-thunk
		 (lambda () (pvector-set v 0 999))
		 iterations))
	(values ms us))

(define (bench-pvector-push n iterations)
	"Push to PVector of size n"
	(define v (for/fold ([v (empty-pvector)])
											([i (in-range n)])
							(pvector-push v i)))
	(define-values (ms us)
		(time-thunk
		 (lambda () (pvector-push v 999))
		 iterations))
	(values ms us))

;; =============================================================================
;; Run benchmarks
;; =============================================================================

(define (run-all-benchmarks)
	(displayln "")
	(displayln "========================================")
	(displayln "  PERSISTENT DATA STRUCTURE BENCHMARKS")
	(displayln "========================================")
	(displayln "")

	;; HAMT
	(displayln "--- HAMT (Hash Array Mapped Trie) ---")
	(displayln "64-way branching, O(log64 n) operations")
	(displayln "")

	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define-values (ms us) (bench-hamt-build n))
		(format-row "HAMT build" n ms us))

	(displayln "")
	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define iters (min 10000 n))
		(define-values (ms us) (bench-hamt-lookup n iters))
		(format-row "HAMT lookup" n ms us))

	(displayln "")
	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define iters (min 10000 n))
		(define-values (ms us) (bench-hamt-update n iters))
		(format-row "HAMT update" n ms us))

	(displayln "")
	(displayln "")

	;; PVector
	(displayln "--- PVector (Persistent Vector) ---")
	(displayln "32-way branching, O(log32 n) operations")
	(displayln "")

	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define-values (ms us) (bench-pvector-build n))
		(format-row "PVector build" n ms us))

	(displayln "")
	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define iters (min 10000 n))
		(define-values (ms us) (bench-pvector-lookup n iters))
		(format-row "PVector lookup" n ms us))

	(displayln "")
	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define iters (min 10000 n))
		(define-values (ms us) (bench-pvector-update n iters))
		(format-row "PVector update" n ms us))

	(displayln "")
	(print-header)

	(for ([n '(100 1000 10000 100000)])
		(define iters (min 10000 n))
		(define-values (ms us) (bench-pvector-push n iters))
		(format-row "PVector push" n ms us))

	(displayln "")
	(displayln "========================================")
	(displayln "  Expected: per-op time roughly constant")
	(displayln "  (slight increase for larger sizes is")
	(displayln "   O(log n) behavior)")
	(displayln "========================================"))

(module+ main
	(run-all-benchmarks))
