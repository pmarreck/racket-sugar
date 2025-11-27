#lang racket/base

;; HAMT - Hash Array Mapped Trie (Optimized version)
;; Uses unsafe operations in hot paths for better performance
;;
;; Based on Phil Bagwell's "Ideal Hash Trees" paper
;; Using 64-way branching (6 bits per level, max 11 levels for 64-bit hash)

(require racket/match
         racket/vector
         racket/unsafe/ops)

(provide
 ;; Constructors
 empty-hamt
 hamt

 ;; Predicates
 hamt?
 hamt-empty?
 hamt-contains?

 ;; Core operations
 hamt-ref
 hamt-set
 hamt-remove
 hamt-count

 ;; Iteration & conversion
 hamt->list
 list->hamt
 hamt-keys
 hamt-values
 hamt-fold

 ;; Bitwise helpers (exported for testing)
 hamt-popcount
 hamt-mask
 hamt-bitpos
 hamt-index)

;; =============================================================================
;; Constants
;; =============================================================================

(define BITS-PER-LEVEL 6)
(define BRANCHING-FACTOR 64)
(define MASK 63)  ; 0x3F
(define MAX-DEPTH 11)

;; =============================================================================
;; Bitwise Helpers (OPTIMIZED with unsafe ops)
;; =============================================================================

(define (hamt-popcount n)
  "Count the number of 1-bits in n"
  (if (fixnum? n)
      (unsafe-fxpopcount n)
      (let loop ([n n] [count 0])
        (if (zero? n)
            count
            (loop (arithmetic-shift n -1)
                  (unsafe-fx+ count (bitwise-and n 1)))))))

(define (hamt-mask hash level)
  "Extract 6 bits from hash at the given level"
  ;; hash may be a bignum, so use safe arithmetic-shift
  ;; but level ops are safe as fixnums
  (define shift-amount (unsafe-fx* (unsafe-fx- (unsafe-fx- MAX-DEPTH 1) level) BITS-PER-LEVEL))
  (bitwise-and (arithmetic-shift hash (- shift-amount)) MASK))

(define (hamt-bitpos hash level)
  "Return bitmap with single bit set at position indicated by hash at level"
  ;; Result can be > 62 bits, so use safe shift
  (arithmetic-shift 1 (hamt-mask hash level)))

(define (hamt-index bitmap bitpos)
  "Count set bits before bitpos to get array index"
  ;; bitmap and bitpos can be bignums (64-bit values)
  (hamt-popcount (bitwise-and bitmap (sub1 bitpos))))

;; =============================================================================
;; Node Types
;; =============================================================================

