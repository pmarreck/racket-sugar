#lang racket

;; Tests for `# ` (hash-space) line comments in racket-sugar. This ALIASES the comment
;; syntax (it does NOT replace `;`): both `;` and `# ` start a line comment. A `#` only
;; starts a comment when immediately followed by a space or tab — so reader syntax like
;; #t, #f, #(...), #:kw, and #\char is unaffected — and `#` inside a string is literal.

(require rackunit
         (prefix-in u: racket-sugar/main))

(define (p str) (call-with-input-string str u:read))

;; --- # + space starts a comment ---
(check-equal? (p "displayln 42  # this is a comment") '((displayln 42)))
(check-equal? (p "+ 1 2 # add them") '((+ 1 2)))

;; --- full-line # comment is ignored ---
(check-equal? (p "# just a comment\ndisplayln 7") '((displayln 7)))

;; --- ; STILL works (aliased, not replaced) ---
(check-equal? (p "displayln 42 ; old-style still fine") '((displayln 42)))
(check-equal? (p "displayln 42 ; mix # of both") '((displayln 42)))

;; --- # NOT followed by space is reader syntax, not a comment ---
(check-equal? (p "displayln #t") '((displayln #t)))
(check-equal? (p "displayln #(1 2 3)") '((displayln #(1 2 3))))
(check-equal? (p "f #:kw 1") '((f #:kw 1)))
(check-equal? (p "displayln #\\a") '((displayln #\a)))

;; --- # inside a string is literal, not a comment ---
(check-equal? (p "displayln \"a # b\"") '((displayln "a # b")))

(module+ test)
