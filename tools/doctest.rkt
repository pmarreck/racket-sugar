#lang racket/base

;; README doctest harness (Elixir-inspired). Extracts fenced code blocks from a
;; Markdown file, runs each `#lang racket-sugar` block through racket, and checks
;; results. Hybrid policy: unannotated blocks must run clean (exit 0); lines with a
;; trailing `; => VALUE` comment additionally assert that program's stdout, in order.
;;
;; The pure core (parsing/detection/extraction/comparison) is unit-tested in
;; tests/doctest-test.rkt; the subprocess runner is exercised by `./doctest` itself.

(require racket/string racket/list racket/port)

(provide (struct-out doc-block)
         parse-fenced-blocks
         racket-sugar-block?
         block-expectations
         block-skip?
         check-expectations
         run-file)

;; A fenced block: `lang` is the info string after the opening ``` (may be ""),
;; `body` is the raw block contents (newline-joined, no fences).
(struct doc-block (lang body) #:transparent)

;; parse-fenced-blocks : string -> (listof doc-block)
;; Split Markdown into ```-fenced blocks. A line whose trimmed text starts with
;; ``` toggles in/out of a block; the opening fence's trailing text is the lang.
(define (parse-fenced-blocks md)
  (let loop ([lines (string-split md "\n" #:trim? #f)]
             [in? #f] [lang ""] [acc '()] [blocks '()])
    (cond
      [(null? lines) (reverse blocks)]
      [else
       (define line (car lines))
       (define fence? (string-prefix? (string-trim line) "```"))
       (cond
         [(and fence? (not in?))
          ;; opening fence: capture lang = text after the backticks
          (define info (string-trim (substring (string-trim line) 3)))
          (loop (cdr lines) #t info '() blocks)]
         [(and fence? in?)
          ;; closing fence: emit the accumulated block
          (loop (cdr lines) #f ""
                '()
                (cons (doc-block lang (string-join (reverse acc) "\n")) blocks))]
         [in? (loop (cdr lines) #t lang (cons line acc) blocks)]
         [else (loop (cdr lines) #f lang acc blocks)])])))

;; first non-blank, trimmed line of a body (or "")
(define (first-content-line body)
  (let loop ([lines (string-split body "\n" #:trim? #f)])
    (cond [(null? lines) ""]
          [(string=? (string-trim (car lines)) "") (loop (cdr lines))]
          [else (string-trim (car lines))])))

;; racket-sugar-block? : doc-block -> boolean
;; True when the first content line is `#lang racket-sugar` or `#lang racket-sugar/...`.
(define (racket-sugar-block? b)
  (and (regexp-match? #rx"^#lang racket-sugar($|/| )"
                      (first-content-line (doc-block-body b)))
       #t))

;; block-expectations : doc-block -> (listof string)
;; Ordered expected-output values from trailing `; => VALUE` comments.
(define (block-expectations b)
  (for/list ([line (in-list (string-split (doc-block-body b) "\n" #:trim? #f))]
             #:when (regexp-match? #rx";[ ]*=>" line))
    (string-trim (cadr (regexp-match #rx";[ ]*=>[ ]*(.*)$" line)))))

;; block-skip? : doc-block -> boolean
;; True when the block opts out of execution via a `; doctest: skip` comment
;; (for illustrative examples that reference undefined placeholder identifiers).
(define (block-skip? b)
  (and (regexp-match? #rx";+[ ]*doctest:[ ]*skip" (doc-block-body b)) #t))
;; check-expectations : (listof string) (listof string) -> (or/c #t string)
;; #t when there is nothing to check (smoke) or expected equals actual; otherwise a
;; human-readable failure message. `actual` should be the trimmed stdout lines.
(define (check-expectations expected actual)
  (cond
    [(null? expected) #t]
    [(equal? expected actual) #t]
    [else (format "expected ~s but got ~s" expected actual)]))

;; ---------------------------------------------------------------------------
;; Subprocess runner (I/O glue)
;; ---------------------------------------------------------------------------

;; run-source : string -> (values exit-code stdout-string stderr-string)
;; Writes `src` to a temp .trk at the CURRENT directory (so relative `require`s in
;; the example resolve against the repo root) and runs racket on it.
(define (run-source src idx)
  (define tmp (string-append ".doctest-tmp-" (number->string idx) ".trk"))
  (call-with-output-file tmp #:exists 'replace
    (lambda (o) (write-string src o)))
  (dynamic-wind
   void
   (lambda ()
     (define racket-exe (find-executable-path "racket"))
     (define-values (sp out in err)
       (subprocess #f #f #f racket-exe tmp))
     (close-output-port in)
     (define o (port->string out))
     (define e (port->string err))
     (subprocess-wait sp)
     (close-input-port out)
     (close-input-port err)
     (values (subprocess-status sp) o e))
   (lambda () (when (file-exists? tmp) (delete-file tmp)))))

(define (stdout->lines s)
  (filter (lambda (l) (not (string=? l "")))
          (map string-trim (string-split s "\n" #:trim? #f))))

;; ANSI helpers (kept minimal)
(define (green s) (string-append "\e[32m" s "\e[0m"))
(define (red s)   (string-append "\e[31m" s "\e[0m"))
(define (dim s)   (string-append "\e[2m"  s "\e[0m"))

;; run-file : path-string -> exact-nonnegative-integer (failure count)
(define (run-file file)
  (define md (call-with-input-file file port->string))
  (define blocks (filter racket-sugar-block? (parse-fenced-blocks md)))
  (eprintf "Running ~a racket-sugar doctest block(s) from ~a\n"
           (length blocks) file)
  (for/fold ([failures 0]) ([b (in-list blocks)] [i (in-naturals 1)])
    (define snippet (first-content-line (doc-block-body b)))
    (cond
      [(block-skip? b)
       (eprintf "~a block ~a (~a)~a\n"
                (dim "SKIP") i snippet (dim " [doctest: skip]"))
       failures]
      [else
       (define expected (block-expectations b))
       (define-values (code out err) (run-source (doc-block-body b) i))
       (cond
         [(not (zero? code))
          (eprintf "~a block ~a (~a)\n~a\n"
                   (red "FAIL") i snippet (dim (string-trim err)))
          (add1 failures)]
         [else
          (define verdict (check-expectations expected (stdout->lines out)))
          (cond
            [(eq? verdict #t)
             (eprintf "~a block ~a (~a)~a\n"
                      (green "PASS") i snippet
                      (if (null? expected) (dim " [smoke]") ""))
             failures]
            [else
             (eprintf "~a block ~a (~a)\n  ~a\n" (red "FAIL") i snippet verdict)
             (add1 failures)])])])))

(module+ main
  (require racket/cmdline)
  (define file (command-line #:args ([f "README.md"]) f))
  (define failures (run-file file))
  (eprintf "\n~a doctest failure(s)\n" failures)
  (exit (min 255 failures)))
