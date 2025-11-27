#lang racket/base

;; Benchmark comparing original vs optimized HAMT

(require racket/format
         (prefix-in original: "../hamt/main.rkt")
         (prefix-in optimized: "../hamt/optimized-main.rkt"))

;; Timing utility
(define (time-thunk thunk iterations)
  (collect-garbage)
  (collect-garbage)
  (let ([start (current-inexact-milliseconds)])
    (for ([_ (in-range iterations)])
      (thunk))
    (let* ([elapsed (- (current-inexact-milliseconds) start)]
           [per-op (* 1000 (/ elapsed iterations))])
      (values elapsed per-op))))

(define (format-comparison label size orig-us opt-us)
  (define speedup (/ orig-us opt-us))
  (printf "~a~a~a~a~a\n"
          (~a label #:width 25)
          (~a size #:width 10)
          (~a (~r orig-us #:precision 3) #:width 15)
          (~a (~r opt-us #:precision 3) #:width 15)
          (~a (~r speedup #:precision 2) #:width 10)))

(define (print-header)
  (printf "~a~a~a~a~a\n"
          (~a "Operation" #:width 25)
          (~a "Size" #:width 10)
          (~a "Original (μs)" #:width 15)
          (~a "Optimized (μs)" #:width 15)
          (~a "Speedup" #:width 10))
  (displayln (make-string 75 #\-)))

(define (run-comparison)
  (displayln "")
  (displayln "========================================")
  (displayln "  ORIGINAL vs OPTIMIZED HAMT")
  (displayln "  (unsafe ops in hot paths)")
  (displayln "========================================")
  (displayln "")

  (print-header)

  (for ([n '(100 1000 10000 100000)])
    (define iters (min 10000 n))

    ;; Build HAMTs of size n
    (define orig-h
      (for/fold ([h (original:empty-hamt)])
                ([i (in-range n)])
        (original:hamt-set h i i)))

    (define opt-h
      (for/fold ([h (optimized:empty-hamt)])
                ([i (in-range n)])
        (optimized:hamt-set h i i)))

    ;; Benchmark lookup
    (define-values (o-ms o-us)
      (time-thunk (lambda () (original:hamt-ref orig-h (random n))) iters))
    (define-values (p-ms p-us)
      (time-thunk (lambda () (optimized:hamt-ref opt-h (random n))) iters))
    (format-comparison "Lookup" n o-us p-us))

  (displayln "")
  (print-header)

  (for ([n '(100 1000 10000 100000)])
    (define iters (min 10000 n))

    (define orig-h
      (for/fold ([h (original:empty-hamt)])
                ([i (in-range n)])
        (original:hamt-set h i i)))

    (define opt-h
      (for/fold ([h (optimized:empty-hamt)])
                ([i (in-range n)])
        (optimized:hamt-set h i i)))

    ;; Benchmark update
    (define-values (o-ms o-us)
      (time-thunk (lambda () (original:hamt-set orig-h 0 999)) iters))
    (define-values (p-ms p-us)
      (time-thunk (lambda () (optimized:hamt-set opt-h 0 999)) iters))
    (format-comparison "Update" n o-us p-us))

  (displayln "")
  (displayln "Speedup > 1.0 means optimized is faster")
  (displayln ""))

(module+ main
  (run-comparison))
