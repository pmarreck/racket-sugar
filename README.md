# tab-racket

A Racket language variant that uses significant **tab-based indentation** instead of parentheses.

## Overview

`tab-racket` lets you write Racket code using indentation to denote structure, similar to Python or Haskell. Instead of wrapping expressions in parentheses, you indent child expressions under their parent.

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
racket hello.tab
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

### Clojure-style Literals

`tab-racket` supports Clojure-style syntax for vectors and hash maps:

| Syntax | Becomes | Mutability |
|--------|---------|------------|
| `[a b c]` | Immutable vector | `(vector-immutable a b c)` |
| `![a b c]` | Mutable vector | `(vector a b c)` |
| `{k1 v1 k2 v2}` | Immutable hash | `(hasheq k1 v1 k2 v2)` |
| `!{k1 v1 k2 v2}` | Mutable hash | `(make-hasheq ...)` |

```
#lang tab-racket

; Immutable by default (like Clojure)
define scores {:alice 95 :bob 87 :carol 92}
define names ["Alice" "Bob" "Carol"]

; Mutable when you need it
define mutable-vec ![1 2 3]
vector-set! mutable-vec 0 99

define mutable-hash !{:x 10}
hash-set! mutable-hash (quote :x) 999
```

Note: Since `[]` now creates vectors, use parentheses `()` for list operations like let bindings.

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

## Running Tests

```bash
./test.sh
```

Or directly:

```bash
raco test test
```

## Project Structure

```
.
├── tab-racket/
│   ├── main.rkt          # Core reader and parser
│   ├── lang/
│   │   └── reader.rkt    # #lang tab-racket support
│   └── info.rkt          # Package metadata
├── examples/
│   ├── hello.tab         # Hello world example
│   └── fibonacci.tab     # Fibonacci example
├── test/
│   └── tab-racket-test.rkt  # Test suite
├── test.sh               # Test runner script
├── flake.nix             # Nix flake configuration
└── README.md
```

## Limitations

- **Tabs only** - Spaces for indentation cause an error
- **No continuation lines** - Line continuation with `\` is not yet implemented
- Full Racket semantics apply after parsing

## License

MIT
