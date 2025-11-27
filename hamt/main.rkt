#lang racket/base

;; HAMT - Hash Array Mapped Trie
;; A persistent, immutable hash map with O(log64 n) operations
;;
;; Based on Phil Bagwell's "Ideal Hash Trees" paper
;; Using 64-way branching (6 bits per level, max 11 levels for 64-bit hash)

(require racket/contract
         racket/match
         racket/vector
         (only-in racket/unsafe/ops unsafe-fxpopcount))

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
 hamt-index

 ;; Hash-compatible aliases (drop-in replacement API)
 (rename-out [hamt-ref hash-ref]
             [hamt-set hash-set]
             [hamt-remove hash-remove]
             [hamt-count hash-count]
             [hamt-contains? hash-has-key?]
             [hamt-keys hash-keys]
             [hamt-values hash-values]
             [hamt->list hash->list]))

;; =============================================================================
;; Constants
;; =============================================================================

(define BITS-PER-LEVEL 6)
(define BRANCHING-FACTOR 64)  ; 2^6
(define MASK (sub1 BRANCHING-FACTOR))  ; 0x3F = 63 = 0b111111
(define MAX-DEPTH 11)  ; ceil(64 / 6) for 64-bit hashes

;; =============================================================================
;; Bitwise Helpers
;; =============================================================================

(define (hamt-popcount n)
  "Count the number of 1-bits in n"
  ;; For fixnums, use fast unsafe operation
  ;; For bignums, fall back to manual counting
  (if (fixnum? n)
      (unsafe-fxpopcount n)
      ;; Manual popcount for bignums
      (let loop ([n n] [count 0])
        (if (zero? n)
            count
            (loop (arithmetic-shift n -1)
                  (+ count (bitwise-and n 1)))))))

(define (hamt-mask hash level)
  "Extract 6 bits from hash at the given level (0 = highest bits)"
  (bitwise-and (arithmetic-shift hash (- (* (- MAX-DEPTH 1 level) BITS-PER-LEVEL)))
               MASK))

(define (hamt-bitpos hash level)
  "Return bitmap with single bit set at position indicated by hash at level"
  (arithmetic-shift 1 (hamt-mask hash level)))

(define (hamt-index bitmap bitpos)
  "Count set bits before bitpos to get array index"
  (hamt-popcount (bitwise-and bitmap (sub1 bitpos))))

;; =============================================================================
;; Node Types
;; =============================================================================

