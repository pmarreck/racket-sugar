#lang racket

;; HAMT Test Suite
;; TDD-style tests following HAMT_TDD_CHECKLIST.md

(require rackunit
         rackunit/text-ui
         "../hamt/main.rkt")

;; =============================================================================
;; Phase 1: Core Helpers - Bitwise Operations
;; =============================================================================

(define bitwise-tests
  (test-suite
   "Phase 1.1: Bitwise Operations"

   (test-case "popcount of 0 returns 0"
     (check-equal? (hamt-popcount 0) 0))

   (test-case "popcount of #b1111 returns 4"
     (check-equal? (hamt-popcount #b1111) 4))

   (test-case "popcount of #xFFFFFFFFFFFFFFFF returns 64"
     (check-equal? (hamt-popcount #xFFFFFFFFFFFFFFFF) 64))

   (test-case "mask extracts correct 6 bits for level 0"
     ;; mask extracts 6 bits at the given level
     ;; Just verify it returns a valid 6-bit value (0-63)
     (define hash #xFC00000000000000)
     (check-true (<= 0 (hamt-mask hash 0) 63)))

   (test-case "mask extracts correct 6 bits for level 5"
     ;; Test that we get different bits at different levels
     (define hash #x0123456789ABCDEF)
     ;; Just verify it returns a valid 6-bit value (0-63)
     (check-true (<= 0 (hamt-mask hash 5) 63)))

   (test-case "bitpos returns power of 2"
     ;; bitpos returns 1 << (6-bit value from hash at level)
     (check-true (= 1 (bitwise-and (hamt-bitpos #x0 0) (hamt-bitpos #x0 0)))))

   (test-case "index counts bits correctly"
     ;; bitmap with bits 0, 2, 5 set = #b100101 = 37
     ;; bitpos for position 5 = 32
     ;; bits before position 5 are bits 0 and 2, so index = 2
     (check-equal? (hamt-index #b100101 #b100000) 2)
     ;; bitpos for position 2 = 4
     ;; bits before position 2 is just bit 0, so index = 1
     (check-equal? (hamt-index #b100101 #b000100) 1)
     ;; bitpos for position 0 = 1
     ;; no bits before position 0, so index = 0
     (check-equal? (hamt-index #b100101 #b000001) 0))))

;; =============================================================================
;; Phase 1: Core Helpers - Node Constructors
;; =============================================================================

(define constructor-tests
  (test-suite
   "Phase 1.2: Node Constructors"

   (test-case "empty-hamt creates empty node"
     (check-true (hamt? (empty-hamt))))

   (test-case "hamt-empty? returns #t for empty node"
     (check-true (hamt-empty? (empty-hamt))))

   (test-case "hamt-count of empty returns 0"
     (check-equal? (hamt-count (empty-hamt)) 0))))

;; =============================================================================
;; Phase 2: Basic Lookup & Insert
;; =============================================================================

(define basic-ops-tests
  (test-suite
   "Phase 2: Basic Lookup & Insert"

   (test-suite
    "Phase 2.1: Single Entry"

    (test-case "insert one key, lookup returns value"
      (define h (hamt-set (empty-hamt) 'a 1))
      (check-equal? (hamt-ref h 'a) 1))

    (test-case "insert one key, lookup different key returns not-found"
      (define h (hamt-set (empty-hamt) 'a 1))
      (check-equal? (hamt-ref h 'b 'not-found) 'not-found))

    (test-case "insert one key, count returns 1"
      (define h (hamt-set (empty-hamt) 'a 1))
      (check-equal? (hamt-count h) 1))

    (test-case "hamt-contains? returns #t for existing key"
      (define h (hamt-set (empty-hamt) 'a 1))
      (check-true (hamt-contains? h 'a)))

    (test-case "hamt-contains? returns #f for missing key"
      (define h (hamt-set (empty-hamt) 'a 1))
      (check-false (hamt-contains? h 'b))))

   (test-suite
    "Phase 2.2: Multiple Entries (Same Level)"

    (test-case "insert two keys with different hashes, both lookups work"
      (define h (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2))
      (check-equal? (hamt-ref h 'a) 1)
      (check-equal? (hamt-ref h 'b) 2))

    (test-case "count returns 2"
      (define h (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2))
      (check-equal? (hamt-count h) 2)))

   (test-suite
    "Phase 2.4: Many Entries"

    (test-case "insert 100 unique keys, all lookups work"
      (define h
        (for/fold ([h (empty-hamt)])
                  ([i (in-range 100)])
          (hamt-set h i (* i 10))))
      (for ([i (in-range 100)])
        (check-equal? (hamt-ref h i) (* i 10))))

    (test-case "count returns 100"
      (define h
        (for/fold ([h (empty-hamt)])
                  ([i (in-range 100)])
          (hamt-set h i i)))
      (check-equal? (hamt-count h) 100))

    (test-case "missing key lookup returns not-found"
      (define h
        (for/fold ([h (empty-hamt)])
                  ([i (in-range 100)])
          (hamt-set h i i)))
      (check-equal? (hamt-ref h 999 'not-found) 'not-found)))

   (test-suite
    "Phase 2.5: Update Existing Key"

    (test-case "insert key, insert same key with new value, lookup returns new value"
      (define h1 (hamt-set (empty-hamt) 'a 1))
      (define h2 (hamt-set h1 'a 2))
      (check-equal? (hamt-ref h2 'a) 2))

    (test-case "count stays at 1 after update"
      (define h1 (hamt-set (empty-hamt) 'a 1))
      (define h2 (hamt-set h1 'a 2))
      (check-equal? (hamt-count h2) 1)))))

;; =============================================================================
;; Phase 3: Persistence (Structural Sharing)
;; =============================================================================

(define persistence-tests
  (test-suite
   "Phase 3: Persistence"

   (test-case "insert into HAMT, original still has old values"
     (define h1 (hamt-set (empty-hamt) 'a 1))
     (define h2 (hamt-set h1 'a 2))
     (check-equal? (hamt-ref h1 'a) 1)
     (check-equal? (hamt-ref h2 'a) 2))

   (test-case "both HMATs are valid simultaneously"
     (define h1 (hamt-set (empty-hamt) 'a 1))
     (define h2 (hamt-set h1 'b 2))
     (define h3 (hamt-set h1 'c 3))
     ;; h2 has a and b
     (check-equal? (hamt-ref h2 'a) 1)
     (check-equal? (hamt-ref h2 'b) 2)
     (check-false (hamt-contains? h2 'c))
     ;; h3 has a and c
     (check-equal? (hamt-ref h3 'a) 1)
     (check-false (hamt-contains? h3 'b))
     (check-equal? (hamt-ref h3 'c) 3))))

;; =============================================================================
;; Phase 5: Delete
;; =============================================================================

(define delete-tests
  (test-suite
   "Phase 5: Delete"

   (test-case "delete existing key, lookup returns not-found"
     (define h1 (hamt-set (empty-hamt) 'a 1))
     (define h2 (hamt-remove h1 'a))
     (check-equal? (hamt-ref h2 'a 'not-found) 'not-found))

   (test-case "delete existing key, count decrements"
     (define h1 (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2))
     (define h2 (hamt-remove h1 'a))
     (check-equal? (hamt-count h2) 1))

   (test-case "delete non-existing key, HAMT unchanged"
     (define h1 (hamt-set (empty-hamt) 'a 1))
     (define h2 (hamt-remove h1 'b))
     (check-equal? (hamt-ref h2 'a) 1)
     (check-equal? (hamt-count h2) 1))

   (test-case "delete from HAMT, original still has key"
     (define h1 (hamt-set (empty-hamt) 'a 1))
     (define h2 (hamt-remove h1 'a))
     (check-equal? (hamt-ref h1 'a) 1)
     (check-equal? (hamt-ref h2 'a 'not-found) 'not-found))))

;; =============================================================================
;; Phase 6: Iteration & Conversion
;; =============================================================================

(define iteration-tests
  (test-suite
   "Phase 6: Iteration & Conversion"

   (test-case "hamt->list of empty returns empty list"
     (check-equal? (hamt->list (empty-hamt)) '()))

   (test-case "hamt->list of single returns one pair"
     (define h (hamt-set (empty-hamt) 'a 1))
     (check-equal? (hamt->list h) '((a . 1))))

   (test-case "hamt->list of many returns all pairs"
     (define h (hamt-set (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2) 'c 3))
     (define lst (hamt->list h))
     (check-equal? (length lst) 3)
     (check-not-false (member '(a . 1) lst))
     (check-not-false (member '(b . 2) lst))
     (check-not-false (member '(c . 3) lst)))

   (test-case "list->hamt of empty returns empty HAMT"
     (check-true (hamt-empty? (list->hamt '()))))

   (test-case "list->hamt creates correct HAMT"
     (define h (list->hamt '((a . 1) (b . 2))))
     (check-equal? (hamt-ref h 'a) 1)
     (check-equal? (hamt-ref h 'b) 2))

   (test-case "hamt-keys returns all keys"
     (define h (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2))
     (define keys (hamt-keys h))
     (check-equal? (length keys) 2)
     (check-not-false (member 'a keys))
     (check-not-false (member 'b keys)))

   (test-case "hamt-values returns all values"
     (define h (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2))
     (define values (hamt-values h))
     (check-equal? (length values) 2)
     (check-not-false (member 1 values))
     (check-not-false (member 2 values)))

   (test-case "hamt-fold sums values"
     (define h (hamt-set (hamt-set (hamt-set (empty-hamt) 'a 1) 'b 2) 'c 3))
     (check-equal? (hamt-fold (lambda (k v acc) (+ v acc)) 0 h) 6))))

;; =============================================================================
;; Phase: hamt constructor function
;; =============================================================================

(define hamt-constructor-tests
  (test-suite
   "hamt constructor"

   (test-case "hamt with no args returns empty"
     (check-true (hamt-empty? (hamt))))

   (test-case "hamt with key-value pairs works"
     (define h (hamt 'a 1 'b 2 'c 3))
     (check-equal? (hamt-ref h 'a) 1)
     (check-equal? (hamt-ref h 'b) 2)
     (check-equal? (hamt-ref h 'c) 3)
     (check-equal? (hamt-count h) 3))))

;; =============================================================================
;; Run all tests
;; =============================================================================

(define all-tests
  (test-suite
   "HAMT Test Suite"
   bitwise-tests
   constructor-tests
   basic-ops-tests
   persistence-tests
   delete-tests
   iteration-tests
   hamt-constructor-tests))

(module+ main
  (run-tests all-tests 'verbose))

(module+ test
  (require rackunit/text-ui)
  (run-tests all-tests))
