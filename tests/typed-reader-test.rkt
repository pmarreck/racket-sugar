#lang racket

;; Tests for the racket-sugar/typed reader's ~-> arrow transform. The arrow must be
;; rewritten to -> in EVERY position (not just inside `: name type` annotations) so
;; that types written inline (e.g. in `ann`, `cast`, `inst`) work without falling back
;; to a literal `->`.

(require rackunit
         (prefix-in t: racket-sugar/typed/main))

(define (tparse str) (call-with-input-string str t:read))

;; --- arrow in `:` annotation position (already worked) ---
(check-equal? (tparse ": f (Integer Integer ~-> Boolean)")
              '((: f (-> Integer Integer Boolean))))

;; --- arrow in EXPRESSION position (inside ann) — the regression we are fixing ---
(check-equal? (tparse "ann g (Integer Integer ~-> Boolean)")
              '((ann g (-> Integer Integer Boolean))))

;; --- single-arg arrow still works everywhere ---
(check-equal? (tparse "ann h (Integer ~-> Boolean)")
              '((ann h (-> Integer Boolean))))

;; --- nested / higher-order arrow inside an expression ---
(check-equal? (tparse "ann k ((Integer ~-> Integer) Integer ~-> Integer)")
              '((ann k (-> (-> Integer Integer) Integer Integer))))

(module+ test)
