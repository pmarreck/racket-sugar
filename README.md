# tab-racket

A Racket language variant that uses significant **tab-based indentation** instead of parentheses, with **Clojure-style persistent data structures**.

## Overview

`tab-racket` lets you write Racket code using indentation to denote structure, similar to Python or Haskell. Instead of wrapping expressions in parentheses, you indent child expressions under their parent.

### Key Features

- **Tab-based significant indentation** - Structure code without parentheses
- **Infix operators** - `(a ~+ b)` for readable binary operations
- **Persistent vectors** - `[]` creates immutable, structurally-shared vectors with O(log32 n) operations
- **Persistent hash maps** - `{}` creates HAMTs (Hash Array Mapped Tries) with O(log64 n) operations
- **Self-evaluating keywords** - `:foo` symbols auto-evaluate like Clojure/Ruby/Elixir atoms
- **Typed Racket support** - `#lang tab-racket/typed` for full type annotations
- **File extension** - Use `.trk` ("tabbed racket") for tab-racket source files

```
#lang tab-racket

define (fib n)
	cond
		(= n 0) 0
		(= n 1) 1
		else
			+
				fib (- n 1)
				fib (- n 2)

displayln
	fib 10
```

This is equivalent to:

```racket
#lang racket

(define (fib n)
  (cond
    [(= n 0) 0]
    [(= n 1) 1]
    [else
      (+
        (fib (- n 1))
        (fib (- n 2)))]))

(displayln
  (fib 10))
```

## Installation

### Using raco

```bash
cd tab-racket
raco pkg install
```

### Using Nix

This project uses Nix flakes for reproducible development:

```bash
nix develop
```

## Usage

Create a file with the `#lang tab-racket` directive:

```
#lang tab-racket
displayln "Hello, tabs!"
```

Run it with Racket:

```bash
racket hello.trk
```

## Syntax Rules

### Indentation

- **Tabs only** - Spaces for indentation are rejected with an error
- **Nesting** - Each tab level increases nesting depth
- **Siblings** - Lines at the same indentation level are siblings
- **Children** - Lines indented one level deeper become children of the preceding line

### How Indentation Maps to S-expressions

| Tab-indented code | S-expression |
|-------------------|--------------|
| `foo` | `foo` |
| `+ 1 2` | `(+ 1 2)` |
| `define x 1` | `(define x 1)` |
| `define (f x)`<br>&nbsp;&nbsp;&nbsp;&nbsp;`+ x 1` | `(define (f x) (+ x 1))` |

### Multiple Tokens on One Line

When multiple tokens appear on the same line, they form a list:

```
+ 1 2        ; becomes (+ 1 2)
define x 1   ; becomes (define x 1)
```

### Nested Structures

Indented children are appended to their parent's token list:

```
define (add a b)    ; parent line has tokens: define, (add a b)
	+ a b           ; child line adds: (+ a b)
                    ; result: (define (add a b) (+ a b))
```

### Empty Lines

Empty lines and lines containing only whitespace are ignored.

### Clojure-style Persistent Data Structures

`tab-racket` supports Clojure-style syntax for **persistent** vectors and hash maps. These are immutable by default with efficient structural sharing:

| Syntax | Data Structure | Complexity |
|--------|----------------|------------|
| `[a b c]` | Persistent Vector (PVector) | O(log32 n) |
| `{k1 v1 k2 v2}` | Persistent Hash Map (HAMT) | O(log64 n) |
| `![a b c]` | Mutable Racket vector | O(1) |
| `!{k1 v1 k2 v2}` | Mutable Racket hash | O(1) amortized |

```
#lang tab-racket

; Persistent by default - updates return new structure, original unchanged
define scores {"alice" 95 "bob" 87}
define updated-scores (hamt-set scores "carol" 92)
; scores still has only alice and bob!

define nums [1 2 3]
define more-nums (pvector-push nums 4)
; nums is still [1 2 3]!

; Mutable when you need it
define mutable-vec ![1 2 3]
vector-set! mutable-vec 0 99
```

Note: Since `[]` now creates persistent vectors, use parentheses `()` for list operations like let bindings.

### Self-Evaluating Keywords

Keywords (symbols starting with `:`) are automatically self-evaluating, like atoms in Clojure, Ruby, or Elixir:

