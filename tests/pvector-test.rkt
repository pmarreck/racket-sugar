#lang racket

;; Persistent Vector Test Suite

(require rackunit
         rackunit/text-ui
         "../pvector/main.rkt")

;; =============================================================================
;; Basic Tests
;; =============================================================================

(define basic-tests
  (test-suite
   "Basic Operations"

   (test-case "empty-pvector creates empty vector"
     (check-true (pvector-empty? (empty-pvector))))

   (test-case "pvector-length of empty is 0"
     (check-equal? (pvector-length (empty-pvector)) 0))

   (test-case "pvector constructor works"
     (define v (pvector 1 2 3))
     (check-equal? (pvector-length v) 3)
     (check-equal? (pvector-ref v 0) 1)
     (check-equal? (pvector-ref v 1) 2)
     (check-equal? (pvector-ref v 2) 3))

   (test-case "pvector-push adds element"
     (define v1 (empty-pvector))
     (define v2 (pvector-push v1 42))
     (check-equal? (pvector-length v2) 1)
     (check-equal? (pvector-ref v2 0) 42))

   (test-case "pvector-push multiple elements"
     (define v (pvector-push (pvector-push (pvector-push (empty-pvector) 1) 2) 3))
     (check-equal? (pvector-length v) 3)
     (check-equal? (pvector-ref v 0) 1)
     (check-equal? (pvector-ref v 1) 2)
     (check-equal? (pvector-ref v 2) 3))))

;; =============================================================================
;; Update Tests
;; =============================================================================

(define update-tests
  (test-suite
   "Update Operations"

   (test-case "pvector-set updates element"
     (define v1 (pvector 1 2 3))
     (define v2 (pvector-set v1 1 42))
     (check-equal? (pvector-ref v2 1) 42)
     ;; Original unchanged (persistence!)
     (check-equal? (pvector-ref v1 1) 2))

   (test-case "pvector-pop removes last element"
     (define v1 (pvector 1 2 3))
     (define v2 (pvector-pop v1))
     (check-equal? (pvector-length v2) 2)
     (check-equal? (pvector-ref v2 0) 1)
     (check-equal? (pvector-ref v2 1) 2)
     ;; Original unchanged
     (check-equal? (pvector-length v1) 3))))

;; =============================================================================
;; Conversion Tests
;; =============================================================================

(define conversion-tests
  (test-suite
   "Conversion Operations"

   (test-case "list->pvector works"
     (define v (list->pvector '(1 2 3 4 5)))
     (check-equal? (pvector-length v) 5)
     (for ([i (in-range 5)])
       (check-equal? (pvector-ref v i) (add1 i))))

   (test-case "pvector->list works"
     (define v (pvector 1 2 3))
     (check-equal? (pvector->list v) '(1 2 3)))

   (test-case "vector->pvector works"
     (define v (vector->pvector #(a b c)))
     (check-equal? (pvector-length v) 3)
     (check-equal? (pvector-ref v 0) 'a))

   (test-case "pvector->vector works"
     (define v (pvector 1 2 3))
     (check-equal? (pvector->vector v) '#(1 2 3)))))

;; =============================================================================
;; Large Scale Tests
;; =============================================================================

(define large-tests
  (test-suite
   "Large Scale Operations"

   (test-case "build and access 1000 elements"
     (define v (list->pvector (range 1000)))
     (check-equal? (pvector-length v) 1000)
     (for ([i (in-range 1000)])
       (check-equal? (pvector-ref v i) i)))

   (test-case "update multiple elements"
     (define v1 (list->pvector (range 100)))
     (define v2 (pvector-set (pvector-set v1 0 999) 99 888))
     (check-equal? (pvector-ref v2 0) 999)
     (check-equal? (pvector-ref v2 99) 888)
     (check-equal? (pvector-ref v2 50) 50)
     ;; Original unchanged
     (check-equal? (pvector-ref v1 0) 0))

   (test-case "push beyond tail capacity"
     ;; Push more than 32 elements to trigger trie creation
     (define v (list->pvector (range 100)))
     (check-equal? (pvector-length v) 100)
     (for ([i (in-range 100)])
       (check-equal? (pvector-ref v i) i)))))

;; =============================================================================
;; Iteration Tests
;; =============================================================================

(define iteration-tests
  (test-suite
   "Iteration"

   (test-case "in-pvector sequence works"
     (define v (pvector 1 2 3 4 5))
     (define sum (for/sum ([x (in-pvector v)]) x))
     (check-equal? sum 15))

   (test-case "pvector-fold works"
     (define v (pvector 1 2 3 4 5))
     (check-equal? (pvector-fold + 0 v) 15))))

;; =============================================================================
;; Run Tests
;; =============================================================================

(define all-tests
  (test-suite
   "PVector Test Suite"
   basic-tests
   update-tests
   conversion-tests
   large-tests
   iteration-tests))

(module+ main
  (run-tests all-tests 'verbose))

(module+ test
  (run-tests all-tests))
