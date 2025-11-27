#lang tab-racket

;; Word Frequency Counter
;; Demonstrates tab-racket with persistent data structures
;; 
;; Features shown:
;; - {} syntax for persistent HAMT (hash maps)
;; - [] syntax for persistent vectors  
;; - Tab-based significant indentation

define sample-text "the quick brown fox jumps over the lazy dog the fox was quick"

;; Split string into words
define split-words
	lambda (text)
		regexp-split #rx" +" (string-downcase text)

;; Count words using HAMT
define count-words
	lambda (words)
		foldl
			lambda (word freq-map)
				define current (hamt-ref freq-map word 0)
				hamt-set freq-map word (+ current 1)
			{}
			words

;; Sort by frequency descending
define sort-by-freq
	lambda (freq-map)
		sort
			hamt->list freq-map
			lambda (a b)
				> (cdr a) (cdr b)

;; Build histogram bars
define histogram
	lambda (sorted max-width)
		define max-count
			if (null? sorted)
				1
				cdr (car sorted)
		for/list ((pair sorted))
			define word (car pair)
			define count (cdr pair)
			define width (quotient (* count max-width) max-count)
			format "~a ~a ~a"
				~a word #:width 10
				make-string width #\█
				count

;; Demo persistence - key feature of these data structures!
define demo-persistence
	lambda ()
		displayln "\n=== Persistence Demo ==="
		;; Vectors
		define v1 [1 2 3]
		define v2 (pvector-push v1 4)
		displayln (format "v1 = [1 2 3]:        ~a" (pvector->list v1))
		displayln (format "v2 = (push v1 4):    ~a" (pvector->list v2))
		displayln "v1 is UNCHANGED! That's persistence."
		;; Hash maps
		displayln ""
		define m1 {"a" 1}
		define m2 (hamt-set m1 "b" 2)
		displayln (format "m1 = {a: 1}:         ~a" (hamt->list m1))
		displayln (format "m2 = (set m1 b 2):   ~a" (hamt->list m2))
		displayln "m1 is UNCHANGED! Structural sharing FTW."

;; Run the demo
displayln "╔══════════════════════════════════════════╗"
displayln "║   Word Frequency Counter (tab-racket)    ║"
displayln "╚══════════════════════════════════════════╝"
displayln ""
displayln (format "Input: ~a" sample-text)
define words (split-words sample-text)
define freq (count-words words)
define sorted (sort-by-freq freq)
displayln (format "\nTotal words: ~a | Unique: ~a" (length words) (hamt-count freq))
displayln "\n=== Frequency Histogram ==="
for-each displayln (histogram sorted 25)
(demo-persistence)