```
#lang tab-racket

;; Keywords evaluate to themselves - no quoting needed!
define person {:name "Alice" :age 30}
displayln (hamt-ref person :name)  ; prints "Alice"

;; Works in function calls and comparisons
define (greet who)
    if (equal? who :world)
        displayln "Hello, World!"
        displayln (format "Hello, ~a!" who)

greet :world
```

Note: Bare `:` is reserved for type annotations in `tab-racket/typed` and is not auto-quoted.

### Infix Operators (`~func`)

For binary operations, you can use infix syntax with the `~` prefix. `(a ~func b)` transforms to `(func a b)`:

```
#lang tab-racket

;; Arithmetic - more readable than prefix
displayln (1 ~+ 2)              ; → (+ 1 2) = 3
displayln (10 ~- 3)             ; → (- 10 3) = 7
displayln (4 ~* 5)              ; → (* 4 5) = 20
displayln (10 ~/ 2)             ; → (/ 10 2) = 5

;; Comparisons
displayln (5 ~< 10)             ; → (< 5 10) = #t
displayln (5 ~> 10)             ; → (> 5 10) = #f
displayln (5 ~= 5)              ; → (= 5 5) = #t

;; Any binary function works
displayln (17 ~modulo 5)        ; → (modulo 17 5) = 2
displayln ("hello" ~string-append " world")  ; → "hello world"

;; Nested expressions - use parens for precedence
displayln (1 ~+ (2 ~* 3))       ; → (+ 1 (* 2 3)) = 7
displayln ((10 ~- 2) ~* 3)      ; → (* (- 10 2) 3) = 24

;; Works in function bodies
define (add x y)
	x ~+ y

define (quadratic a b c x)
	(a ~* (x ~* x)) ~+ ((b ~* x) ~+ c)
```

Works with `#lang tab-racket/typed` too:

```
#lang tab-racket/typed

: add (Integer Integer ~-> Integer)
define (add x y)
	x ~+ y

: quadratic (Integer Integer Integer Integer ~-> Integer)
define (quadratic a b c x)
	(a ~* (x ~* x)) ~+ ((b ~* x) ~+ c)

displayln (add 3 4)           ; 7
displayln (quadratic 1 2 1 3) ; 16
```

**Type annotation syntax**: In type annotations, `~->` as the second-to-last element moves to the front as `->`. This reads naturally as "args ~-> return":

```
(Integer ~-> Integer)                    ; → (-> Integer Integer)
(Integer Integer ~-> Integer)            ; → (-> Integer Integer Integer)
(String (Listof Integer) ~-> Integer)    ; → (-> String (Listof Integer) Integer)
((Integer ~-> Integer) Integer ~-> Integer)  ; Higher-order function
```

Note: The `~` prefix is only special when followed by an identifier. The tilde character in format strings (`~a`, `~s`, etc.) is unaffected.

### Persistent Vector API

```racket
; Construction
[1 2 3]                    ; literal syntax
(pvector 1 2 3)            ; function call
(list->pvector '(1 2 3))   ; from list

; Operations (all O(log32 n))
(pvector-ref v 0)          ; get element at index
(pvector-set v 0 99)       ; return new vector with updated element
(pvector-push v 4)         ; return new vector with element appended
(pvector-pop v)            ; return new vector without last element
(pvector-length v)         ; get length

; Conversion
(pvector->list v)          ; convert to list
(pvector->vector v)        ; convert to Racket vector
```

### Persistent Hash Map API

```racket
; Construction
{"name" "Alice" "age" 30}  ; literal syntax
(hamt "name" "Alice")      ; function call
(list->hamt '(("a" . 1)))  ; from alist

; Operations (all O(log64 n))
(hamt-ref h "name")        ; get value for key
(hamt-ref h "x" 'default)  ; with default value
(hamt-set h "city" "NYC")  ; return new hamt with key-value
(hamt-remove h "age")      ; return new hamt without key
(hamt-count h)             ; get number of entries
(hamt-contains? h "name")  ; check if key exists

; Conversion
(hamt->list h)             ; convert to alist
(hamt-keys h)              ; get all keys
(hamt-values h)            ; get all values
```

## Examples

### Hello World

```
#lang tab-racket
displayln "Hello, tabs!"
```

### Fibonacci

