#lang racket/base

;; Unit tests for the pure core of the README doctest harness (tools/doctest.rkt).
;; Covers markdown fence parsing, racket-sugar block detection, `; =>` expectation
;; extraction, and expected-vs-actual comparison. The subprocess runner is thin
;; glue exercised by `./doctest README.md` itself, not here (keeps these pure/fast).

(require rackunit
         racket/string
         "../tools/doctest.rkt")

(define fixture
  (string-join
   (list "# Title"
         ""
         "Some prose."
         ""
         "```"
         "#lang racket-sugar"
         "displayln (1 ~+ 2)     ; => 3"
         "displayln 42           ; => 42"
         "```"
         ""
         "Equivalent racket:"
         ""
         "```racket"
         "#lang racket"
         "(displayln 3)"
         "```"
         ""
         "```bash"
         "raco test"
         "```"
         ""
         "```"
         "#lang racket-sugar/typed"
         "displayln \"hi\""
         "```")
   "\n"))

(define blocks (parse-fenced-blocks fixture))

;; --- fence parsing ---
(check-equal? (length blocks) 4 "should find all four fenced blocks")

;; --- racket-sugar detection (untyped AND typed, not plain racket/bash) ---
(define rs (filter racket-sugar-block? blocks))
(check-equal? (length rs) 2 "racket-sugar + racket-sugar/typed, not racket/bash")

;; --- expectation extraction (ordered) ---
(check-equal? (block-expectations (car rs)) '("3" "42"))
(check-equal? (block-expectations (cadr rs)) '() "typed block has no annotations")

;; --- skip directive (illustrative-only blocks opt out of execution) ---
(check-false (block-skip? (car rs)) "normal block is not skipped")
(define skippy
  (car (filter racket-sugar-block?
               (parse-fenced-blocks
                "```\n#lang racket-sugar\n; doctest: skip\nfoo undefined-thing\n```"))))
(check-true (block-skip? skippy) "block with `; doctest: skip` is skipped")
;; --- comparison core ---
(check-true (eq? #t (check-expectations '("3" "42") '("3" "42"))))
(check-pred string? (check-expectations '("3" "42") '("3" "99"))
            "mismatch returns a failure message")
(check-pred string? (check-expectations '("3" "42") '("3"))
            "wrong count returns a failure message")

(module+ test)
