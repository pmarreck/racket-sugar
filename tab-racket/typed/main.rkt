#lang racket
(require (only-in racket [read racket-read]))
(provide read read-syntax)

;; Typed variant - same parser, but wraps in typed/racket module

;; --- Clojure-style Literal Support ---
;; [...]  -> immutable vector
;; ![...] -> mutable vector
;; {...}  -> immutable hash map
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

(define (read-bracket ch port src line col pos)
  (vector->immutable-vector (list->vector (read-delimited-list #\] port clojure-readtable))))

(define (read-brace ch port src line col pos)
  (let ([items (read-delimited-list #\} port clojure-readtable)])
    (unless (even? (length items))
      (error "Hash literal requires even number of elements (key-value pairs)"))
    (apply hasheq items)))

(define (maybe-quote v)
  (cond
    [(or (number? v) (string? v) (boolean? v) (char? v)) v]
    [(and (pair? v) (eq? (car v) 'quote)) v]
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

(define (tokenize-line str)
  (let ([in (open-input-string str)])
    (let loop ([tokens '()])
      (let ([token (read-with-table in clojure-readtable)])
        (if (eof-object? token)
            (reverse tokens)
            (loop (cons token tokens)))))))

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
    ;; Wrap in typed/racket module instead of racket
    (datum->syntax #f
                   `(module anonymous typed/racket
                      ,@body))))