```
#lang tab-racket

define (fib n)
	cond
		(= n 0) 0
		(= n 1) 1
		else
			+
				fib (- n 1)
				fib (- n 2)

displayln
	fib 10
```

### Conditionals

```
#lang tab-racket

define (abs x)
	if (< x 0)
		- x
		x

displayln
	abs -5
```

### Let Bindings

```
#lang tab-racket

let
	((x 10) (y 20))
	+ x y
```

Note: Use parentheses `()` for let bindings since `[]` creates vectors in tab-racket.

### Word Frequency Counter (Persistent Data Structures)

This example demonstrates persistent vectors and HAMTs:

```
#lang tab-racket

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

;; Demo persistence
define v1 [1 2 3]
define v2 (pvector-push v1 4)
displayln (format "v1 = ~a" (pvector->list v1))
displayln (format "v2 = ~a" (pvector->list v2))
displayln "v1 is UNCHANGED! That's persistence."

;; Run word count
define words (split-words sample-text)
define freq (count-words words)
displayln (format "Word frequencies: ~a" (hamt->list freq))
```

### Cache Algorithms (Typed)

The examples include implementations of production cache algorithms using typed persistent data structures:

**ARC (Adaptive Replacement Cache)** - `examples/arc-cache.trk`
- Self-tuning algorithm used in ZFS
- Balances recency (LRU) and frequency (LFU) using ghost lists
- Adapts to workload patterns automatically

**S3-FIFO (Simple, Scalable, FIFO-based)** - `examples/s3fifo-cache.trk`
- From SOSP 2023: "FIFO Queues are All You Need for Cache Eviction"
- Uses two FIFO queues (S=10%, M=90%) to filter one-hit-wonders
- Excellent scan resistance for sequential access patterns

**SIEVE (1-bit)** - `examples/sieve-cache.trk`
- From NSDI 2024: "SIEVE is Simpler than LRU"
- Single FIFO queue with a scanning "hand" pointer
- Each entry has a 1-bit visited flag; unvisited items evicted first
- Key insight: retained items stay in place (unlike CLOCK which reinserts)

**SIEVE-2 (2-bit)** - `examples/sieve2-cache.trk`
- Variant using a 2-bit counter (0-3) instead of a boolean
- On hit: increment counter (saturates at 3)
- On hand pass: decrement counter; evict when 0
- Gives frequently-accessed items more "staying power"

#### Benchmark Results

Run the comprehensive benchmark (default: 50,000 ops per test):
```bash
racket tests/cache-bench.trk

# Configure via environment variables:
BENCH_OPS=100000 racket tests/cache-bench.trk           # More ops for statistical confidence
BENCH_SEED=42 racket tests/cache-bench.trk              # Reproducible random seed
BENCH_OPS=10000 BENCH_SEED=42 racket tests/cache-bench.trk  # Both
```

| Test Pattern | LRU | ARC | S3-FIFO | SIEVE | SIEVE-2 |
|--------------|-----|-----|---------|-------|---------|
| Temporal Locality | 85.1% | **85.1%** | 84.8% | 81.6% | 78.3% |
| Hot/Cold (80/20) | 83.9% | 84.0% | **84.0%** | 84.0% | 84.0% |
| Scan Resistance | 25.3% | 29.5% | 29.8% | **30.0%** | 29.9% |
| Zipf Distribution | 31.7% | 34.5% | 37.7% | 39.8% | **41.8%** |
| Loop/Burst | 56.0% | 66.2% | 69.5% | 69.9% | **70.0%** |
| Working Set Shift | 75.4% | **75.4%** | 71.2% | 63.4% | 58.1% |
| Mixed Recency/Freq | 50.0% | **53.0%** | 53.0% | 53.0% | 53.0% |

