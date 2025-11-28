#lang typed/racket

;; Persistent Vector (PVector) - Typed Racket version with optimizer
;; A persistent, immutable vector with O(log32 n) operations
;;
;; Based on Clojure's PersistentVector
;; Using 32-way branching (5 bits per level) - all values fit in fixnums!

(require racket/match
									racket/unsafe/ops)

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
	pvector-push
	pvector-pop
	pvector-length

	;; Conversion
	pvector->list
	pvector->vector

	;; Iteration
	pvector-fold
	in-pvector

	;; Type export
	PVector)

;; =============================================================================
;; Constants (all fixnums)
;; =============================================================================

(define BITS : Fixnum 5)
(define BRANCHING : Fixnum 32)
(define MASK : Fixnum 31)

;; =============================================================================
;; Types
;; =============================================================================

;; Node is either a branch (vector of nodes) or a leaf (vector of values)
(define-type Node (U (Vectorof Any) #f))

;; A pvector struct
(struct pv
		([count : Fixnum]
			[shift : Fixnum]
			[root : Node]
			[tail : (Vectorof Any)])
		#:transparent)

(define-type PVector pv)

;; Empty pvector singleton
(define THE-EMPTY-PVECTOR : pv (pv 0 BITS #f (vector->immutable-vector #())))

;; =============================================================================
;; Predicates
;; =============================================================================

(: pvector? (-> Any Boolean : PVector))
(define (pvector? x)
		(pv? x))

(: pvector-empty? (-> PVector Boolean))
(define (pvector-empty? v)
		(unsafe-fx= (pv-count v) 0))

;; =============================================================================
;; Constructors
;; =============================================================================

(: empty-pvector (-> PVector))
(define (empty-pvector)
		THE-EMPTY-PVECTOR)

(: pvector (-> Any * PVector))
(define (pvector . items)
		(list->pvector items))

(: list->pvector (-> (Listof Any) PVector))
(define (list->pvector lst)
		(for/fold ([v : PVector (empty-pvector)])
												([item (in-list lst)])
				(pvector-push v item)))

(: vector->pvector (-> (Vectorof Any) PVector))
(define (vector->pvector vec)
		(for/fold ([v : PVector (empty-pvector)])
												([item (in-vector vec)])
				(pvector-push v item)))

;; =============================================================================
;; Length
;; =============================================================================

(: pvector-length (-> PVector Fixnum))
(define (pvector-length v)
		(pv-count v))

;; =============================================================================
;; Tail Operations
;; =============================================================================

(: tail-offset (-> PVector Fixnum))
(define (tail-offset v)
		(let ([cnt (pv-count v)])
				(if (unsafe-fx< cnt BRANCHING)
								0
								(unsafe-fxand (unsafe-fx- cnt 1) (unsafe-fxnot MASK)))))

;; =============================================================================
;; Lookup
;; =============================================================================

(: pvector-ref (->* (PVector Fixnum) (Any) Any))
(define (pvector-ref v idx [default (lambda () (error 'pvector-ref "index out of bounds: ~a" idx))])
		(if (or (unsafe-fx< idx 0) (unsafe-fx>= idx (pv-count v)))
						(if (procedure? default) ((cast default (-> Any))) default)
						(let ([arr (array-for v idx)])
								(unsafe-vector-ref arr (unsafe-fxand idx MASK)))))

(: array-for (-> PVector Fixnum (Vectorof Any)))
(define (array-for v idx)
		(if (unsafe-fx>= idx (tail-offset v))
						(pv-tail v)
						(let loop ([node : (Vectorof Any) (cast (pv-root v) (Vectorof Any))]
																	[level : Fixnum (pv-shift v)])
								(if (unsafe-fx> level 0)
												(loop (cast (unsafe-vector-ref node (unsafe-fxand (unsafe-fxrshift idx level) MASK)) (Vectorof Any))
																		(unsafe-fx- level BITS))
												node))))

;; =============================================================================
;; Update
;; =============================================================================

(: pvector-set (-> PVector Fixnum Any PVector))
(define (pvector-set v idx val)
		(when (or (unsafe-fx< idx 0) (unsafe-fx>= idx (pv-count v)))
				(error 'pvector-set "index out of bounds: ~a" idx))
		(if (unsafe-fx>= idx (tail-offset v))
						;; Update in tail
						(let* ([tail (pv-tail v)]
													[new-tail : (Vectorof Any) (vector-copy tail)])
								(unsafe-vector-set! new-tail (unsafe-fxand idx MASK) val)
								(pv (pv-count v) (pv-shift v) (pv-root v) (vector->immutable-vector new-tail)))
						;; Update in trie
						(pv (pv-count v) (pv-shift v)
										(do-set (pv-shift v) (cast (pv-root v) (Vectorof Any)) idx val)
										(pv-tail v))))

(: do-set (-> Fixnum (Vectorof Any) Fixnum Any (Vectorof Any)))
(define (do-set level node idx val)
		(let ([new-node : (Vectorof Any) (vector-copy node)]
								[subidx (unsafe-fxand (unsafe-fxrshift idx level) MASK)])
				(if (unsafe-fx= level 0)
								;; At leaf level - set value directly
								(begin
										(unsafe-vector-set! new-node subidx val)
										(vector->immutable-vector new-node))
								;; Recurse into child
								(begin
										(unsafe-vector-set! new-node subidx
																														(do-set (unsafe-fx- level BITS)
																																					(cast (unsafe-vector-ref node subidx) (Vectorof Any))
																																					idx val))
										(vector->immutable-vector new-node)))))

;; =============================================================================
;; Push (Append)
;; =============================================================================

(: new-path (-> Fixnum (Vectorof Any) (Vectorof Any)))
(define (new-path level node)
		(if (unsafe-fx= level BITS)
						(vector->immutable-vector (vector node))
						(vector->immutable-vector (vector (new-path (unsafe-fx- level BITS) node)))))

(: pvector-push (-> PVector Any PVector))
(define (pvector-push v val)
		(let ([cnt (pv-count v)]
								[tail (pv-tail v)])
				(cond
						;; Room in tail?
						[(unsafe-fx< (unsafe-fx- cnt (tail-offset v)) BRANCHING)
							(let ([new-tail (vector-append tail (vector val))])
									(pv (unsafe-fx+ cnt 1) (pv-shift v) (pv-root v) (vector->immutable-vector new-tail)))]
						;; Tail is full, push it into the trie
						[else
							(let* ([tail-node : (Vectorof Any) (vector->immutable-vector tail)]
														[overflow? (and (pv-root v)
																													(unsafe-fx> cnt (unsafe-fxlshift BRANCHING (pv-shift v))))]
														[new-shift (if overflow? (unsafe-fx+ (pv-shift v) BITS) (pv-shift v))]
														[new-root : (Vectorof Any)
																								(cond
																										[overflow?
																											(vector->immutable-vector
																													(vector (pv-root v) (new-path (pv-shift v) tail-node)))]
																										[(pv-root v)
																											(push-tail (pv-shift v) (cast (pv-root v) (Vectorof Any)) tail-node cnt)]
																										[else
																											(vector->immutable-vector (vector tail-node))])])
									(pv (unsafe-fx+ cnt 1) new-shift new-root (vector val)))])))

(: push-tail (-> Fixnum (Vectorof Any) (Vectorof Any) Fixnum (Vectorof Any)))
(define (push-tail shift parent tail-node cnt)
		(let* ([subidx (unsafe-fxand (unsafe-fxrshift (unsafe-fx- cnt 1) shift) MASK)]
									[parent-len (vector-length parent)]
									[new-len (unsafe-fx+ subidx 1)]
									[new-parent : (Vectorof Any) (make-vector new-len #f)])
				;; Copy existing elements from parent
				(for ([i (in-range (min parent-len new-len))])
						(unsafe-vector-set! new-parent i (unsafe-vector-ref parent i)))
				(if (unsafe-fx= shift BITS)
								;; At leaf level
								(begin
										(unsafe-vector-set! new-parent subidx tail-node)
										(vector->immutable-vector new-parent))
								;; Recurse
								(let ([child (and (unsafe-fx< subidx parent-len)
																									(unsafe-vector-ref parent subidx))])
										(unsafe-vector-set! new-parent subidx
																														(if child
																																		(push-tail (unsafe-fx- shift BITS) (cast child (Vectorof Any)) tail-node cnt)
																																		(new-path (unsafe-fx- shift BITS) tail-node)))
										(vector->immutable-vector new-parent)))))

;; =============================================================================
;; Pop (Remove from end)
;; =============================================================================

(: pvector-pop (-> PVector PVector))
(define (pvector-pop v)
		(let ([cnt (pv-count v)])
				(cond
						[(unsafe-fx= cnt 0)
							(error 'pvector-pop "cannot pop from empty pvector")]
						[(unsafe-fx= cnt 1)
							THE-EMPTY-PVECTOR]
						;; More than one element in tail?
						[(unsafe-fx> (vector-length (pv-tail v)) 1)
							(let ([new-tail (vector-copy (pv-tail v) 0 (unsafe-fx- (vector-length (pv-tail v)) 1))])
									(pv (unsafe-fx- cnt 1) (pv-shift v) (pv-root v) (vector->immutable-vector new-tail)))]
						;; Pop from trie
						[else
							(let* ([new-tail (array-for v (unsafe-fx- cnt 2))]
														[new-root (pop-tail (pv-shift v) (cast (pv-root v) (Vectorof Any)) cnt)]
														[can-shrink? (and new-root
																															(unsafe-fx= (vector-length new-root) 1)
																															(unsafe-fx> (pv-shift v) BITS))]
														[new-shift (if can-shrink? (unsafe-fx- (pv-shift v) BITS) (pv-shift v))]
														[final-root (if can-shrink? (cast (unsafe-vector-ref new-root 0) (Vectorof Any)) new-root)])
									(pv (unsafe-fx- cnt 1) new-shift final-root new-tail))])))

(: pop-tail (-> Fixnum (Vectorof Any) Fixnum (U (Vectorof Any) #f)))
(define (pop-tail shift node cnt)
		(let ([subidx (unsafe-fxand (unsafe-fxrshift (unsafe-fx- cnt 2) shift) MASK)])
				(if (unsafe-fx= shift BITS)
								;; At leaf level
								(if (unsafe-fx= subidx 0)
												#f
												(let ([new-node (vector-copy node 0 subidx)])
														(vector->immutable-vector new-node)))
								;; Recurse
								(let ([child (pop-tail (unsafe-fx- shift BITS) (cast (unsafe-vector-ref node subidx) (Vectorof Any)) cnt)])
										(if (and (not child) (unsafe-fx= subidx 0))
														#f
														(let ([new-node : (Vectorof Any) (vector-copy node)])
																(unsafe-vector-set! new-node subidx child)
																(vector->immutable-vector new-node)))))))

;; =============================================================================
;; Conversion
;; =============================================================================

(: pvector->list (-> PVector (Listof Any)))
(define (pvector->list v)
		(pvector-fold (lambda ([acc : (Listof Any)] [item : Any]) (cons item acc)) '() v #:reverse? #t))

(: pvector->vector (-> PVector (Vectorof Any)))
(define (pvector->vector v)
		(let ([result : (Vectorof Any) (make-vector (pv-count v))])
				(for ([i (in-range (pv-count v))])
						(unsafe-vector-set! result (assert i fixnum?) (pvector-ref v (assert i fixnum?))))
				(vector->immutable-vector result)))

;; =============================================================================
;; Iteration
;; =============================================================================

(: pvector-fold (All (A) (->* ((-> A Any A) A PVector) (#:reverse? Boolean) A)))
(define (pvector-fold f init v #:reverse? [reverse? #f])
		(if reverse?
						(for/fold ([acc : A init])
																([i (in-range (unsafe-fx- (pv-count v) 1) -1 -1)])
								(f acc (pvector-ref v (assert i fixnum?))))
						(for/fold ([acc : A init])
																([i (in-range (pv-count v))])
								(f acc (pvector-ref v (assert i fixnum?))))))

(: in-pvector (-> PVector (Sequenceof Any)))
(define (in-pvector v)
		(make-do-sequence
			(lambda ()
					(values
						(lambda ([i : Integer]) (pvector-ref v (assert i fixnum?)))
						add1
						0
						(lambda ([i : Integer]) (< i (pv-count v)))
						#f
						#f))))
