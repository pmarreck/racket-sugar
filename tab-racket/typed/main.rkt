#lang racket
(require (only-in racket [read racket-read])
         (prefix-in hamt: "../../hamt/main.rkt")
         (prefix-in pv: "../../pvector/main.rkt"))

(provide read read-syntax
         ;; Re-export HAMT functions for typed code
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
         ;; Re-export PVector functions for typed code
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
                     [pv:pvector-fold pvector-fold]))

;; Typed variant - same parser, but wraps in typed/racket module

;; --- Clojure-style Literal Support ---
;; [...]  -> persistent vector (PVector)
;; ![...] -> mutable vector
;; {...}  -> persistent hash map (HAMT)
;; !{...} -> mutable hash map

(define (read-delimited-list close-char port readtable)
  (let loop ([items '()])
    (skip-whitespace-and-comments port)
    (let ([ch (peek-char port)])
      (cond
        [(eof-object? ch)
         (error (format "Unexpected EOF, expected '~a'" close-char))]
        [(char=? ch close-char)
         (read-char port)
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
      [(char=? ch #\;)
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

(define (maybe-quote v)
  (cond
    [(or (number? v) (string? v) (boolean? v) (char? v)) v]
    [(and (pair? v) (eq? (car v) 'quote)) v]
    ;; Persistent structures are values, don't quote
    [(or (hamt:hamt? v) (pv:pvector? v)) v]
    [(or (symbol? v) (pair? v) (vector? v) (hash? v)) `(quote ,v)]
    [else v]))

(define (read-bang ch port src line col pos)
  (let ([next (peek-char port)])
    (cond
      [(char=? next #\[)
       (read-char port)
       (let ([items (read-delimited-list #\] port clojure-readtable)])
         `(vector ,@(map maybe-quote items)))]
      [(char=? next #\{)
       (read-char port)
       (let ([items (read-delimited-list #\} port clojure-readtable)])
         (unless (even? (length items))
           (error "Hash literal requires even number of elements (key-value pairs)"))
         (let ([pairs (let loop ([items items] [acc '()])
                        (if (null? items)
                            (reverse acc)
                            (let ([k (car items)]
                                  [v (cadr items)])
                              (loop (cddr items)
                                    (cons `(cons ,(maybe-quote k) ,(maybe-quote v)) acc)))))])
           `(make-hasheq (list ,@pairs))))]
      [else
       (let ([sym-str (string-append "!" (symbol->string (racket-read port)))])
         (string->symbol sym-str))])))

(define (read-with-table port readtable)
  (parameterize ([current-readtable readtable])
    (racket-read port)))

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

;; Helper: Check if a symbol is a keyword (starts with :)
(define (keyword-symbol? v)
  (and (symbol? v)
       (let ([s (symbol->string v)])
         (and (> (string-length s) 0)
              (char=? (string-ref s 0) #\:)))))

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

(define (read-all-lines port)
  (let loop ([lines '()] [idx 1])
    (let ([raw (read-line port)])
      (if (eof-object? raw)
          (reverse lines)
          (loop (cons (line (count-indent raw idx) (tokenize-line raw) idx) lines)
                (add1 idx))))))

(define (read in)
  (let ([lines (read-all-lines in)])
    (parse-block lines 0)))

(define (read-syntax src in)
  (let* ([lines (read-all-lines in)]
         [body (parse-block lines 0)])
    ;; Wrap in typed/racket module with require/typed for persistent structures
    (datum->syntax #f
                   `(module anonymous typed/racket
                      (require/typed tab-racket/main
                        ;; HAMT types
                        [empty-hamt (-> Any)]
                        [hamt (-> Any * Any)]
                        [hamt? (-> Any Boolean)]
                        [hamt-empty? (-> Any Boolean)]
                        [hamt-contains? (-> Any Any Boolean)]
                        [hamt-ref (->* (Any Any) (Any) Any)]
                        [hamt-set (-> Any Any Any Any)]
                        [hamt-remove (-> Any Any Any)]
                        [hamt-count (-> Any Integer)]
                        [hamt->list (-> Any (Listof (Pairof Any Any)))]
                        [list->hamt (-> (Listof (Pairof Any Any)) Any)]
                        [hamt-keys (-> Any (Listof Any))]
                        [hamt-values (-> Any (Listof Any))]
                        ;; PVector types
                        [empty-pvector (-> Any)]
                        [pvector (-> Any * Any)]
                        [pvector? (-> Any Boolean)]
                        [pvector-empty? (-> Any Boolean)]
                        [pvector-ref (->* (Any Integer) (Any) Any)]
                        [pvector-set (-> Any Integer Any Any)]
                        [pvector-push (-> Any Any Any)]
                        [pvector-pop (-> Any Any)]
                        [pvector-length (-> Any Integer)]
                        [pvector->list (-> Any (Listof Any))]
                        [pvector->vector (-> Any (Vectorof Any))]
                        [list->pvector (-> (Listof Any) Any)]
                        [vector->pvector (-> (Vectorof Any) Any)])
                      ,@body))))
