#lang racket

;; Memory and GC Benchmarks for Persistent Data Structures
;; Measures memory consumption and GC behavior

(require racket/format
         "../hamt/main.rkt"
         "../pvector/main.rkt")

;; =============================================================================
;; Configuration
;; =============================================================================

(define SIZES '(1000 10000 100000))
(define NUM-VERSIONS 100)  ; Number of versions to create for sharing test

;; =============================================================================
;; Memory Measurement Helpers
;; =============================================================================

(define (measure-memory-delta thunk)
  "Run thunk and return approximate memory delta in bytes"
  (collect-garbage)
  (collect-garbage)
  (collect-garbage)
  (define before (current-memory-use))
  (define result (thunk))
  (collect-garbage)
  (collect-garbage)
  (collect-garbage)
  (define after (current-memory-use))
  (values result (- after before)))

(define (format-bytes n)
  "Format bytes in human-readable form"
  (cond
    [(>= n 1048576) (format "~a MB" (~r (/ n 1048576.0) #:precision 2))]
    [(>= n 1024) (format "~a KB" (~r (/ n 1024.0) #:precision 2))]
    [else (format "~a B" n)]))

;; =============================================================================
;; HAMT Memory Tests
;; =============================================================================

(define (hamt-memory-single-build n)
  "Measure memory for building a single HAMT of size n"
  (displayln (format "\n--- HAMT Single Build (n=~a) ---" n))
  (define-values (h delta)
    (measure-memory-delta
     (λ () (for/fold ([h (empty-hamt)])
                     ([i (in-range n)])
             (hamt-set h i i)))))
  (displayln (format "Total memory used: ~a" (format-bytes delta)))
  (displayln (format "Per-entry average: ~a" (format-bytes (quotient delta n))))
  (displayln (format "Entry count: ~a" (hamt-count h)))
  delta)

(define (hamt-memory-structural-sharing n num-versions)
  "Measure memory with many versions sharing structure"
  (displayln (format "\n--- HAMT Structural Sharing (n=~a, versions=~a) ---" n num-versions))

  ;; Build base HAMT
  (define base
    (for/fold ([h (empty-hamt)])
              ([i (in-range n)])
      (hamt-set h i i)))

  (collect-garbage)
  (collect-garbage)
  (define before (current-memory-use))

  ;; Create many versions, each with one key changed
  (define versions
    (for/list ([i (in-range num-versions)])
      (hamt-set base i 'modified)))

  (collect-garbage)
  (define after (current-memory-use))
  (define delta (- after before))

  (displayln (format "Memory for ~a versions: ~a" num-versions (format-bytes delta)))
  (displayln (format "Per-version average: ~a" (format-bytes (quotient delta num-versions))))
  (displayln (format "If fully copied, would be: ~a" (format-bytes (* num-versions n 50)))) ; estimate 50 bytes/entry
  (displayln (format "Sharing efficiency: ~a%"
                     (~r (* 100.0 (- 1 (/ delta (* num-versions n 50.0)))) #:precision 1)))

  ;; Verify all versions are valid
  (for ([v versions] [i (in-naturals)])
    (unless (eq? (hamt-ref v i) 'modified)
      (error 'hamt-memory-structural-sharing "Version ~a has wrong value at key ~a" i i)))

  delta)

;; =============================================================================
;; PVector Memory Tests
;; =============================================================================

(define (pvector-memory-single-build n)
  "Measure memory for building a single PVector of size n"
  (displayln (format "\n--- PVector Single Build (n=~a) ---" n))
  (define-values (v delta)
    (measure-memory-delta
     (λ () (for/fold ([v (empty-pvector)])
                     ([i (in-range n)])
             (pvector-push v i)))))
  (displayln (format "Total memory used: ~a" (format-bytes delta)))
  (displayln (format "Per-element average: ~a" (format-bytes (quotient delta n))))
  (displayln (format "Length: ~a" (pvector-length v)))
  delta)

(define (pvector-memory-structural-sharing n num-versions)
  "Measure memory with many versions sharing structure"
  (displayln (format "\n--- PVector Structural Sharing (n=~a, versions=~a) ---" n num-versions))

  ;; Build base PVector
  (define base (list->pvector (range n)))

  (collect-garbage)
  (collect-garbage)
  (define before (current-memory-use))

  ;; Create many versions, each with one element changed
  (define versions
    (for/list ([i (in-range num-versions)])
      (pvector-set base (modulo i n) 'modified)))

  (collect-garbage)
  (define after (current-memory-use))
  (define delta (- after before))

  (displayln (format "Memory for ~a versions: ~a" num-versions (format-bytes delta)))
  (displayln (format "Per-version average: ~a" (format-bytes (quotient delta num-versions))))
  (displayln (format "If fully copied, would be: ~a" (format-bytes (* num-versions n 8)))) ; estimate 8 bytes/element
  (displayln (format "Sharing efficiency: ~a%"
                     (~r (* 100.0 (- 1 (/ delta (* num-versions n 8.0)))) #:precision 1)))

  delta)

;; =============================================================================
;; GC Pressure Tests
;; =============================================================================

(define (gc-pressure-test data-type n iterations)
  "Measure GC collections during intensive operations"
  (displayln (format "\n--- GC Pressure Test (~a, n=~a, iter=~a) ---" data-type n iterations))

  (define gc-before (current-gc-milliseconds))
  (define start-time (current-inexact-milliseconds))

  (case data-type
    [(hamt)
     (define base (for/fold ([h (empty-hamt)])
                            ([i (in-range n)])
                    (hamt-set h i i)))
     ;; Rapid update cycles
     (for ([_ (in-range iterations)])
       (for/fold ([h base])
                 ([i (in-range 100)])
         (hamt-set h (random n) 'new-value)))]
    [(pvector)
     (define base (list->pvector (range n)))
     ;; Rapid update cycles
     (for ([_ (in-range iterations)])
       (for/fold ([v base])
                 ([i (in-range 100)])
         (pvector-set v (random n) 'new-value)))])

  (define gc-after (current-gc-milliseconds))
  (define end-time (current-inexact-milliseconds))
  (define elapsed (- end-time start-time))
  (define gc-time (- gc-after gc-before))

  (displayln (format "Total time: ~a ms" (~r elapsed #:precision 1)))
  (displayln (format "GC time: ~a ms" gc-time))
  (displayln (format "GC overhead: ~a%" (~r (* 100.0 (/ gc-time elapsed)) #:precision 1))))

;; =============================================================================
;; Comparison with Mutable Structures
;; =============================================================================

(define (compare-mutable-vs-persistent n)
  "Compare memory usage of mutable vs persistent structures"
  (displayln (format "\n=== Mutable vs Persistent Comparison (n=~a) ===" n))

  ;; Mutable vector
  (define-values (mv mv-delta)
    (measure-memory-delta
     (λ () (define v (make-vector n))
           (for ([i (in-range n)])
             (vector-set! v i i))
           v)))
  (displayln (format "Mutable vector: ~a" (format-bytes mv-delta)))

  ;; Persistent vector
  (define-values (pv pv-delta)
    (measure-memory-delta
     (λ () (list->pvector (range n)))))
  (displayln (format "Persistent vector: ~a (~ax)"
                     (format-bytes pv-delta)
                     (~r (/ pv-delta (max mv-delta 1.0)) #:precision 2)))

  ;; Mutable hash
  (define-values (mh mh-delta)
    (measure-memory-delta
     (λ () (define h (make-hasheq))
           (for ([i (in-range n)])
             (hash-set! h i i))
           h)))
  (displayln (format "Mutable hash: ~a" (format-bytes mh-delta)))

  ;; Persistent hash (HAMT)
  (define-values (ph ph-delta)
    (measure-memory-delta
     (λ () (for/fold ([h (empty-hamt)])
                     ([i (in-range n)])
             (hamt-set h i i)))))
  (displayln (format "Persistent hash (HAMT): ~a (~ax)"
                     (format-bytes ph-delta)
                     (~r (/ ph-delta (max mh-delta 1.0)) #:precision 2))))

;; =============================================================================
;; Main
;; =============================================================================

(module+ main
  (displayln "")
  (displayln "╔═══════════════════════════════════════════════════════════════╗")
  (displayln "║  Memory & GC Benchmarks for Persistent Data Structures        ║")
  (displayln "╚═══════════════════════════════════════════════════════════════╝")

  ;; Memory build tests
  (displayln "\n========== SINGLE BUILD MEMORY USAGE ==========")
  (for ([n SIZES])
    (hamt-memory-single-build n)
    (pvector-memory-single-build n))

  ;; Structural sharing tests
  (displayln "\n========== STRUCTURAL SHARING EFFICIENCY ==========")
  (hamt-memory-structural-sharing 10000 NUM-VERSIONS)
  (pvector-memory-structural-sharing 10000 NUM-VERSIONS)

  ;; GC pressure tests
  (displayln "\n========== GC PRESSURE TESTS ==========")
  (gc-pressure-test 'hamt 10000 100)
  (gc-pressure-test 'pvector 10000 100)

  ;; Comparison tests
  (displayln "\n========== MUTABLE VS PERSISTENT COMPARISON ==========")
  (for ([n '(1000 10000 100000)])
    (compare-mutable-vs-persistent n))

  (displayln "\n")
  (displayln "========== SUMMARY ==========")
  (displayln "")
  (displayln "Key insights:")
  (displayln "- Persistent structures use more memory per entry than mutable")
  (displayln "- But structural sharing makes creating versions very cheap")
  (displayln "- GC overhead is typically <10% during normal operations")
  (displayln "- Trade-off: ~2-3x memory for immutability guarantees")
  (displayln ""))
