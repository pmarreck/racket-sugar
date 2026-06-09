#lang racket

;; Performance benchmark suite for racket-sugar data structures
;; Tests O-notation behavior by measuring time at different scales
;; Logs results to TSV file with % diff from previous run

(require racket/format
				 racket/date
				 racket/file)

;; =============================================================================
;; TSV Logging Infrastructure
;; =============================================================================

(define PERF_LOG_FILE "perf-log.tsv")

;; TSV format: datetime\tbenchmark\tsize\ttime_ms\tper_op_us\tprev_per_op_us\tpct_diff

(define (get-timestamp)
	(define d (current-date))
	(format "~a-~a-~a ~a:~a:~a"
					(date-year d)
					(~a (date-month d) #:min-width 2 #:pad-string "0")
					(~a (date-day d) #:min-width 2 #:pad-string "0")
					(~a (date-hour d) #:min-width 2 #:pad-string "0")
					(~a (date-minute d) #:min-width 2 #:pad-string "0")
					(~a (date-second d) #:min-width 2 #:pad-string "0")))

(define (ensure-log-header)
	"Create TSV file with header if it doesn't exist"
	(unless (file-exists? PERF_LOG_FILE)
		(call-with-output-file PERF_LOG_FILE
			(lambda (out)
				(displayln "datetime\tbenchmark\tsize\ttime_ms\tper_op_us\tprev_per_op_us\tpct_diff" out)))))

(define (read-previous-runs)
	"Read previous runs from TSV, return hash of (benchmark, size) -> per_op_us"
	(if (file-exists? PERF_LOG_FILE)
			(let ([lines (file->lines PERF_LOG_FILE)])
				(for/fold ([h (hash)])
									([line (cdr lines)]  ; skip header
									 #:when (not (string=? line "")))
					(let* ([parts (string-split line "\t")]
								 [benchmark (list-ref parts 1)]
								 [size (string->number (list-ref parts 2))]
								 [per-op (string->number (list-ref parts 4))])
						(if (and benchmark size per-op)
								(hash-set h (cons benchmark size) per-op)
								h))))
			(hash)))

(define (log-result benchmark-name size time-ms per-op-us prev-results)
	"Log a benchmark result to TSV and print % diff"
	(define key (cons benchmark-name size))
	(define prev-per-op (hash-ref prev-results key #f))
	(define pct-diff
		(if (and prev-per-op (> prev-per-op 0))
				(* 100 (/ (- per-op-us prev-per-op) prev-per-op))
				0.0))
	(define pct-str
		(if (and prev-per-op (> prev-per-op 0))
				(format "~a%" (~r pct-diff #:precision 1 #:sign '+ #:notation 'positional))
				"N/A"))

	;; Append to TSV
	(call-with-output-file PERF_LOG_FILE
		#:exists 'append
		(lambda (out)
			(fprintf out "~a\t~a\t~a\t~a\t~a\t~a\t~a\n"
							 (get-timestamp)
							 benchmark-name
							 size
							 (~r time-ms #:precision 3)
							 (~r per-op-us #:precision 3)
							 (if prev-per-op (~r prev-per-op #:precision 3) "")
							 (if prev-per-op (~r pct-diff #:precision 1) ""))))

	(values pct-str prev-per-op))

;; =============================================================================
;; Benchmark Infrastructure
;; =============================================================================

(define (time-op name thunk)
	"Time a single operation, return milliseconds"
	(collect-garbage)
	(collect-garbage)
	(let ([start (current-inexact-milliseconds)])
		(thunk)
		(- (current-inexact-milliseconds) start)))

(define (time-n-ops name n thunk)
	"Time n operations, return average microseconds per op"
	(collect-garbage)
	(collect-garbage)
	(let ([start (current-inexact-milliseconds)])
		(for ([_ (in-range n)])
			(thunk))
		(/ (* 1000 (- (current-inexact-milliseconds) start)) n)))

;; Cached previous results for the session
(define prev-results (make-parameter (hash)))

(define (benchmark name sizes op-fn)
	"Run benchmark at multiple sizes, print results and log to TSV"
	(printf "\n~a:\n" name)
	(printf "~a~a~a~a~a\n"
					(~a "Size" #:width 12)
					(~a "Time (ms)" #:width 15)
					(~a "Per-op (μs)" #:width 15)
					(~a "vs prev" #:width 12)
					"Ratio to prev size")
	(printf "~a\n" (make-string 70 #\-))
	(let loop ([sizes sizes] [prev-time #f])
		(when (not (null? sizes))
			(let* ([n (car sizes)]
						 [result (op-fn n)]
						 [total-ms (car result)]
						 [per-op-us (cdr result)]
						 [ratio (if (and prev-time (> prev-time 0)) (/ total-ms prev-time) 1.0)])
				(define-values (pct-str _) (log-result name n total-ms per-op-us (prev-results)))
				(printf "~a~a~a~a~a\n"
								(~a n #:width 12)
								(~a (~r total-ms #:precision 3) #:width 15)
								(~a (~r per-op-us #:precision 3) #:width 15)
								(~a pct-str #:width 12)
								(~r ratio #:precision 2))
				(loop (cdr sizes) total-ms)))))

;; =============================================================================
;; Hash Map Benchmarks (Current: hasheq - Copy on Write)
;; =============================================================================

(define (bench-hash-insert n)
	"Insert n items into a hash - measures O(?) for building"
	(let ([start (current-inexact-milliseconds)])
		(let loop ([i 0] [h (hasheq)])
			(if (>= i n)
					h
					(loop (add1 i) (hash-set h i i))))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-hash-update n)
	"Update same key n times in hash of size n - measures O(?) for single update"
	(let* ([h (for/hasheq ([i (in-range n)]) (values i i))]
				 [start (current-inexact-milliseconds)])
		(for ([_ (in-range n)])
			(hash-set h 0 999))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-hash-lookup n)
	"Lookup n times in hash of size n - measures O(?)"
	(let* ([h (for/hasheq ([i (in-range n)]) (values i i))]
				 [start (current-inexact-milliseconds)])
		(for ([i (in-range n)])
			(hash-ref h (random n)))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

;; =============================================================================
;; Vector Benchmarks (Current: immutable vector)
;; =============================================================================

(define (bench-vector-build n)
	"Build vector of size n"
	(let ([start (current-inexact-milliseconds)])
		(vector->immutable-vector (build-vector n identity))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-vector-update n)
	"Update same index n times in vector of size n"
	(let* ([v (vector->immutable-vector (build-vector n identity))]
				 [start (current-inexact-milliseconds)])
		;; Note: vector-set on immutable vector requires conversion dance
		;; This simulates what persistent vectors would need to beat
		(for ([_ (in-range (min n 1000))]) ; cap at 1000 to avoid timeout
			(let ([mv (vector-copy v)])
				(vector-set! mv 0 999)
				(vector->immutable-vector mv)))
		(let* ([ops (min n 1000)]
					 [elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) ops)))))

(define (bench-vector-access n)
	"Random access n times in vector of size n"
	(let* ([v (build-vector n identity)]
				 [start (current-inexact-milliseconds)])
		(for ([_ (in-range n)])
			(vector-ref v (random n)))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

;; =============================================================================
;; List Benchmarks (Already persistent/structural sharing)
;; =============================================================================

(define (bench-list-cons n)
	"Cons n items onto list - should be O(1) per op = O(n) total"
	(let ([start (current-inexact-milliseconds)])
		(let loop ([i 0] [lst '()])
			(if (>= i n)
					lst
					(loop (add1 i) (cons i lst))))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-list-access n)
	"Access middle element - should be O(n)"
	(let* ([lst (build-list n identity)]
				 [mid (quotient n 2)]
				 [start (current-inexact-milliseconds)])
		(for ([_ (in-range 100)]) ; only 100 times since O(n) per access
			(list-ref lst mid))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) 100)))))

;; =============================================================================
;; Analysis Helpers
;; =============================================================================

(define (analyze-complexity ratios)
	"Given ratios when size increases 10x, estimate complexity"
	(let ([avg-ratio (/ (apply + ratios) (length ratios))])
		(cond
			[(<= avg-ratio 1.5) "O(1)"]
			[(<= avg-ratio 3.5) "O(log n)"]
			[(<= avg-ratio 15) "O(n)"]
			[(<= avg-ratio 150) "O(n log n)"]
			[else "O(n²) or worse"])))

;; =============================================================================
;; Main Benchmark Runner
;; =============================================================================

(define (run-all-benchmarks)
	;; Initialize TSV logging
	(ensure-log-header)
	(prev-results (read-previous-runs))

	(printf "\n")
	(printf "========================================\n")
	(printf "  TAB-RACKET PERFORMANCE BENCHMARKS\n")
	(printf "========================================\n")
	(printf "Measuring algorithmic complexity via timing at scale\n")
	(printf "Results logged to: ~a\n" PERF_LOG_FILE)
	(printf "Ratio column shows time increase when size 10x\n")
	(displayln "  ratio ~1 = O(1), ~3 = O(log n), ~10 = O(n), ~100 = O(n^2)")
	(displayln "  'vs prev' shows % change from last recorded run")

	(define sizes '(100 1000 10000 100000))

	(printf "\n\n--- HASH MAP (hasheq - copy-on-write) ---\n")

	(benchmark "Hash: Insert n items (building)" sizes bench-hash-insert)
	(printf "  Expected: O(n²) total due to copying, O(n) per insert\n")

	(benchmark "Hash: Update same key n times (size=n)" sizes bench-hash-update)
	(printf "  Expected: O(n) per update (full copy)\n")

	(benchmark "Hash: Lookup n times (size=n)" sizes bench-hash-lookup)
	(printf "  Expected: O(1) per lookup\n")

	(printf "\n\n--- IMMUTABLE VECTOR ---\n")

	(benchmark "Vector: Build size n" sizes bench-vector-build)
	(printf "  Expected: O(n) total\n")

	(benchmark "Vector: Update index 0 (capped at 1000 ops)" sizes bench-vector-update)
	(printf "  Expected: O(n) per update (full copy)\n")

	(benchmark "Vector: Random access n times (size=n)" sizes bench-vector-access)
	(printf "  Expected: O(1) per access\n")

	(printf "\n\n--- LIST (persistent via structural sharing) ---\n")

	(benchmark "List: Cons n items" sizes bench-list-cons)
	(printf "  Expected: O(1) per cons = O(n) total\n")

	(benchmark "List: Access middle element 100 times" sizes bench-list-access)
	(printf "  Expected: O(n) per access\n")

	(printf "\n\n========================================\n")
	(printf "  SUMMARY\n")
	(printf "========================================\n")
	(printf "Current hash-set: O(n) per operation - BAD for functional style\n")
	(printf "Current vector-set: O(n) per operation - BAD for functional style\n")
	(printf "Current list cons: O(1) per operation - GOOD (already persistent)\n")
	(printf "\nWith HAMT-based persistent structures:\n")
	(printf "  hash-set would be: O(log₃₂ n) ≈ O(1) amortized\n")
	(printf "  vector-set would be: O(log₃₂ n) ≈ O(1) amortized\n")
	(printf "\n"))

;; =============================================================================
;; PFDS Benchmarks (Persistent Functional Data Structures)
;; =============================================================================

(require (prefix-in pfds: pfds/ralist/skew))

(define (bench-pfds-ralist-build n)
	"Build a persistent ralist of size n"
	(let ([start (current-inexact-milliseconds)])
		(let loop ([i 0] [lst (pfds:list)])
			(if (>= i n)
					lst
					(loop (add1 i) (pfds:cons i lst))))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-pfds-ralist-update n)
	"Update index 0 n times in ralist of size n - should be O(log n) per op"
	(let* ([lst (let loop ([i 0] [acc (pfds:list)])
								(if (>= i n) acc (loop (add1 i) (pfds:cons i acc))))]
				 [ops (min n 1000)]
				 [start (current-inexact-milliseconds)])
		(for ([_ (in-range ops)])
			(pfds:list-set lst 0 999))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) ops)))))

(define (bench-pfds-ralist-access n)
	"Random access n times in ralist of size n - should be O(log n)"
	(let* ([lst (let loop ([i 0] [acc (pfds:list)])
								(if (>= i n) acc (loop (add1 i) (pfds:cons i acc))))]
				 [start (current-inexact-milliseconds)])
		(for ([_ (in-range n)])
			(pfds:list-ref lst (random n)))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (run-pfds-benchmarks)
	(printf "\n\n--- PFDS RALIST (Persistent Random Access List) ---\n")
	(printf "Should show O(log n) for updates instead of O(n)\n")

	(define sizes '(100 1000 10000 100000))

	(benchmark "PFDS RAList: Build size n" sizes bench-pfds-ralist-build)
	(printf "  Expected: O(1) per cons = O(n) total\n")

	(benchmark "PFDS RAList: Update index 0 (capped at 1000 ops)" sizes bench-pfds-ralist-update)
	(printf "  Expected: O(log n) per update - MUCH better than vector!\n")

	(benchmark "PFDS RAList: Random access n times" sizes bench-pfds-ralist-access)
	(printf "  Expected: O(log n) per access\n"))

;; =============================================================================
;; HAMT Benchmarks (Our Implementation)
;; =============================================================================

(require (prefix-in hamt: "../hamt/main.rkt"))

(define (bench-hamt-insert n)
	"Insert n items into HAMT - should be O(log n) per op = O(n log n) total"
	(let ([start (current-inexact-milliseconds)])
		(let loop ([i 0] [h (hamt:empty-hamt)])
			(if (>= i n)
					h
					(loop (add1 i) (hamt:hamt-set h i i))))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-hamt-update n)
	"Update same key n times in HAMT of size n - should be O(log n) per op"
	(let* ([h (let loop ([i 0] [acc (hamt:empty-hamt)])
							(if (>= i n) acc (loop (add1 i) (hamt:hamt-set acc i i))))]
				 [start (current-inexact-milliseconds)])
		(for ([_ (in-range n)])
			(hamt:hamt-set h 0 999))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (bench-hamt-lookup n)
	"Lookup n times in HAMT of size n - should be O(log n) per op"
	(let* ([h (let loop ([i 0] [acc (hamt:empty-hamt)])
							(if (>= i n) acc (loop (add1 i) (hamt:hamt-set acc i i))))]
				 [start (current-inexact-milliseconds)])
		(for ([i (in-range n)])
			(hamt:hamt-ref h (random n)))
		(let ([elapsed (- (current-inexact-milliseconds) start)])
			(cons elapsed (/ (* 1000 elapsed) n)))))

(define (run-hamt-benchmarks)
	(printf "\n\n--- HAMT (Our 64-way Persistent Hash Map) ---\n")
	(printf "Should show O(log64 n) ≈ O(1) for all operations\n")

	(define sizes '(100 1000 10000 100000))

	(benchmark "HAMT: Insert n items (building)" sizes bench-hamt-insert)
	(printf "  Expected: O(log n) per insert = O(n log n) total\n")

	(benchmark "HAMT: Update same key n times (size=n)" sizes bench-hamt-update)
	(printf "  Expected: O(log n) per update - MUCH better than hasheq!\n")

	(benchmark "HAMT: Lookup n times (size=n)" sizes bench-hamt-lookup)
	(printf "  Expected: O(log n) per lookup\n"))

;; =============================================================================
;; Comparison Summary
;; =============================================================================

(define (run-comparison)
	(printf "\n\n========================================\n")
	(printf "  COMPARISON: Hash Update n times (size=n)\n")
	(printf "========================================\n")
	(printf "\nBuilt-in hasheq (copy-on-write):\n")
	(for ([n '(100 1000 10000 100000)])
		(let ([result (bench-hash-update n)])
			(printf "  n=~a: ~a μs/op\n" n (~r (cdr result) #:precision 2))))

	(printf "\nHAMT (persistent, 64-way):\n")
	(for ([n '(100 1000 10000 100000)])
		(let ([result (bench-hamt-update n)])
			(printf "  n=~a: ~a μs/op\n" n (~r (cdr result) #:precision 2))))

	(printf "\n"))

;; Run benchmarks when executed directly
(module+ main
	(run-all-benchmarks)
	(run-hamt-benchmarks)
	(run-pfds-benchmarks)
	(run-comparison))

(provide run-all-benchmarks run-hamt-benchmarks run-pfds-benchmarks run-comparison)
