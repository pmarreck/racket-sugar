#lang typed/racket

;; Benchmark typed HAMT from typed code (no contract overhead)

(require racket/format
         "../hamt/typed-main.rkt")

(: time-thunk (-> (-> Any) Integer (Values Flonum Flonum)))
(define (time-thunk thunk iterations)
  (collect-garbage)
  (collect-garbage)
  (let ([start (current-inexact-milliseconds)])
    (for ([_ (in-range iterations)])
      (thunk))
    (let* ([elapsed (- (current-inexact-milliseconds) start)]
           [per-op (* 1000.0 (/ elapsed (exact->inexact iterations)))])
      (values elapsed per-op))))

(: run-benchmark (-> Void))
(define (run-benchmark)
  (displayln "")
  (displayln "========================================")
  (displayln "  TYPED HAMT (no contract overhead)")
  (displayln "  Called from typed code")
  (displayln "========================================")
  (displayln "")

  (displayln "Building HAMTs...")

  (for ([n '(100 1000 10000 100000)])
    (define iters : Integer (min 10000 n))

    ;; Build HAMT of size n
    (define h : HAMT
      (for/fold ([h : HAMT (empty-hamt)])
                ([i (in-range n)])
        (hamt-set h i i)))

    ;; Benchmark lookup
    (define-values (ms us)
      (time-thunk (lambda () (hamt-ref h (random n))) iters))

    (printf "Lookup  n=~a: ~a μs/op\n"
            (~a n #:width 6)
            (~r us #:precision 3)))

  (displayln "")

  (for ([n '(100 1000 10000 100000)])
    (define iters : Integer (min 10000 n))

    (define h : HAMT
      (for/fold ([h : HAMT (empty-hamt)])
                ([i (in-range n)])
        (hamt-set h i i)))

    ;; Benchmark update
    (define-values (ms us)
      (time-thunk (lambda () (hamt-set h 0 999)) iters))

    (printf "Update  n=~a: ~a μs/op\n"
            (~a n #:width 6)
            (~r us #:precision 3)))

  (displayln ""))

(module+ main
  (run-benchmark))
