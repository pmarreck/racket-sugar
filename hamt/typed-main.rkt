#lang typed/racket

;; HAMT - Hash Array Mapped Trie (Typed Racket version)
;; A persistent, immutable hash map with O(log64 n) operations
;;
;; Based on Phil Bagwell's "Ideal Hash Trees" paper
;; Using 64-way branching (6 bits per level, max 11 levels for 64-bit hash)

(require racket/match
									racket/vector)

(require/typed racket/unsafe/ops
		[unsafe-fxpopcount (-> Fixnum Fixnum)])

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

	;; Types
	HAMT)

;; =============================================================================
;; Constants
;; =============================================================================

(define BITS-PER-LEVEL : Fixnum 6)
(define BRANCHING-FACTOR : Fixnum 64)
(define MASK : Fixnum 63)  ; 0x3F
(define MAX-DEPTH : Fixnum 11)

;; =============================================================================
;; Types
;; =============================================================================

;; Forward declaration for recursive types
(define-type HAMTNode (U EmptyNode BitmapNode CollisionNode Entry))

;; Empty node singleton
(struct EmptyNode () #:transparent)

;; Bitmap-indexed node: sparse array compressed via bitmap
(struct BitmapNode
		([bitmap : Integer]
			[array : (Immutable-Vectorof HAMTNode)]
			[count : Integer])
		#:transparent)

;; Hash collision node: multiple entries with same hash
(struct CollisionNode
		([hash : Integer]
			[entries : (Listof (Pairof Any Any))]
			[count : Integer])
		#:transparent)

;; Entry: leaf node with key-value pair
(struct Entry
		([key : Any]
			[value : Any]
			[hash : Integer])
		#:transparent)

;; HAMT is just an alias for HAMTNode
(define-type HAMT HAMTNode)

(define THE-EMPTY-NODE : EmptyNode (EmptyNode))

;; =============================================================================
;; Bitwise Helpers
;; =============================================================================

(: hamt-popcount (-> Integer Integer))
(define (hamt-popcount n)
		(if (fixnum? n)
						(unsafe-fxpopcount n)
						(let loop ([n : Integer n] [count : Integer 0])
								(if (zero? n)
												count
												(loop (arithmetic-shift n -1)
																		(+ count (bitwise-and n 1)))))))

(: hamt-mask (-> Integer Integer Integer))
(define (hamt-mask hash level)
		(bitwise-and (arithmetic-shift hash (- (* (- MAX-DEPTH 1 level) BITS-PER-LEVEL)))
															MASK))

(: hamt-bitpos (-> Integer Integer Integer))
(define (hamt-bitpos hash level)
		(arithmetic-shift 1 (hamt-mask hash level)))

(: hamt-index (-> Integer Integer Integer))
(define (hamt-index bitmap bitpos)
		(hamt-popcount (bitwise-and bitmap (sub1 bitpos))))

;; =============================================================================
;; Predicates
;; =============================================================================

(: hamt? (-> Any Boolean))
(define (hamt? x)
		(or (EmptyNode? x)
						(BitmapNode? x)
						(CollisionNode? x)
						(Entry? x)))

(: hamt-empty? (-> HAMT Boolean))
(define (hamt-empty? h)
		(EmptyNode? h))

(: hamt-contains? (-> HAMT Any Boolean))
(define (hamt-contains? h key)
		(not (eq? (hamt-ref h key 'hamt-not-found) 'hamt-not-found)))

;; =============================================================================
;; Constructors
;; =============================================================================

(: empty-hamt (-> HAMT))
(define (empty-hamt)
		THE-EMPTY-NODE)

(: hamt (-> Any * HAMT))
(define (hamt . pairs)
		(let loop ([pairs : (Listof Any) pairs] [h : HAMT (empty-hamt)])
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

(: hamt-count (-> HAMT Integer))
(define (hamt-count h)
		(cond
				[(EmptyNode? h) 0]
				[(BitmapNode? h) (BitmapNode-count h)]
				[(CollisionNode? h) (CollisionNode-count h)]
				[(Entry? h) 1]
				[else 0]))

;; =============================================================================
;; Lookup
;; =============================================================================

(: hamt-ref (->* (HAMT Any) (Any) Any))
(define (hamt-ref h key [default (lambda () (error 'hamt-ref "key not found: ~v" key))])
		(define hash (equal-hash-code key))
		(let loop ([node : HAMT h] [level : Integer 0])
				(cond
						[(EmptyNode? node)
							(if (procedure? default) ((cast default (-> Any))) default)]

						[(BitmapNode? node)
							(define bitmap (BitmapNode-bitmap node))
							(define array (BitmapNode-array node))
							(define bit (hamt-bitpos hash level))
							(if (zero? (bitwise-and bitmap bit))
											(if (procedure? default) ((cast default (-> Any))) default)
											(let ([idx (hamt-index bitmap bit)])
													(loop (vector-ref array idx) (add1 level))))]

						[(CollisionNode? node)
							(define node-hash (CollisionNode-hash node))
							(define entries (CollisionNode-entries node))
							(if (= hash node-hash)
											(let ([found (assoc key entries)])
													(if found
																	(cdr found)
																	(if (procedure? default) ((cast default (-> Any))) default)))
											(if (procedure? default) ((cast default (-> Any))) default))]

						[(Entry? node)
							(if (equal? key (Entry-key node))
											(Entry-value node)
											(if (procedure? default) ((cast default (-> Any))) default))]

						[else
							(if (procedure? default) ((cast default (-> Any))) default)])))

;; =============================================================================
;; Insert
;; =============================================================================

(: hamt-set (-> HAMT Any Any HAMT))
(define (hamt-set h key value)
		(define hash (equal-hash-code key))
		(insert-node h key value hash 0))

(: insert-node (-> HAMT Any Any Integer Integer HAMT))
(define (insert-node node key value hash level)
		(cond
				[(EmptyNode? node)
					(Entry key value hash)]

				[(Entry? node)
					(define k (Entry-key node))
					(define v (Entry-value node))
					(define h (Entry-hash node))
					(cond
							[(equal? key k)
								(if (equal? value v)
												node
												(Entry key value hash))]
							[(= hash h)
								(CollisionNode hash (list (cons key value) (cons k v)) 2)]
							[else
								(create-intermediate-node k v h key value hash level)])]

				[(BitmapNode? node)
					(define bitmap (BitmapNode-bitmap node))
					(define array (BitmapNode-array node))
					(define count (BitmapNode-count node))
					(define bit (hamt-bitpos hash level))
					(define idx (hamt-index bitmap bit))
					(cond
							[(zero? (bitwise-and bitmap bit))
								(define new-entry (Entry key value hash))
								(define new-array (vector-insert array idx new-entry))
								(define new-bitmap (bitwise-ior bitmap bit))
								(BitmapNode new-bitmap new-array (add1 count))]
							[else
								(define child (vector-ref array idx))
								(define new-child (insert-node child key value hash (add1 level)))
								(if (eq? new-child child)
												node
												(let ([count-diff (- (hamt-count new-child) (hamt-count child))])
														(BitmapNode bitmap
																										(vector-update array idx new-child)
																										(+ count count-diff))))])]

				[(CollisionNode? node)
					(define node-hash (CollisionNode-hash node))
					(define entries (CollisionNode-entries node))
					(define count (CollisionNode-count node))
					(if (= hash node-hash)
									(let ([existing (assoc key entries)])
											(if existing
															(if (equal? (cdr existing) value)
																			node
																			(CollisionNode node-hash
																																		(cons (cons key value)
																																								(remove existing entries))
																																		count))
															(CollisionNode node-hash
																														(cons (cons key value) entries)
																														(add1 count))))
									(split-collision node key value hash level))]

				[else node]))

(: create-intermediate-node (-> Any Any Integer Any Any Integer Integer HAMT))
(define (create-intermediate-node k1 v1 h1 k2 v2 h2 level)
		(if (>= level MAX-DEPTH)
						(CollisionNode h1 (list (cons k1 v1) (cons k2 v2)) 2)
						(let ([bit1 (hamt-bitpos h1 level)]
												[bit2 (hamt-bitpos h2 level)])
								(if (= bit1 bit2)
												(let ([child (create-intermediate-node k1 v1 h1 k2 v2 h2 (add1 level))])
														(BitmapNode bit1 (vector->immutable-vector (vector child)) 2))
												(if (< bit1 bit2)
																(BitmapNode (bitwise-ior bit1 bit2)
																												(vector->immutable-vector (vector (Entry k1 v1 h1) (Entry k2 v2 h2)))
																												2)
																(BitmapNode (bitwise-ior bit1 bit2)
																												(vector->immutable-vector (vector (Entry k2 v2 h2) (Entry k1 v1 h1)))
																												2))))))

(: split-collision (-> CollisionNode Any Any Integer Integer HAMT))
(define (split-collision coll-node key value hash level)
		(define coll-hash (CollisionNode-hash coll-node))
		(define count (CollisionNode-count coll-node))
		(define bit-coll (hamt-bitpos coll-hash level))
		(define bit-new (hamt-bitpos hash level))
		(if (= bit-coll bit-new)
						(let ([child (split-collision coll-node key value hash (add1 level))])
								(BitmapNode bit-coll (vector->immutable-vector (ann (vector child) (Vectorof HAMTNode))) (add1 count)))
						(if (< bit-coll bit-new)
										(BitmapNode (bitwise-ior bit-coll bit-new)
																						(vector->immutable-vector (ann (vector coll-node (Entry key value hash)) (Vectorof HAMTNode)))
																						(add1 count))
										(BitmapNode (bitwise-ior bit-coll bit-new)
																						(vector->immutable-vector (ann (vector (Entry key value hash) coll-node) (Vectorof HAMTNode)))
																						(add1 count)))))

;; =============================================================================
;; Delete
;; =============================================================================

(: hamt-remove (-> HAMT Any HAMT))
(define (hamt-remove h key)
		(define hash (equal-hash-code key))
		(remove-node h key hash 0))

(: remove-node (-> HAMT Any Integer Integer HAMT))
(define (remove-node node key hash level)
		(cond
				[(EmptyNode? node) node]

				[(Entry? node)
					(if (equal? key (Entry-key node))
									THE-EMPTY-NODE
									node)]

				[(BitmapNode? node)
					(define bitmap (BitmapNode-bitmap node))
					(define array (BitmapNode-array node))
					(define count (BitmapNode-count node))
					(define bit (hamt-bitpos hash level))
					(if (zero? (bitwise-and bitmap bit))
									node
									(let* ([idx (hamt-index bitmap bit)]
																[child (vector-ref array idx)]
																[new-child (remove-node child key hash (add1 level))])
											(cond
													[(eq? new-child child) node]
													[(EmptyNode? new-child)
														(if (= (hamt-popcount bitmap) 1)
																		THE-EMPTY-NODE
																		(BitmapNode (bitwise-and bitmap (bitwise-not bit))
																														(vector-remove array idx)
																														(sub1 count)))]
													[(Entry? new-child)
														(BitmapNode bitmap
																										(vector-update array idx new-child)
																										(sub1 count))]
													[else
														(BitmapNode bitmap
																										(vector-update array idx new-child)
																										(- count (- (hamt-count child) (hamt-count new-child))))])))]

				[(CollisionNode? node)
					(define node-hash (CollisionNode-hash node))
					(define entries (CollisionNode-entries node))
					(define count (CollisionNode-count node))
					(if (= hash node-hash)
									(let ([new-entries (filter (lambda ([e : (Pairof Any Any)]) (not (equal? (car e) key))) entries)])
											(cond
													[(= (length new-entries) (length entries)) node]
													[(= (length new-entries) 1)
														(Entry (caar new-entries) (cdar new-entries) node-hash)]
													[else
														(CollisionNode node-hash new-entries (length new-entries))]))
									node)]

				[else node]))

;; =============================================================================
;; Vector Helpers
;; =============================================================================

(: vector-insert (-> (Immutable-Vectorof HAMTNode) Integer HAMTNode (Immutable-Vectorof HAMTNode)))
(define (vector-insert vec idx val)
		(define len (vector-length vec))
		(define new-vec : (Vectorof HAMTNode) (make-vector (add1 len) THE-EMPTY-NODE))
		(for ([i (in-range idx)])
				(vector-set! new-vec i (vector-ref vec i)))
		(vector-set! new-vec idx val)
		(for ([i (in-range idx len)])
				(vector-set! new-vec (add1 i) (vector-ref vec i)))
		(vector->immutable-vector new-vec))

(: vector-remove (-> (Immutable-Vectorof HAMTNode) Integer (Immutable-Vectorof HAMTNode)))
(define (vector-remove vec idx)
		(define len (vector-length vec))
		(define new-vec : (Vectorof HAMTNode) (make-vector (sub1 len) THE-EMPTY-NODE))
		(for ([i (in-range idx)])
				(vector-set! new-vec i (vector-ref vec i)))
		(for ([i (in-range (add1 idx) len)])
				(vector-set! new-vec (sub1 i) (vector-ref vec i)))
		(vector->immutable-vector new-vec))

(: vector-update (-> (Immutable-Vectorof HAMTNode) Integer HAMTNode (Immutable-Vectorof HAMTNode)))
(define (vector-update vec idx val)
		(define new-vec : (Vectorof HAMTNode) (vector-copy vec))
		(vector-set! new-vec idx val)
		(vector->immutable-vector new-vec))

;; =============================================================================
;; Iteration & Conversion
;; =============================================================================

(: hamt->list (-> HAMT (Listof (Pairof Any Any))))
(define (hamt->list h)
		(hamt-fold (lambda ([k : Any] [v : Any] [acc : (Listof (Pairof Any Any))])
															(cons (cons k v) acc))
													'() h))

(: list->hamt (-> (Listof (Pairof Any Any)) HAMT))
(define (list->hamt lst)
		(for/fold ([h : HAMT (empty-hamt)])
												([pair (in-list lst)])
				(hamt-set h (car pair) (cdr pair))))

(: hamt-keys (-> HAMT (Listof Any)))
(define (hamt-keys h)
		(hamt-fold (lambda ([k : Any] [v : Any] [acc : (Listof Any)])
															(cons k acc))
													'() h))

(: hamt-values (-> HAMT (Listof Any)))
(define (hamt-values h)
		(hamt-fold (lambda ([k : Any] [v : Any] [acc : (Listof Any)])
															(cons v acc))
													'() h))

(: hamt-fold (All (A) (-> (-> Any Any A A) A HAMT A)))
(define (hamt-fold f init h)
		(fold-node f init h))

(: fold-node (All (A) (-> (-> Any Any A A) A HAMT A)))
(define (fold-node f acc node)
		(cond
				[(EmptyNode? node) acc]
				[(Entry? node) (f (Entry-key node) (Entry-value node) acc)]
				[(BitmapNode? node)
					(for/fold ([acc : A acc])
															([child (in-vector (BitmapNode-array node))])
							(fold-node f acc child))]
				[(CollisionNode? node)
					(for/fold ([acc : A acc])
															([pair (in-list (CollisionNode-entries node))])
							(f (car pair) (cdr pair) acc))]
				[else acc]))
