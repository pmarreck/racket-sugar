#lang racket
(require (only-in racket [read racket-read])
				 (prefix-in hamt: "../hamt/main.rkt")
				 (prefix-in pv: "../pvector/main.rkt"))
(provide read read-syntax
				 ;; Re-export HAMT functions for users
				 (rename-out [hamt:empty-hamt empty-hamt]
										 [hamt:hamt hamt]
										 [hamt:hamt? hamt?]
										 [hamt:hamt-empty? hamt-empty?]
										 [hamt:hamt-contains? hamt-contains?]
										 [hamt:hamt-ref hamt-ref]
										 [hamt:hamt-set hamt-set]
										 [hamt:hamt-remove hamt-remove]
										 [hamt:hamt-count hamt-count]
										 [hamt:hamt->list hamt->list]
										 [hamt:list->hamt list->hamt]
										 [hamt:hamt-keys hamt-keys]
										 [hamt:hamt-values hamt-values]
										 [hamt:hamt-fold hamt-fold])
				 ;; Re-export PVector functions for users
				 (rename-out [pv:empty-pvector empty-pvector]
										 [pv:pvector pvector]
										 [pv:pvector? pvector?]
										 [pv:pvector-empty? pvector-empty?]
										 [pv:pvector-ref pvector-ref]
										 [pv:pvector-set pvector-set]
										 [pv:pvector-push pvector-push]
										 [pv:pvector-pop pvector-pop]
										 [pv:pvector-length pvector-length]
										 [pv:pvector->list pvector->list]
										 [pv:pvector->vector pvector->vector]
										 [pv:list->pvector list->pvector]
										 [pv:vector->pvector vector->pvector]
										 [pv:pvector-fold pvector-fold]
										 [pv:in-pvector in-pvector]))

;; --- Clojure-style Literal Support ---
;; [...]  -> persistent vector (pvector)
;; ![...] -> mutable vector
;; {...}  -> persistent HAMT (Hash Array Mapped Trie)
;; !{...} -> mutable hash map (hasheq)

