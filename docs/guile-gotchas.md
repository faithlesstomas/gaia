# Guile Scheme Gotchas & Antipatterns

This cheatsheet lists common mistakes Language Models make when writing GNU Guile Scheme code for the GAIA REPL environment. If you encountered a `Syntax Error` or `Runtime Error`, check if your code violates these rules.

## 1. Parentheses `()` Mismatch (The #1 Error)
**Error:** `unexpected end of input while searching for: ~A ()`
**Cause:** You forgot to close a parenthesis, or closed too many.
**Fix:** Instead of completely rewriting the code, COUNT your parentheses. Deeply nested `let` structures inside `dolist` loops are prone to this. Use flatter architectures like `let loop` with accumulators.

## 2. Invalid Usage of `define` (Scope Rules)
**Error:** `definition in expression context, where definitions are not allowed`
**Cause:** You used `(define ...)` inside a loop (`while`, `dolist`), an `if`, or a `cond` block.
**Fix:** Scheme requires internal definitions to be at the *start* of the script or the *start* of a `let`/`lambda` body. To create temporary variables inside a block, use `let` or `let*`. To mutate existing variables, use `set!`.

**Incorrect:**
```scheme
(dolist (path paths)
  (define info (file-info path)) ;; WRONG
  (display info))
```

**Correct:**
```scheme
(dolist (path paths)
  (let ((info (file-info path))) ;; CORRECT
    (display info)))
```

## 3. The `format` Function
**Error:** `wrong-number-of-args` when calling `format`.
**Cause:** Expecting `(format "String ~a" val)` to work like C's `printf`. Guile requires a destination port as the first argument.
**Fix:** Pass `#f` to return a string, or `#t` to print to standard output.

**Incorrect:** `(format "Hello ~a\n" name)`
**Correct (returns string):** `(format #f "Hello ~a\n" name)`
**Correct (prints to stdout):** `(format #t "Hello ~a\n" name)`

## 4. Character Literals vs Made-up Syntax
**Error:** `Unknown # object: ~S (#/)`
**Cause:** Fabricating syntax like `#/.` to represent characters.
**Fix:** Guile character literals start with `#\`.
- Space: `#\space`
- Dot: `#\.`
- Slash: `#\/`
- Newline: `#\newline`

## 5. String Splitting
**Warning:** Guile's built-in `(string-split string char)` function accepts a CHARACTER, not a string as the delimiter.
**Incorrect:** `(string-split "hello world" " ")`
**Correct:** `(string-split "hello world" #\space)`
*Note: GAIA provides `(split-string str delim)` if you want to use a string delimiter.*