**Takeaways:**
- **SIEVE/SIEVE-2** excel at Zipf (power-law) patterns - common in real workloads
- **ARC** wins on mixed workloads that alternate between recency and frequency patterns
- **S3-FIFO** strong on hot/cold and loop patterns thanks to ghost queue filtering one-hit-wonders
- **LRU** strong baseline for pure temporal locality patterns
- Results vary with random seed - run multiple times for statistical confidence
- Real-world traces: SIEVE ~6% better than LRU ([NSDI'24](https://www.usenix.org/conference/nsdi24/presentation/zhang-yazhuo)), S3-FIFO lowest miss ratio on 10/14 datasets ([SOSP'23](https://dl.acm.org/doi/10.1145/3600006.3613147))
- ARC algorithm per [Megiddo & Modha, FAST 2003](https://www.usenix.org/conference/fast-03/arc-self-tuning-low-overhead-replacement-cache)

## Running Tests

```bash
raco test tests/tab-racket-test.rkt tests/examples-test.rkt
```

Or run all tests in the tests directory:

```bash
raco test tests/
```

## Project Structure

```
.
├── tab-racket/
│   ├── main.rkt          # Core reader and parser (untyped)
│   ├── typed/
│   │   └── main.rkt      # Typed variant reader
│   ├── lang/
│   │   └── reader.rkt    # #lang tab-racket support
│   └── info.rkt          # Package metadata
├── hamt/
│   ├── main.rkt          # HAMT implementation (untyped)
│   ├── typed-main.rkt    # HAMT with full type annotations
│   └── optimized-main.rkt # HAMT with unsafe ops for speed
├── pvector/
│   ├── main.rkt          # PVector implementation (untyped)
│   └── typed-main.rkt    # PVector with full type annotations
├── examples/
│   ├── hello.trk           # Hello world example
│   ├── fibonacci.trk       # Fibonacci example
│   ├── fibonacci-typed.trk # Typed Fibonacci
│   ├── word-freq.trk       # Word frequency counter
│   ├── counter-typed.trk   # Word counter with types
│   ├── arc-cache.trk       # ARC cache algorithm (typed)
│   ├── s3fifo-cache.trk    # S3-FIFO cache algorithm (typed)
│   ├── sieve-cache.trk     # SIEVE 1-bit cache (typed)
│   └── sieve2-cache.trk    # SIEVE 2-bit cache (typed)
├── tests/
│   ├── tab-racket-test.rkt  # Parser test suite
│   ├── hamt-test.rkt        # HAMT test suite
│   ├── pvector-test.rkt     # PVector test suite
│   ├── hash-api-test.trk    # HAMT API demo (tab-racket)
│   ├── pvector-api-test.trk # PVector API demo (tab-racket)
│   ├── examples-test.rkt    # Integration tests for examples
│   └── cache-bench.trk      # Comprehensive cache algorithm benchmark
├── flake.nix             # Nix flake configuration
├── docs/
│   └── PROJECT_PLAN.md   # Project planning document
└── README.md
```

## Typed Racket Support

### Using `#lang tab-racket/typed`

For type-annotated tab-racket code, use the typed variant:

```
#lang tab-racket/typed

;; Type annotations use : prefix (like Typed Racket)
: fib (-> Integer Integer)
define (fib n)
	cond
		(= n 0) 0
		(= n 1) 1
		else
			+ (fib (- n 1)) (fib (- n 2))

displayln (fib 10)
```

### Using Typed Data Structures from Typed Racket

Both persistent data structures have fully typed versions that can be used directly from Typed Racket code without contract overhead:

```racket
#lang typed/racket

(require "hamt/typed-main.rkt"
         "pvector/typed-main.rkt")

;; Types are: HAMT, PVector
(: my-map HAMT)
(define my-map (hamt "key" 42))

(: my-vec PVector)
(define my-vec (pvector 1 2 3))
```

The typed versions use `unsafe-fxpopcount` and other unsafe operations internally for performance while maintaining type safety at the API boundary.

## Performance

The persistent data structures are designed for both correctness and performance:

| Operation | PVector | HAMT |
|-----------|---------|------|
| Lookup | O(log32 n) ~1.1μs | O(log64 n) ~1.2μs |
| Insert/Update | O(log32 n) ~2.5μs | O(log64 n) ~3μs |
| Structural sharing | Yes | Yes |

At 100K elements, persistent operations are ~1.5-2x slower than mutable equivalents but provide immutability guarantees. The optimized HAMT version uses unsafe operations in hot paths for ~30% speedup.

## Limitations

- **Tabs only** - Spaces for indentation cause an error
- **No continuation lines** - Line continuation with `\` is not yet implemented
- Full Racket semantics apply after parsing
- Persistent vectors use 32-way branching (max ~1 billion elements efficiently)
- Use `.trk` extension for tab-racket files to distinguish from standard `.rkt` files

## License

MIT
