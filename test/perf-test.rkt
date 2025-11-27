#lang racket

;; Performance benchmark suite for tab-racket data structures
;; Tests O-notation behavior by measuring time at different scales

(require racket/format)

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

(define (benchmark name sizes op-fn)
  "Run benchmark at multiple sizes, print results"
  (printf "\n~a:\n" name)
  (printf "~a~a~a~a\n"
          (~a "Size" #:width 12)
          (~a "Time (ms)" #:width 15)
          (~a "Per-op (μs)" #:width 15)
          "Ratio to prev")
  (printf "~a\n" (make-string 55 #\-))
  (let loop ([sizes sizes] [prev-time #f])
    (when (not (null? sizes))
      (let* ([n (car sizes)]
             [result (op-fn n)]
             [total-ms (car result)]
             [per-op-us (cdr result)]
             [ratio (if prev-time (/ total-ms prev-time) 1.0)])
        (printf "~a~a~a~a\n"
                (~a n #:width 12)
                (~a (~r total-ms #:precision 3) #:width 15)
                (~a (~r per-op-us #:precision 3) #:width 15)
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
  (printf "\n")
  (printf "========================================\n")
  (printf "  TAB-RACKET PERFORMANCE BENCHMARKS\n")
  (printf "========================================\n")
  (printf "Measuring algorithmic complexity via timing at scale\n")
  (printf "Ratio column shows time increase when size 10x\n")
  (displayln "  ratio ~1 = O(1), ~3 = O(log n), ~10 = O(n), ~100 = O(n^2)")

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
;; Comparison Summary
;; =============================================================================

(define (run-comparison)
  (printf "\n\n========================================\n")
  (printf "  COMPARISON: Vector Update (capped at 1000 ops)\n")
  (printf "========================================\n")
  (printf "\nBuilt-in immutable vector (copy-on-write):\n")
  (for ([n '(100 1000 10000 100000)])
    (let ([result (bench-vector-update n)])
      (printf "  n=~a: ~a μs/op\n" n (~r (cdr result) #:precision 2))))

  (printf "\nPFDS Random Access List (persistent):\n")
  (for ([n '(100 1000 10000 100000)])
    (let ([result (bench-pfds-ralist-update n)])
      (printf "  n=~a: ~a μs/op\n" n (~r (cdr result) #:precision 2))))

  (printf "\n"))

;; Run benchmarks when executed directly
(module+ main
  (run-all-benchmarks)
  (run-pfds-benchmarks)
  (run-comparison))

(provide run-all-benchmarks run-pfds-benchmarks run-comparison)