(struct empty-node () #:transparent)
(define THE-EMPTY-NODE (empty-node))

(struct bitmap-node (bitmap array count) #:transparent)
(struct collision-node (hash entries count) #:transparent)
(struct entry (key value hash) #:transparent)

;; =============================================================================
;; Predicates
;; =============================================================================

(define (hamt? x)
  (or (empty-node? x)
      (bitmap-node? x)
      (collision-node? x)
      (entry? x)))

(define (hamt-empty? h)
  (empty-node? h))

(define (hamt-contains? h key)
  (not (eq? (hamt-ref h key 'hamt-not-found) 'hamt-not-found)))

;; =============================================================================
;; Constructors
;; =============================================================================

(define (empty-hamt)
  THE-EMPTY-NODE)

(define (hamt . pairs)
  (let loop ([pairs pairs] [h (empty-hamt)])
    (cond
      [(null? pairs) h]
      [(null? (cdr pairs))
       (error 'hamt "odd number of arguments")]
      [else
       (loop (cddr pairs)
             (hamt-set h (car pairs) (cadr pairs)))])))

;; =============================================================================
;; Count
;; =============================================================================

(define (hamt-count h)
  (match h
    [(empty-node) 0]
    [(bitmap-node _ _ count) count]
    [(collision-node _ _ count) count]
    [(entry _ _ _) 1]))

;; =============================================================================
;; Lookup (OPTIMIZED)
;; =============================================================================

(define (hamt-ref h key [default (lambda () (error 'hamt-ref "key not found: ~v" key))])
  (define hash (equal-hash-code key))
  (let loop ([node h] [level 0])
    (match node
      [(empty-node)
       (if (procedure? default) (default) default)]

      [(bitmap-node bitmap array _)
       (define bit (hamt-bitpos hash level))
       (if (zero? (bitwise-and bitmap bit))
           (if (procedure? default) (default) default)
           (let ([idx (hamt-index bitmap bit)])
             (loop (unsafe-vector-ref array idx) (unsafe-fx+ level 1))))]

      [(collision-node node-hash entries _)
       (if (= hash node-hash)
           (let ([found (assoc key entries)])
             (if found
                 (cdr found)
                 (if (procedure? default) (default) default)))
           (if (procedure? default) (default) default))]

      [(entry k v _)
       (if (equal? key k)
           v
           (if (procedure? default) (default) default))])))

;; =============================================================================
;; Insert (OPTIMIZED)
;; =============================================================================

(define (hamt-set h key value)
  (define hash (equal-hash-code key))
  (insert-node h key value hash 0))

(define (insert-node node key value hash level)
  (match node
    [(empty-node)
     (entry key value hash)]

    [(entry k v h)
     (cond
       [(equal? key k)
        (if (equal? value v)
            node
            (entry key value hash))]
       [(= hash h)
        (collision-node hash (list (cons key value) (cons k v)) 2)]
       [else
        (create-intermediate-node k v h key value hash level)])]

    [(bitmap-node bitmap array count)
     (define bit (hamt-bitpos hash level))
     (define idx (hamt-index bitmap bit))
     (cond
       [(zero? (bitwise-and bitmap bit))
        (define new-entry (entry key value hash))
        (define new-array (vector-insert array idx new-entry))
        (define new-bitmap (bitwise-ior bitmap bit))
        (bitmap-node new-bitmap new-array (unsafe-fx+ count 1))]
       [else
        (define child (unsafe-vector-ref array idx))
        (define new-child (insert-node child key value hash (unsafe-fx+ level 1)))
        (if (eq? new-child child)
            node
            (let ([count-diff (unsafe-fx- (hamt-count new-child) (hamt-count child))])
              (bitmap-node bitmap
                          (vector-update array idx new-child)
                          (unsafe-fx+ count count-diff))))])]

    [(collision-node node-hash entries count)
     (if (= hash node-hash)
         (let ([existing (assoc key entries)])
           (if existing
               (if (equal? (cdr existing) value)
                   node
                   (collision-node node-hash
                                  (cons (cons key value)
                                        (remove existing entries))
                                  count))
               (collision-node node-hash
                              (cons (cons key value) entries)
                              (unsafe-fx+ count 1))))
         (split-collision node key value hash level))]))

(define (create-intermediate-node k1 v1 h1 k2 v2 h2 level)
  (if (unsafe-fx>= level MAX-DEPTH)
      (collision-node h1 (list (cons k1 v1) (cons k2 v2)) 2)
      (let ([bit1 (hamt-bitpos h1 level)]
            [bit2 (hamt-bitpos h2 level)])
        (if (= bit1 bit2)
            (let ([child (create-intermediate-node k1 v1 h1 k2 v2 h2 (unsafe-fx+ level 1))])
              (bitmap-node bit1 (vector->immutable-vector (vector child)) 2))
            (if (< bit1 bit2)
                (bitmap-node (bitwise-ior bit1 bit2)
                            (vector->immutable-vector (vector (entry k1 v1 h1) (entry k2 v2 h2)))
                            2)
                (bitmap-node (bitwise-ior bit1 bit2)
                            (vector->immutable-vector (vector (entry k2 v2 h2) (entry k1 v1 h1)))
                            2))))))

(define (split-collision coll-node key value hash level)
  (match coll-node
    [(collision-node coll-hash entries count)
     (define bit-coll (hamt-bitpos coll-hash level))
     (define bit-new (hamt-bitpos hash level))
     (if (= bit-coll bit-new)
         (let ([child (split-collision coll-node key value hash (unsafe-fx+ level 1))])
           (bitmap-node bit-coll (vector->immutable-vector (vector child)) (unsafe-fx+ count 1)))
         (if (< bit-coll bit-new)
             (bitmap-node (bitwise-ior bit-coll bit-new)
                         (vector->immutable-vector (vector coll-node (entry key value hash)))
                         (unsafe-fx+ count 1))
             (bitmap-node (bitwise-ior bit-coll bit-new)
                         (vector->immutable-vector (vector (entry key value hash) coll-node))
                         (unsafe-fx+ count 1))))]))

;; =============================================================================
;; Delete (OPTIMIZED)
;; =============================================================================

(define (hamt-remove h key)
  (define hash (equal-hash-code key))
  (remove-node h key hash 0))

(define (remove-node node key hash level)
  (match node
    [(empty-node) node]

    [(entry k v _)
     (if (equal? key k)
         THE-EMPTY-NODE
         node)]

    [(bitmap-node bitmap array count)
     (define bit (hamt-bitpos hash level))
     (if (zero? (bitwise-and bitmap bit))
         node
         (let* ([idx (hamt-index bitmap bit)]
                [child (unsafe-vector-ref array idx)]
                [new-child (remove-node child key hash (unsafe-fx+ level 1))])
           (cond
             [(eq? new-child child) node]
             [(empty-node? new-child)
              (if (unsafe-fx= (hamt-popcount bitmap) 1)
                  THE-EMPTY-NODE
                  (bitmap-node (bitwise-and bitmap (bitwise-not bit))
                              (vector-remove array idx)
                              (unsafe-fx- count 1)))]
             [(entry? new-child)
              (bitmap-node bitmap
                          (vector-update array idx new-child)
                          (unsafe-fx- count 1))]
             [else
              (bitmap-node bitmap
                          (vector-update array idx new-child)
                          (unsafe-fx- count (unsafe-fx- (hamt-count child) (hamt-count new-child))))])))]

    [(collision-node node-hash entries count)
     (if (= hash node-hash)
         (let ([new-entries (filter (lambda (e) (not (equal? (car e) key))) entries)])
           (cond
             [(= (length new-entries) (length entries)) node]
             [(= (length new-entries) 1)
              (entry (caar new-entries) (cdar new-entries) node-hash)]
             [else
              (collision-node node-hash new-entries (length new-entries))]))
         node)]))

;; =============================================================================
;; Vector Helpers
;; =============================================================================

(define (vector-insert vec idx val)
  (define len (vector-length vec))
  (define new-vec (make-vector (unsafe-fx+ len 1)))
  (for ([i (in-range idx)])
    (unsafe-vector-set! new-vec i (unsafe-vector-ref vec i)))
  (unsafe-vector-set! new-vec idx val)
  (for ([i (in-range idx len)])
    (unsafe-vector-set! new-vec (unsafe-fx+ i 1) (unsafe-vector-ref vec i)))
  (vector->immutable-vector new-vec))

(define (vector-remove vec idx)
  (define len (vector-length vec))
  (define new-vec (make-vector (unsafe-fx- len 1)))
  (for ([i (in-range idx)])
    (unsafe-vector-set! new-vec i (unsafe-vector-ref vec i)))
  (for ([i (in-range (unsafe-fx+ idx 1) len)])
    (unsafe-vector-set! new-vec (unsafe-fx- i 1) (unsafe-vector-ref vec i)))
  (vector->immutable-vector new-vec))

(define (vector-update vec idx val)
  (define new-vec (vector-copy vec))
  (unsafe-vector-set! new-vec idx val)
  (vector->immutable-vector new-vec))

;; =============================================================================
;; Iteration & Conversion
;; =============================================================================

(define (hamt->list h)
  (hamt-fold (lambda (k v acc) (cons (cons k v) acc)) '() h))

(define (list->hamt lst)
  (for/fold ([h (empty-hamt)])
            ([pair (in-list lst)])
    (hamt-set h (car pair) (cdr pair))))

(define (hamt-keys h)
  (hamt-fold (lambda (k v acc) (cons k acc)) '() h))

(define (hamt-values h)
  (hamt-fold (lambda (k v acc) (cons v acc)) '() h))

(define (hamt-fold f init h)
  (fold-node f init h))

(define (fold-node f acc node)
  (match node
    [(empty-node) acc]
    [(entry k v _) (f k v acc)]
    [(bitmap-node _ array _)
     (for/fold ([acc acc])
               ([child (in-vector array)])
       (fold-node f acc child))]
    [(collision-node _ entries _)
     (for/fold ([acc acc])
               ([pair (in-list entries)])
       (f (car pair) (cdr pair) acc))]))