;; Read until closing delimiter, using our custom readtable
(define (read-delimited-list close-char port readtable)
	(let loop ([items '()])
		(skip-whitespace-and-comments port)
		(let ([ch (peek-char port)])
			(cond
				[(eof-object? ch)
				 (error (format "Unexpected EOF, expected '~a'" close-char))]
				[(char=? ch close-char)
				 (read-char port)  ; consume closing delimiter
				 (reverse items)]
				[else
				 (let ([item (read-with-table port readtable)])
					 (loop (cons item items)))]))))

(define (skip-whitespace-and-comments port)
	(let ([ch (peek-char port)])
		(cond
			[(eof-object? ch) (void)]
			[(char-whitespace? ch)
			 (read-char port)
			 (skip-whitespace-and-comments port)]
			[(char=? ch #\;)  ; line comment
			 (read-line port)
			 (skip-whitespace-and-comments port)]
			[else (void)])))

;; Helper: prepare a value for runtime evaluation
;; - Keywords (symbols starting with :) are quoted so they stay as symbols
;; - Other symbols are left unquoted so they're evaluated as variables
;; - Numbers, strings, booleans stay as-is (self-evaluating)
;; - Nested structures (lists from [] or {}) are left as-is (already runtime exprs)
(define (prepare-for-runtime v)
	(cond
		[(and (symbol? v)
					(let ([s (symbol->string v)])
						(and (> (string-length s) 0)
								 (char=? (string-ref s 0) #\:))))
		 ;; Keyword-style symbol - quote it
		 `(quote ,v)]
		[(or (number? v) (string? v) (boolean? v) (char? v))
		 ;; Self-evaluating literals
		 v]
		[(and (pair? v) (memq (car v) '(quote pvector hamt vector make-hasheq)))
		 ;; Already a runtime expression or quoted
		 v]
		[(symbol? v)
		 ;; Regular symbol - leave unquoted for variable reference
		 v]
		[else v]))

;; Reader for [...] -> persistent vector (runtime expression)
(define (read-bracket ch port src line col pos)
	(let ([items (read-delimited-list #\] port clojure-readtable)])
		`(pvector ,@(map prepare-for-runtime items))))

;; Reader for {...} -> persistent HAMT (runtime expression)
(define (read-brace ch port src line col pos)
	(let ([items (read-delimited-list #\} port clojure-readtable)])
		(unless (even? (length items))
			(error "Hash literal requires even number of elements (key-value pairs)"))
		`(hamt ,@(map prepare-for-runtime items))))

;; Helper: quote a value if it needs quoting (symbols need quotes, literals don't)
(define (maybe-quote v)
	(cond
		[(or (number? v) (string? v) (boolean? v) (char? v)) v]
		[(and (pair? v) (eq? (car v) 'quote)) v]  ; already quoted
		[(or (symbol? v) (pair? v) (vector? v) (hash? v)) `(quote ,v)]
		[else v]))

;; Reader for ![ and !{ -> mutable variants
;; Returns code that creates mutable data at runtime (literals become immutable when compiled)
(define (read-bang ch port src line col pos)
	(let ([next (peek-char port)])
		(cond
			[(char=? next #\[)
			 (read-char port)  ; consume [
			 (let ([items (read-delimited-list #\] port clojure-readtable)])
				 ;; Return (vector item ...) to create mutable vector at runtime
				 `(vector ,@(map maybe-quote items)))]
			[(char=? next #\{)
			 (read-char port)  ; consume {
			 (let ([items (read-delimited-list #\} port clojure-readtable)])
				 (unless (even? (length items))
					 (error "Hash literal requires even number of elements (key-value pairs)"))
				 ;; Return (make-hasheq (list (cons 'k 'v) ...)) to create mutable hash at runtime
				 (let ([pairs (let loop ([items items] [acc '()])
												(if (null? items)
														(reverse acc)
														(let ([k (car items)]
																	[v (cadr items)])
															(loop (cddr items)
																		(cons `(cons ,(maybe-quote k) ,(maybe-quote v)) acc)))))])
					 `(make-hasheq (list ,@pairs))))]
			[else
			 ;; Not ![ or !{, so re-read as normal (likely a symbol like !foo)
			 (let ([sym-str (string-append "!" (symbol->string (racket-read port)))])
				 (string->symbol sym-str))])))

;; Helper for mutable hash: applies key-value pairs to a hash
(define (hasheq! h . kvs)
	(let loop ([kvs kvs])
		(if (null? kvs)
				h
				(begin
					(hash-set! h (car kvs) (cadr kvs))
					(loop (cddr kvs))))))

;; Read using our custom readtable
(define (read-with-table port readtable)
	(parameterize ([current-readtable readtable])
		(racket-read port)))

;; Custom readtable with Clojure-style literals
(define clojure-readtable
	(make-readtable #f
									#\[ 'terminating-macro read-bracket
									#\] 'terminating-macro (lambda args (error "Unexpected ']'"))
									#\{ 'terminating-macro read-brace
									#\} 'terminating-macro (lambda args (error "Unexpected '}'"))
									#\! 'non-terminating-macro read-bang))

;; --- Indentation Parser Logic ---

(struct line (indent content original-line-num) #:transparent)

(define (count-indent str line-num)
	(let loop ([chars (string->list str)] [count 0])
		(match chars
			[(cons #\tab rest) (loop rest (add1 count))]
			[(cons #\space rest)
			 (error (format "Line ~a: Indentation Error. TABS ONLY." line-num))]
			[_ count])))

;; Helper: Check if a symbol is a keyword (starts with : and has more chars)
;; Note: bare ":" is NOT a keyword (used for type annotations in typed racket)
(define (keyword-symbol? v)
	(and (symbol? v)
			 (let ([s (symbol->string v)])
				 (and (> (string-length s) 1)  ; Must be more than just ":"
							(char=? (string-ref s 0) #\:)))))

;; Helper: Check if a symbol is an infix operator (starts with ~)
;; ~+ means infix +, ~mod means infix mod, etc.
(define (infix-symbol? v)
	(and (symbol? v)
			 (let ([s (symbol->string v)])
				 (and (> (string-length s) 1)  ; Must be more than just "~"
							(char=? (string-ref s 0) #\~)))))

;; Extract the actual function name from an infix symbol
;; ~+ -> +, ~mod -> mod, ~-> -> ->
(define (infix->func sym)
	(string->symbol (substring (symbol->string sym) 1)))

;; Transform infix expressions: (a ~func b ...) -> (func a b ...)
;; Finds any ~func symbol in second position of a list and moves it to front
;; Recursively processes nested lists
(define (transform-infix v)
	(cond
		[(and (pair? v)
					(>= (length v) 3)  ; Need at least (a ~op b)
					(infix-symbol? (cadr v)))  ; Second element is ~something
		 ;; Transform: (a ~func b ...) -> (func a b ...)
		 (let ([left (transform-infix (car v))]      ; First arg (recurse)
					 [op (infix->func (cadr v))]          ; The function (strip ~)
					 [rest (map transform-infix (cddr v))]) ; Remaining args (recurse)
			 (cons op (cons left rest)))]
		[(pair? v)
		 ;; Not an infix expression, but still recurse into sub-expressions
		 (map transform-infix v)]
		[else v]))

;; Helper: Auto-quote keywords (symbols starting with :) to make them self-evaluating
;; This mimics Clojure/Ruby/Elixir behavior where :foo evaluates to itself
;; Recursively processes nested lists (but not already-quoted forms)
(define (auto-quote-keyword v)
	(cond
		[(keyword-symbol? v) `(quote ,v)]
		[(and (pair? v) (not (eq? (car v) 'quote)))
		 ;; Recursively process lists (but skip quoted forms)
		 (map auto-quote-keyword v)]
		[else v]))

(define (tokenize-line str)
	(let ([in (open-input-string str)])
		(let loop ([tokens '()])
			(let ([token (read-with-table in clojure-readtable)])
				(if (eof-object? token)
						(reverse tokens)
						;; Apply keyword quoting during tokenization (infix transform happens after parsing)
						(loop (cons (auto-quote-keyword token) tokens)))))))

(define (split-f-list lst pred)
	(let loop ([l lst] [acc '()])
		(if (or (null? l) (not (pred (car l))))
				(values (reverse acc) l)
				(loop (cdr l) (cons (car l) acc)))))

(define (split-by-indent lines target-indent)
	(split-f-list lines (lambda (l) (>= (line-indent l) target-indent))))

(define (parse-block lines current-indent)
	(let loop ([remaining lines] [acc '()])
		(if (null? remaining)
				(reverse acc)
				(let* ([current (car remaining)]
							 [next-lines (cdr remaining)]
							 [c-indent (line-indent current)]
							 [c-content (line-content current)])
					(cond
						[(null? c-content) (loop next-lines acc)]
						[(< c-indent current-indent) (error "Dedent error.")]
						[(= c-indent current-indent)
						 (define-values (children siblings)
							 (split-by-indent next-lines (add1 current-indent)))
						 (define parsed-children
							 (if (null? children) '() (parse-block children (add1 current-indent))))
						 (define expr
							 (cond
								 [(not (null? parsed-children)) (append c-content parsed-children)]
								 [(> (length c-content) 1) c-content]
								 [else (car c-content)]))
						 (loop siblings (cons expr acc))]
						[else (error "Indentation gap error.")])))))

;; Check if a line ends with \ (line continuation marker)
;; Returns #t if the line ends with backslash (possibly followed by whitespace)
(define (line-continues? str)
	(let ([trimmed (string-trim str #:left? #f)])
		(and (> (string-length trimmed) 0)
				 (char=? (string-ref trimmed (sub1 (string-length trimmed))) #\\))))

;; Strip the trailing backslash from a continuation line
(define (strip-continuation str)
	(let ([trimmed (string-trim str #:left? #f)])
		(if (line-continues? trimmed)
				(substring trimmed 0 (sub1 (string-length trimmed)))
				str)))

;; Read a possibly multi-line logical line (handling \ continuation)
;; Returns: (values complete-line-string line-number lines-consumed)
(define (read-continued-line port start-line-num)
	(let ([raw (read-line port)])
		(if (eof-object? raw)
				(values #f start-line-num 0)
				(if (line-continues? raw)
						;; Line continues - read next and join
						(let ([base-indent (count-indent raw start-line-num)])
							(let-values ([(next-raw next-line-num lines-consumed)
														(read-continued-line port (add1 start-line-num))])
								(if (not next-raw)
										(error (format "Line ~a: Line continuation at end of file" start-line-num))
										(let ([next-indent (count-indent next-raw next-line-num)])
											(if (not (= base-indent next-indent))
													(error (format "Line ~a: Continuation line must have same indentation (expected ~a tabs, got ~a)"
																				 next-line-num base-indent next-indent))
													;; Join lines: strip \ from first, concatenate with space
													(let ([joined (string-append (strip-continuation raw) " " (string-trim next-raw #:right? #f))])
														(values joined start-line-num (add1 lines-consumed))))))))
						;; No continuation
						(values raw start-line-num 1)))))

(define (read-all-lines port)
	(let loop ([lines '()] [idx 1])
		(let-values ([(raw line-num lines-consumed) (read-continued-line port idx)])
			(if (not raw)
					(reverse lines)
					(loop (cons (line (count-indent raw line-num) (tokenize-line raw) line-num) lines)
								(+ idx lines-consumed))))))

;; --- The Reader Interface ---

(define (read in)
	(let ([lines (read-all-lines in)])
		;; Apply infix transform after parsing (when lists are formed)
		(map transform-infix (parse-block lines 0))))

(define (read-syntax src in)
	(let* ([lines (read-all-lines in)]
				 ;; Apply infix transform after parsing (when lists are formed)
				 [body (map transform-infix (parse-block lines 0))])
		;; Wrap the parsed body in a module definition
		;; Include tab-racket bindings (HAMT, etc.)
		(datum->syntax #f
									 `(module anonymous racket
											(require tab-racket/main)
											,@body))))