;; Empty node singleton
(struct empty-node () #:transparent)
(define THE-EMPTY-NODE (empty-node))

;; Bitmap-indexed node: sparse array compressed via bitmap
(struct bitmap-node (bitmap    ; u64: which positions have children
                     array     ; vector of children (nodes or entries)
                     count)    ; total entry count in subtree
  #:transparent)

;; Hash collision node: multiple entries with same hash
(struct collision-node (hash     ; the shared hash value
                        entries  ; list of (key . value) pairs
                        count)   ; number of entries
  #:transparent)

;; Entry: leaf node with key-value pair
(struct entry (key value hash) #:transparent)

;; =============================================================================
;; Predicates
;; =============================================================================

(define (hamt? x)
  "Check if x is a HAMT node"
  (or (empty-node? x)
      (bitmap-node? x)
      (collision-node? x)
      (entry? x)))

(define (hamt-empty? h)
  "Check if HAMT is empty"
  (empty-node? h))

(define (hamt-contains? h key)
  "Check if HAMT contains key"
  (not (eq? (hamt-ref h key 'hamt-not-found) 'hamt-not-found)))

;; =============================================================================
;; Constructors
;; =============================================================================

(define (empty-hamt)
  "Create an empty HAMT"
  THE-EMPTY-NODE)

(define (hamt . pairs)
  "Create HAMT from key-value pairs: (hamt k1 v1 k2 v2 ...)"
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
  "Return the number of entries in the HAMT"
  (match h
    [(empty-node) 0]
    [(bitmap-node _ _ count) count]
    [(collision-node _ _ count) count]
    [(entry _ _ _) 1]
    [_ (error 'hamt-count "expected HAMT node, got: ~v" h)]))

;; =============================================================================
;; Lookup
;; =============================================================================

(define (hamt-ref h key [default (lambda () (error 'hamt-ref "key not found: ~v" key))])
  "Look up key in HAMT, return value or default"
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
             (loop (vector-ref array idx) (add1 level))))]

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
;; Insert
;; =============================================================================

(define (hamt-set h key value)
  "Insert or update key-value pair in HAMT"
  (define hash (equal-hash-code key))
  (insert-node h key value hash 0))

(define (insert-node node key value hash level)
  (match node
    [(empty-node)
     (entry key value hash)]

    [(entry k v h)
     (cond
       [(equal? key k)
        ;; Update existing entry
        (if (equal? value v)
            node  ; No change
            (entry key value hash))]
       [(= hash h)
        ;; Hash collision - create collision node
        (collision-node hash (list (cons key value) (cons k v)) 2)]
       [else
        ;; Different hashes - create bitmap node and insert both
        (create-intermediate-node k v h key value hash level)])]

    [(bitmap-node bitmap array count)
     (define bit (hamt-bitpos hash level))
     (define idx (hamt-index bitmap bit))
     (cond
       [(zero? (bitwise-and bitmap bit))
        ;; Position empty - add new entry
        (define new-entry (entry key value hash))
        (define new-array (vector-insert array idx new-entry))
        (define new-bitmap (bitwise-ior bitmap bit))
        (bitmap-node new-bitmap new-array (add1 count))]
       [else
        ;; Position occupied - recurse into child
        (define child (vector-ref array idx))
        (define new-child (insert-node child key value hash (add1 level)))
        (if (eq? new-child child)
            node  ; No change
            (let ([count-diff (- (hamt-count new-child) (hamt-count child))])
              (bitmap-node bitmap
                          (vector-update array idx new-child)
                          (+ count count-diff))))])]

    [(collision-node node-hash entries count)
     (if (= hash node-hash)
         ;; Same hash - add to collision list
         (let ([existing (assoc key entries)])
           (if existing
               (if (equal? (cdr existing) value)
                   node  ; No change
                   (collision-node node-hash
                                  (cons (cons key value)
                                        (remove existing entries))
                                  count))
               (collision-node node-hash
                              (cons (cons key value) entries)
                              (add1 count))))
         ;; Different hash - need to split
         (split-collision node key value hash level))]))

(define (create-intermediate-node k1 v1 h1 k2 v2 h2 level)
  "Create intermediate nodes until hashes diverge, then place both entries"
  (if (>= level MAX-DEPTH)
      ;; Shouldn't happen with good hash, but handle it
      (collision-node h1 (list (cons k1 v1) (cons k2 v2)) 2)
      (let ([bit1 (hamt-bitpos h1 level)]
            [bit2 (hamt-bitpos h2 level)])
        (if (= bit1 bit2)
            ;; Same position at this level - go deeper
            (let ([child (create-intermediate-node k1 v1 h1 k2 v2 h2 (add1 level))])
              (bitmap-node bit1 (vector child) 2))
            ;; Different positions - place both entries
            (if (< bit1 bit2)
                (bitmap-node (bitwise-ior bit1 bit2)
                            (vector (entry k1 v1 h1) (entry k2 v2 h2))
                            2)
                (bitmap-node (bitwise-ior bit1 bit2)
                            (vector (entry k2 v2 h2) (entry k1 v1 h1))
                            2))))))

(define (split-collision coll-node key value hash level)
  "Split a collision node when a new entry has a different hash"
  (match coll-node
    [(collision-node coll-hash entries count)
     (define bit-coll (hamt-bitpos coll-hash level))
     (define bit-new (hamt-bitpos hash level))
     (if (= bit-coll bit-new)
         ;; Same position - go deeper
         (let ([child (split-collision coll-node key value hash (add1 level))])
           (bitmap-node bit-coll (vector child) (add1 count)))
         ;; Different positions
         (if (< bit-coll bit-new)
             (bitmap-node (bitwise-ior bit-coll bit-new)
                         (vector coll-node (entry key value hash))
                         (add1 count))
             (bitmap-node (bitwise-ior bit-coll bit-new)
                         (vector (entry key value hash) coll-node)
                         (add1 count))))]))

;; =============================================================================
;; Delete
;; =============================================================================

(define (hamt-remove h key)
  "Remove key from HAMT, return new HAMT"
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
         node  ; Key not found
         (let* ([idx (hamt-index bitmap bit)]
                [child (vector-ref array idx)]
                [new-child (remove-node child key hash (add1 level))])
           (cond
             [(eq? new-child child) node]  ; No change
             [(empty-node? new-child)
              ;; Remove this position
              (if (= (hamt-popcount bitmap) 1)
                  THE-EMPTY-NODE  ; Last entry
                  (bitmap-node (bitwise-and bitmap (bitwise-not bit))
                              (vector-remove array idx)
                              (sub1 count)))]
             [(entry? new-child)
              ;; Child collapsed to entry - keep it inline
              (bitmap-node bitmap
                          (vector-update array idx new-child)
                          (sub1 count))]
             [else
              ;; Normal case
              (bitmap-node bitmap
                          (vector-update array idx new-child)
                          (- count (- (hamt-count child) (hamt-count new-child))))])))]

    [(collision-node node-hash entries count)
     (if (= hash node-hash)
         (let ([new-entries (filter (lambda (e) (not (equal? (car e) key))) entries)])
           (cond
             [(= (length new-entries) (length entries)) node]  ; Key not found
             [(= (length new-entries) 1)
              ;; Collapse to single entry
              (entry (caar new-entries) (cdar new-entries) node-hash)]
             [else
              (collision-node node-hash new-entries (length new-entries))]))
         node)]))

;; =============================================================================
;; Vector Helpers
;; =============================================================================

(define (vector-insert vec idx val)
  "Insert val at idx, shifting elements right"
  (define len (vector-length vec))
  (define new-vec (make-vector (add1 len)))
  (for ([i (in-range idx)])
    (vector-set! new-vec i (vector-ref vec i)))
  (vector-set! new-vec idx val)
  (for ([i (in-range idx len)])
    (vector-set! new-vec (add1 i) (vector-ref vec i)))
  (vector->immutable-vector new-vec))

(define (vector-remove vec idx)
  "Remove element at idx, shifting elements left"
  (define len (vector-length vec))
  (define new-vec (make-vector (sub1 len)))
  (for ([i (in-range idx)])
    (vector-set! new-vec i (vector-ref vec i)))
  (for ([i (in-range (add1 idx) len)])
    (vector-set! new-vec (sub1 i) (vector-ref vec i)))
  (vector->immutable-vector new-vec))

(define (vector-update vec idx val)
  "Return new vector with val at idx"
  (define new-vec (vector-copy vec))
  (vector-set! new-vec idx val)
  (vector->immutable-vector new-vec))

;; =============================================================================
;; Iteration & Conversion
;; =============================================================================

(define (hamt->list h)
  "Convert HAMT to association list"
  (hamt-fold (lambda (k v acc) (cons (cons k v) acc)) '() h))

(define (list->hamt lst)
  "Create HAMT from association list"
  (for/fold ([h (empty-hamt)])
            ([pair (in-list lst)])
    (hamt-set h (car pair) (cdr pair))))

(define (hamt-keys h)
  "Return list of all keys"
  (hamt-fold (lambda (k v acc) (cons k acc)) '() h))

(define (hamt-values h)
  "Return list of all values"
  (hamt-fold (lambda (k v acc) (cons v acc)) '() h))

(define (hamt-fold f init h)
  "Fold f over all key-value pairs: (f key value acc)"
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
