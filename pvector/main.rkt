#lang racket/base

;; Persistent Vector (PVector)
;; A persistent, immutable vector with O(log32 n) operations
;;
;; Based on Clojure's PersistentVector
;; Using 32-way branching (5 bits per level)

(require racket/match
         racket/vector)

(provide
 ;; Constructors
 empty-pvector
 pvector
 list->pvector
 vector->pvector

 ;; Predicates
 pvector?
 pvector-empty?

 ;; Core operations
 pvector-ref
 pvector-set
 pvector-push    ; append to end
 pvector-pop     ; remove from end
 pvector-length

 ;; Conversion
 pvector->list
 pvector->vector

 ;; Iteration
 pvector-fold
 in-pvector)

;; =============================================================================
;; Constants
;; =============================================================================

(define BITS 5)
(define BRANCHING 32)  ; 2^5
(define MASK 31)       ; 0x1F = 0b11111

;; =============================================================================
;; Data Structures
;; =============================================================================

;; A pvector is a struct containing:
;; - count: number of elements
;; - shift: bits to shift for root level (5 * depth)
;; - root: the trie root (vector of nodes or #f for empty)
;; - tail: vector of elements at the end (optimization for push)
(struct pv (count shift root tail) #:transparent)

;; Empty pvector singleton
(define THE-EMPTY-PVECTOR (pv 0 BITS #f (vector)))

;; =============================================================================
;; Predicates
;; =============================================================================

(define (pvector? x)
  (pv? x))

(define (pvector-empty? v)
  (zero? (pv-count v)))

;; =============================================================================
;; Constructors
;; =============================================================================

(define (empty-pvector)
  THE-EMPTY-PVECTOR)

(define (pvector . items)
  (list->pvector items))

(define (list->pvector lst)
  (for/fold ([v (empty-pvector)])
            ([item (in-list lst)])
    (pvector-push v item)))

(define (vector->pvector vec)
  (for/fold ([v (empty-pvector)])
            ([item (in-vector vec)])
    (pvector-push v item)))

;; =============================================================================
;; Length
;; =============================================================================

(define (pvector-length v)
  (pv-count v))

;; =============================================================================
;; Tail Operations
;; =============================================================================

(define (tail-offset v)
  "Calculate the index where tail starts"
  (let ([cnt (pv-count v)])
    (if (< cnt BRANCHING)
        0
        (bitwise-and (sub1 cnt) (bitwise-not MASK)))))

;; =============================================================================
;; Lookup
;; =============================================================================

(define (pvector-ref v idx [default (lambda () (error 'pvector-ref "index out of bounds: ~a" idx))])
  (if (or (< idx 0) (>= idx (pv-count v)))
      (if (procedure? default) (default) default)
      (let ([arr (array-for v idx)])
        (vector-ref arr (bitwise-and idx MASK)))))

(define (array-for v idx)
  "Get the leaf array containing index idx"
  (if (>= idx (tail-offset v))
      (pv-tail v)
      (let loop ([node (pv-root v)]
                 [level (pv-shift v)])
        (if (> level 0)
            (loop (vector-ref node (bitwise-and (arithmetic-shift idx (- level)) MASK))
                  (- level BITS))
            node))))

;; =============================================================================
;; Update
;; =============================================================================

(define (pvector-set v idx val)
  "Set element at idx, return new pvector"
  (when (or (< idx 0) (>= idx (pv-count v)))
    (error 'pvector-set "index out of bounds: ~a" idx))
  (if (>= idx (tail-offset v))
      ;; Update in tail
      (let* ([tail (pv-tail v)]
             [new-tail (vector-copy tail)])
        (vector-set! new-tail (bitwise-and idx MASK) val)
        (pv (pv-count v) (pv-shift v) (pv-root v) (vector->immutable-vector new-tail)))
      ;; Update in trie
      (pv (pv-count v) (pv-shift v)
          (do-set (pv-shift v) (pv-root v) idx val)
          (pv-tail v))))

(define (do-set level node idx val)
  "Recursively update node at idx with val"
  (let ([new-node (vector-copy node)]
        [subidx (bitwise-and (arithmetic-shift idx (- level)) MASK)])
    (if (zero? level)
        ;; At leaf level - set value directly
        (begin
          (vector-set! new-node subidx val)
          (vector->immutable-vector new-node))
        ;; Recurse into child
        (begin
          (vector-set! new-node subidx
                       (do-set (- level BITS) (vector-ref node subidx) idx val))
          (vector->immutable-vector new-node)))))

;; =============================================================================
;; Push (Append)
;; =============================================================================

;; Helper: create a path of single-element nodes from root level to leaf
(define (new-path level node)
  "Create a path from root to node at position 0 of each level"
  (if (= level BITS)
      (vector->immutable-vector (vector node))
      (vector->immutable-vector (vector (new-path (- level BITS) node)))))

(define (pvector-push v val)
  "Append val to end of pvector"
  (let ([cnt (pv-count v)]
        [tail (pv-tail v)])
    (cond
      ;; Room in tail?
      [(< (- cnt (tail-offset v)) BRANCHING)
       (let ([new-tail (vector-append tail (vector val))])
         (pv (add1 cnt) (pv-shift v) (pv-root v) (vector->immutable-vector new-tail)))]
      ;; Tail is full, push it into the trie
      [else
       (let* ([tail-node (vector->immutable-vector tail)]
              ;; Check if we need to increase depth BEFORE deciding how to push
              ;; Overflow when cnt exceeds max capacity at current shift
              ;; Max capacity = BRANCHING * 2^shift = BRANCHING << shift
              [overflow? (and (pv-root v)
                             (> cnt (arithmetic-shift BRANCHING (pv-shift v))))]
              [new-shift (if overflow? (+ (pv-shift v) BITS) (pv-shift v))]
              [new-root (cond
                          ;; Overflow: create new root with old root and new path to tail
                          [overflow?
                           (vector->immutable-vector
                             (vector (pv-root v) (new-path (pv-shift v) tail-node)))]
                          ;; Existing root: push tail into trie
                          [(pv-root v)
                           (push-tail (pv-shift v) (pv-root v) tail-node cnt)]
                          ;; No root yet: create branch node containing the tail
                          [else
                           (vector->immutable-vector (vector tail-node))])])
         (pv (add1 cnt) new-shift new-root (vector val)))])))

(define (push-tail shift parent tail-node cnt)
  "Push tail-node into the trie"
  (let* ([subidx (bitwise-and (arithmetic-shift (sub1 cnt) (- shift)) MASK)]
         [parent-len (if parent (vector-length parent) 0)]
         [new-len (add1 subidx)]  ; need at least this many slots
         [new-parent (make-vector new-len #f)])
    ;; Copy existing elements from parent
    (when parent
      (for ([i (in-range (min parent-len new-len))])
        (vector-set! new-parent i (vector-ref parent i))))
    (if (= shift BITS)
        ;; At leaf level
        (begin
          (vector-set! new-parent subidx tail-node)
          (vector->immutable-vector new-parent))
        ;; Recurse
        (let ([child (and parent
                         (< subidx parent-len)
                         (vector-ref parent subidx))])
          (vector-set! new-parent subidx
                       (push-tail (- shift BITS) child tail-node cnt))
          (vector->immutable-vector new-parent)))))

;; =============================================================================
;; Pop (Remove from end)
;; =============================================================================

(define (pvector-pop v)
  "Remove last element, return new pvector"
  (let ([cnt (pv-count v)])
    (cond
      [(zero? cnt)
       (error 'pvector-pop "cannot pop from empty pvector")]
      [(= cnt 1)
       THE-EMPTY-PVECTOR]
      ;; More than one element in tail?
      [(> (vector-length (pv-tail v)) 1)
       (let ([new-tail (vector-copy (pv-tail v) 0 (sub1 (vector-length (pv-tail v))))])
         (pv (sub1 cnt) (pv-shift v) (pv-root v) (vector->immutable-vector new-tail)))]
      ;; Pop from trie
      [else
       (let* ([new-tail (array-for v (- cnt 2))]
              [new-root (pop-tail (pv-shift v) (pv-root v) cnt)]
              ;; Check if we can decrease depth
              [can-shrink? (and new-root
                               (= (vector-length new-root) 1)
                               (> (pv-shift v) BITS))]
              [new-shift (if can-shrink? (- (pv-shift v) BITS) (pv-shift v))]
              [final-root (if can-shrink? (vector-ref new-root 0) new-root)])
         (pv (sub1 cnt) new-shift final-root new-tail))])))

(define (pop-tail shift node cnt)
  "Remove the last tail from the trie"
  (let ([subidx (bitwise-and (arithmetic-shift (- cnt 2) (- shift)) MASK)])
    (if (= shift BITS)
        ;; At leaf level
        (if (zero? subidx)
            #f
            (let ([new-node (vector-copy node 0 subidx)])
              (vector->immutable-vector new-node)))
        ;; Recurse
        (let ([child (pop-tail (- shift BITS) (vector-ref node subidx) cnt)])
          (if (and (not child) (zero? subidx))
              #f
              (let ([new-node (vector-copy node)])
                (vector-set! new-node subidx child)
                (vector->immutable-vector new-node)))))))

;; =============================================================================
;; Conversion
;; =============================================================================

(define (pvector->list v)
  (pvector-fold (lambda (acc item) (cons item acc)) '() v #:reverse? #t))

(define (pvector->vector v)
  (let ([result (make-vector (pv-count v))])
    (for ([i (in-range (pv-count v))])
      (vector-set! result i (pvector-ref v i)))
    (vector->immutable-vector result)))

;; =============================================================================
;; Iteration
;; =============================================================================

(define (pvector-fold f init v #:reverse? [reverse? #f])
  "Fold f over all elements"
  (if reverse?
      (for/fold ([acc init])
                ([i (in-range (sub1 (pv-count v)) -1 -1)])
        (f acc (pvector-ref v i)))
      (for/fold ([acc init])
                ([i (in-range (pv-count v))])
        (f acc (pvector-ref v i)))))

(define (in-pvector v)
  "Return a sequence for iterating over pvector"
  (make-do-sequence
   (lambda ()
     (values
      (lambda (i) (pvector-ref v i))  ; pos->element
      add1                              ; next-pos
      0                                 ; initial pos
      (lambda (i) (< i (pv-count v)))  ; continue?
      #f                                ; no val check
      #f))))                            ; no pos+val check
