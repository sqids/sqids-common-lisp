# cl-sqids Usage Guide

**English** · [中文](./USAGE.md)

> This is the hands-on guide for cl-sqids. For the API reference see [README.en.md](./README.en.md).

## Table of Contents

- [1. Setup](#1-setup)
- [2. 30-second quickstart](#2-30-second-quickstart)
- [3. Core concepts](#3-core-concepts)
- [4. Common scenarios](#4-common-scenarios)
- [5. Customization in depth](#5-customization-in-depth)
- [6. Error handling](#6-error-handling)
- [7. Cross-language interop](#7-cross-language-interop)
- [8. Performance and memory](#8-performance-and-memory)
- [9. Best practices](#9-best-practices)
- [10. FAQ / pitfalls](#10-faq--pitfalls)

---

## 1. Setup

### 1.1 Supported implementations

| Implementation | Minimum version |
|---|---|
| SBCL | 2.6.6 and newer |
| CCL (Clozure CL) | 1.13 and newer |

Dependencies: **only FiveAM (for tests)**. The core library has zero external deps.

### 1.2 Installation

**Quicklisp (recommended):**

```bash
cd ~/quicklisp/local-projects/
git clone https://github.com/TTalkPro/cl-sqids.git
```

```lisp
(ql:quickload :cl-sqids)
; => (:CL-SQIDS)
```

**Plain ASDF:**

```lisp
(require :asdf)
(pushnew #P"/path/to/cl-sqids/" asdf:*central-registry* :test #'equal)
(asdf:load-system :cl-sqids)
```

### 1.3 Package import

Every public symbol lives in the `#:cl-sqids` package. The full package prefix
is recommended (it makes code greppable):

```lisp
(defpackage #:my-app
  (:use #:common-lisp))
(in-package #:my-app)

(cl-sqids:make-sqids)
```

If the prefix is too verbose, use package-local nicknames (supported by both SBCL and CCL):

```lisp
(defpackage #:my-app
  (:use #:common-lisp)
  (:local-nicknames (#:sqids #:cl-sqids)))
(in-package #:my-app)

(sqids:make-sqids)        ; equivalent to cl-sqids:make-sqids
(sqids:encode '(1 2 3) *) ; both symbols work
```

---

## 2. 30-second quickstart

```lisp
(ql:quickload :cl-sqids)

(defparameter *s* (cl-sqids:make-sqids))

(cl-sqids:encode '(1 2 3) *s*)  ; => "86Rf07"
(cl-sqids:decode "86Rf07" *s*)  ; => (1 2 3)
```

That's it. `make-sqids` with no arguments uses defaults (62-character alphabet,
built-in 210-word blocklist).

---

## 3. Core concepts

### 3.1 What sqids is

sqids is a bidirectional mapping between a **list of non-negative integers**
and a **short string**:

| Input | Output |
|---|---|
| `(1 2 3)` | `"86Rf07"` |
| `(4572721)` | `"JExTR"` |
| `(0)` | `"bM"` |
| `()` | `""` |

It is **not** encryption, not a hash function, and not UUID. Its purpose is
to turn "an internal list of numbers" into "a shareable short ID".

### 3.2 Key properties

- **Deterministic** — same input always yields the same output (within one instance)
- **Reversible** — decoding recovers the original numbers
- **Profanity-filtered** — built-in blocklist skips "fuck", "shit", etc.
- **Configurable** — alphabet, minimum length, and blocklist all tweakable

### 3.3 Instances are immutable

```lisp
(defparameter *s* (cl-sqids:make-sqids))

(setf (cl-sqids:alphabet *s*) "abc")
;; => Error: ALPHABET is a :reader, there is no setf method
```

To change configuration, build a new instance:

```lisp
(defparameter *s2* (cl-sqids:make-sqids :alphabet "abc..."))
```

This is the [Google CL Style Guide](https://google.github.io/styleguide/lispguide.xml)
design direction — avoid the `:accessor` + manual setf-override anti-pattern.

### 3.4 The alphabet is shuffled once at construction

```lisp
(cl-sqids:alphabet (cl-sqids:make-sqids))
;; => "vU7Kbj2pJWcRw9XYgT5Nq8aP3dhLZiFkrVCStzAHMxIef0yoQ46EG1nDBuOsm"
;;    (a shuffled-looking string — same across installs)
```

The shuffle is **deterministic** (derived from character code points and indices,
no randomness). Reinstalling cl-sqids or moving to a different machine yields the
same `(alphabet s)`.

---

## 4. Common scenarios

### 4.1 Database primary key → shareable ID

Turn an auto-increment DB id (e.g., Postgres `BIGSERIAL`) into a public ID that
does not leak your business volume:

```lisp
(defparameter *id-sqids* (cl-sqids:make-sqids :min-length 10))

(defun public-id (db-id)
  "DB primary key → 10-char public ID."
  (cl-sqids:encode (list db-id) *id-sqids*))

(defun lookup-by-public-id (public-id)
  "Public ID → DB primary key."
  (let ((nums (cl-sqids:decode public-id *id-sqids*)))
    (when (and nums (= 1 (length nums)))
      (first nums))))

(public-id 1)                          ; => "UKgmr6HJOd"
(public-id 999999)                     ; => "wYQEaD9WZk"
(lookup-by-public-id "UKgmr6HJOd")     ; => 1
```

> **Note**: sqids is **not** cryptographically strong. Anyone can decode the
> original ID. If you want "unguessable" IDs, layer HMAC or AES on top.

### 4.2 Compound keys (multiple fields)

Pack `(user_id, post_id, reply_id)` into a single string:

```lisp
(defparameter *route-sqids* (cl-sqids:make-sqids))

(defun make-route (user post reply)
  (cl-sqids:encode (list user post reply) *route-sqids*))

(defun parse-route (route)
  (let ((nums (cl-sqids:decode route *route-sqids*)))
    (if (= 3 (length nums))
        (values-list nums)
        (error "Invalid route"))))

(make-route 42 1234 5678)          ; => "..."
(multiple-value-bind (u p r) (parse-route "...")
  (list u p r))                    ; => (42 1234 5678)
```

URL style: `https://example.com/p/<route>`.

### 4.3 Invite codes / share codes (with min-length)

```lisp
(defparameter *invite-sqids*
  (cl-sqids:make-sqids :min-length 8))

(cl-sqids:encode (list 12345) *invite-sqids*) ; => at least 8 characters
```

### 4.4 Custom alphabet (no ambiguous chars)

Avoid visually similar chars like `0/O`, `1/l/I` for situations where the ID
might be dictated or hand-copied:

```lisp
(defparameter *readable-sqids*
  (cl-sqids:make-sqids
    :alphabet "abcdefghijkmnpqrstuvwxyz23456789")) ; drop 0/o/1/l/i
```

### 4.5 Disable the blocklist (performance)

If your IDs are never seen by humans (machine-to-machine tokens, internal IDs),
turn off the blocklist to save one reshuffle:

```lisp
(defparameter *fast-sqids*
  (cl-sqids:make-sqids :blocklist '()))
```

### 4.6 Multiple instances coexisting

Different business lines can have different configs without interfering:

```lisp
(defparameter *user-ids* (cl-sqids:make-sqids :min-length 8))
(defparameter *order-ids* (cl-sqids:make-sqids :min-length 12 :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
(defparameter *share-codes* (cl-sqids:make-sqids :min-length 6 :blocklist '()))
```

---

## 5. Customization in depth

### 5.1 Alphabet (`:alphabet`)

Constraints:

| Rule | Notes |
|---|---|
| Length ≥ 3 | Otherwise `alphabet-too-short-error` |
| Unique characters | Otherwise `alphabet-duplicates-error` |
| ASCII only (code ≤ 127) | Otherwise `alphabet-multibyte-error` |

```lisp
(cl-sqids:make-sqids :alphabet "0123456789abcdef")     ; ✓ hex
(cl-sqids:make-sqids :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ") ; ✓ 26 uppercase
(cl-sqids:make-sqids :alphabet "abc")                  ; ✓ minimum 3 chars
(cl-sqids:make-sqids :alphabet "ab")                   ; ✗ too short
(cl-sqids:make-sqids :alphabet "aabbc")                ; ✗ duplicates
(cl-sqids:make-sqids :alphabet "éabc")                 ; ✗ non-ASCII
```

**Shorter alphabets → longer output.** With the default 62-char alphabet
`(1 2 3)` is 6 chars; with `"abc"` it is much longer.

### 5.2 Minimum length (`:min-length`)

| Constraint | Notes |
|---|---|
| Type | Integer |
| Range | `[0, 255]` inclusive |
| Default | `0` (no padding) |

```lisp
(let ((s (cl-sqids:make-sqids)))
  (cl-sqids:encode '(1 2 3) s))            ; => "86Rf07" (6 chars)

(let ((s (cl-sqids:make-sqids :min-length 10)))
  (cl-sqids:encode '(1 2 3) s))            ; => "86Rf07xd4z" (10 chars)

(let ((s (cl-sqids:make-sqids :min-length 62)))
  (cl-sqids:encode '(1 2 3) s))            ; => "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTM"
```

Padding algorithm: after the natural encoding, a separator is appended; then
the alphabet is repeatedly shuffled and chunks are taken. The decoder
recognizes two adjacent separators as the padding boundary and stops.

### 5.3 Blocklist (`:blocklist`)

#### Three-tier matching (matches official spec exactly)

Let ID length be `n`, blocklist word length be `m`:

| Condition | Match style |
|---|---|
| `n ≤ 3` **or** `m = 3` | Exact equality (`id == word`) |
| `n > 3` **and** word has digit | Prefix or suffix match |
| `n > 3` **and** word has no digit | Substring match |

Matching is **case-insensitive**. Construction time **pre-filters** the list:

- Words with `m < 3` are dropped
- Words containing characters not in the alphabet are dropped

```lisp
(cl-sqids:make-sqids :blocklist '("foo" "bar" "DEAD"))    ; ✓
(cl-sqids:make-sqids :blocklist '("a"))                   ; "a" too short, dropped
(cl-sqids:make-sqids :blocklist '("xyz" "ABC")
                     :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
; "xyz" contains chars outside the alphabet, dropped; only "ABC" kept
```

#### Disable the blocklist

```lisp
(cl-sqids:make-sqids :blocklist '())   ; empty list
;; or
(cl-sqids:make-sqids :blocklist nil)
```

#### Verify that an ID was blocked

The blocklist is split into 3 internal lists at construction. The clean way to
verify behavior is via round-trip:

```lisp
(let ((s (cl-sqids:make-sqids)))
  (cl-sqids:encode '(4572721) s))  ; => "JExTR" (not "aho1e", which is blocked)

(let ((s (cl-sqids:make-sqids :blocklist '())))
  (cl-sqids:encode '(4572721) s))  ; => "aho1e"
```

---

## 6. Error handling

### 6.1 Condition hierarchy

```
sqids-error                            ; base of every cl-sqids error
├── alphabet-error                     ; base of alphabet errors
│   ├── alphabet-too-short-error       ; alphabet < 3 chars
│   ├── alphabet-duplicates-error      ; alphabet has duplicate chars
│   └── alphabet-multibyte-error       ; alphabet has non-ASCII char
├── min-length-out-of-range-error      ; min-length not in [0, 255]
├── max-regenerate-attempts-error      ; blocklist unsatisfiable
└── unsupported-numbers-type-error     ; bad encode input
```

### 6.2 Recommended: catch the whole family

```lisp
(handler-case
    (cl-sqids:make-sqids :alphabet (user-input))
  (cl-sqids:sqids-error (c)
    ;; one clause catches every cl-sqids error
    (log:error "sqids config error: ~A" c)
    (give-up)))
```

### 6.3 Fine-grained handling

```lisp
(handler-case
    (let ((s (cl-sqids:make-sqids :alphabet raw)))
      (cl-sqids:encode numbers s))
  (cl-sqids:alphabet-too-short-error (c)
    (format nil "Alphabet needs at least 3 characters: ~A" (cl-sqids:alphabet c)))
  (cl-sqids:alphabet-duplicates-error (c)
    (format nil "Alphabet cannot have duplicates: ~A" (cl-sqids:alphabet c)))
  (cl-sqids:alphabet-multibyte-error (c)
    (format nil "Alphabet cannot have non-ASCII chars: ~A" (cl-sqids:condition-char c)))
  (cl-sqids:unsupported-numbers-type-error (c)
    (format nil "Encode input must be non-negative int or list: ~A" (cl-sqids:condition-value c)))
  (cl-sqids:max-regenerate-attempts-error ()
    "Blocklist too strict, no compliant ID"))
```

### 6.4 Key details

- Sub-conditions of `alphabet-error` expose the offending alphabet via `(alphabet c)`
- `alphabet-multibyte-error` also exposes the specific bad char via `(condition-char c)`
- `unsupported-numbers-type-error` / `min-length-out-of-range-error` expose the value via `(condition-value c)`
- Every condition has a custom `:report`, so `(princ c)` gives a human-readable message:

```lisp
(let ((c (make-condition 'cl-sqids:alphabet-too-short-error :alphabet "ab")))
  (princ c))
;; => "Alphabet length must be at least 3 (got 2 characters)."
```

---

## 7. Cross-language interop

cl-sqids is **byte-compatible** with [sqids-python](https://github.com/sqids/sqids-python),
[sqids-js](https://github.com/sqids/sqids-js), [sqids-go](https://github.com/sqids/sqids-go),
and every other official port.

### 7.1 Share IDs across languages

```python
# Python side
from sqids import Sqids
s = Sqids()
id = s.encode([1, 2, 3])  # => "86Rf07"
```

```lisp
;; Common Lisp side
(cl-sqids:decode "86Rf07" (cl-sqids:make-sqids)) ; => (1 2 3)
```

### 7.2 Share configuration (key insight)

Both sides must use **the same starting alphabet** (defaults match defaults).
Because the alphabet is shuffled at construction time and the shuffle is
deterministic, identical starting alphabets yield identical shuffled alphabets.

```python
# Python
s = Sqids(min_length=10)
s.encode([1, 2, 3])  # => "86Rf07xd4z"
```

```lisp
;; CL
(cl-sqids:encode '(1 2 3) (cl-sqids:make-sqids :min-length 10))
;; => "86Rf07xd4z"
```

### 7.3 Blocklist compatibility

As long as both sides use the same `blocklist` (order does not matter),
generated IDs match:

```python
s = Sqids(blocklist=["foo", "bar"])
```

```lisp
(cl-sqids:make-sqids :blocklist '("foo" "bar"))
```

### 7.4 Note: default min-length

- **Official default `min_length = 0`** (matches sqids-python / sqids-js)
- cl-sqids also uses 0 (an earlier version used 6; corrected)

To restore the old behavior: `(make-sqids :min-length 6)`.

---

## 8. Performance and memory

### 8.1 Typical timings (SBCL 2.6.6, Linux x64)

Order-of-magnitude estimates (your numbers will vary with hardware):

| Operation | Per-call time |
|---|---|
| `(make-sqids)` with blocklist filtering | ~1 ms (one-time, at startup) |
| `(encode '(1 2 3) s)` | ~20 µs |
| `(decode "86Rf07" s)` | ~15 µs |
| `(encode '(1 2 3) s)` with blocklist off | ~5 µs |

### 8.2 Speed tips

1. **Reuse instances**. `make-sqids` is not cheap (it shuffles + filters the blocklist). Per-request instance construction is a common pitfall.

   ```lisp
   ;; ✗ don't
   (defun encode-id (n)
     (cl-sqids:encode (list n) (cl-sqids:make-sqids)))

   ;; ✓ do
   (defparameter *s* (cl-sqids:make-sqids))
   (defun encode-id (n)
     (cl-sqids:encode (list n) *s*))
   ```

2. **Turn off the blocklist** if you are certain IDs are never human-visible.

3. **Declare types**. On hot paths, declaring `*s*` as `sqids` helps SBCL:

   ```lisp
   (defun encode-id (n)
     (declare (type (integer 0) n)
              (optimize (speed 3) (safety 1)))
     (let ((s (load-time-value (cl-sqids:make-sqids))))
       (cl-sqids:encode (list n) s)))
   ```

### 8.3 Memory

- Each `sqids` instance is roughly 5 KB (62-char alphabet + three blocklist tiers ~200 words)
- `encode` / `decode` internally copy the alphabet; the instance itself is not mutated
- No global mutable state, no thread-local cache → thread-safe

---

## 9. Best practices

### 9.1 ✅ Do

- **Reuse instances** — one `defparameter` per business line
- **Type declarations** on hot paths — `(optimize (speed 3))`
- **Unified error handling** — catch `sqids-error` base class
- **Package-local nicknames** in long projects — shortens prefixes
- **Configuration from files** — alphabet/min-length/blocklist should be configurable, not hardcoded

### 9.2 ❌ Don't

- **Don't drop the original integers when storing the ID**. sqids is bidirectional but decoding can fail (user tampering). Always persist the integers in the database; use sqids for presentation only.
- **Don't use sqids as encryption**. Anyone can decode. Add HMAC/AES if confidentiality matters.
- **Don't assume the blocklist catches everything**. It's a baseline filter, not a guarantee.
- **Don't depend on internal state across threads**. The instance is immutable, but if you keep external state, use locks.
- **Don't mix instances**. Encoding with A and decoding with B will fail.

---

## 10. FAQ / pitfalls

### Q1: Are `(encode 5 s)` and `(encode '(5) s)` equivalent?

Yes. The `encode` method for a single integer wraps it into a list:
```lisp
(cl-sqids:encode 5 s)      ; => "uw"
(cl-sqids:encode '(5) s)   ; => "uw"
```

### Q2: Why is `(encode '(0) s)` not an empty string?

The sqids spec requires `to-id` to use `do/while` semantics: even for 0, at
least one character is produced. So `(encode '(0) s)` is `"bM"` (one character
plus a separator).

### Q3: Why does `(decode "*" s)` return `nil`?

`*` is not in the default alphabet. The spec says: if an ID contains an
out-of-alphabet character, **return an empty list**, not an error.
This prevents historical / mistyped IDs from raising exceptions.

### Q4: How do I get different IDs for the same input?

You can't — sqids is deterministic. To get different IDs, change the input or
the instance.

### Q5: Can sqids produce IDs that cannot be decoded?

No. **Every sqid is decodable.** For undecodable IDs, use HMAC or similar.

### Q6: The constructor throws `alphabet-duplicates-error` but I see no duplicates?

You probably have **invisible characters** in the string (space, tab, zero-width
space U+200B). Use `(length alphabet)` for the char count and
`(coerce alphabet 'list)` to inspect each character.

### Q7: Is the instance safe to share across threads?

Yes. Instances are immutable; there is no mutable state. Concurrent encode/decode
is safe.

### Q8: Can I make IDs look "more random"?

sqids has no randomness. You can:
- Shrink the alphabet (IDs get longer and look more chaotic)
- Set `:min-length`
- Apply a character permutation after encoding (but ensure it's bidirectional)

### Q9: Is CCL slower than SBCL?

Usually yes — SBCL has more aggressive inlining for inner loops. On CCL with
performance concerns:
- Turn off the blocklist
- Reuse instances
- Declare types at compile time

### Q10: Will decoding a historical ID fail?

No, as long as the alphabet and instance remain the same. The spec requires
the decoder to **not re-validate against the blocklist** — IDs that were
generated before a blocklist update still decode fine.

---

## Feedback

Issues and PRs welcome: <https://github.com/TTalkPro/cl-sqids/issues>

For the current state of the project see [TASK.md](./TASK.md).
