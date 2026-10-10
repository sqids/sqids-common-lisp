# cl-sqids

**English** · [中文](./README.md)

[![Common Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL%20%7C%20CCL-success.svg)](https://common-lisp.dev/)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-281%20checks%20%E2%9C%93-brightgreen.svg)](#tests)

> **cl-sqids** is a Common Lisp implementation of [sqids](https://sqids.org/) —
> encode lists of non-negative integers into short, unique, URL-safe, reversible IDs.

sqids ("squids") is the modern successor to hashids: feed it numbers, get back a
short string; decode the string to recover the numbers. The encoder also avoids
profanity via a built-in blocklist.

---

## Table of Contents

- [Highlights](#highlights)
- [Installation](#installation)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Customization](#customization)
- [Errors](#errors)
- [Tests](#tests)
- [Compatibility](#compatibility)
- [Project layout](#project-layout)
- [License](#license)

> 📖 **For a hands-on guide with real-world scenarios, best practices, and FAQ see [USAGE.en.md](./USAGE.en.md).**
> This README is the API reference; for usage patterns, performance notes, and
> cross-language interop, read USAGE.en.md.

---

## Highlights

- Full implementation of the [official sqids spec](https://github.com/sqids/sqids-spec) — output is byte-identical to sqids-python / sqids-js / sqids-go
- CLOS-based immutable `sqids` class
- Follows the [Google Common Lisp Style Guide](https://google.github.io/styleguide/lispguide.xml)
- Works on **SBCL** and **CCL** with no implementation-specific code
- **281 FiveAM checks** ported 1:1 from sqids-python's official test vectors
- A macro (`with-peeled-separator`) and shared helpers eliminate duplication
- Built-in default blocklist of ~210 profanity / leet-speak words

---

## Installation

### Option A: Quicklisp (recommended)

Clone into Quicklisp's `local-projects`:

```bash
cd ~/quicklisp/local-projects/
git clone https://github.com/TTalkPro/cl-sqids.git
```

```lisp
(ql:quickload :cl-sqids)
```

### Option B: Plain ASDF

```bash
git clone https://github.com/TTalkPro/cl-sqids.git ~/workspace/cl-sqids
```

```lisp
(require :asdf)
(pushnew #P"/path/to/cl-sqids/" asdf:*central-registry* :test #'equal)
(asdf:load-system :cl-sqids)
```

---

## Quick start

```lisp
(ql:quickload :cl-sqids)

(defparameter *s* (cl-sqids:make-sqids))

(cl-sqids:encode '(1 2 3) *s*)   ; => "86Rf07"
(cl-sqids:decode "86Rf07" *s*)   ; => (1 2 3)
```

---

## API reference

### `make-sqids` (&key alphabet min-length blocklist) → `sqids`

Construct an immutable `sqids` encoder/decoder.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `:alphabet` | `string` | `*default-alphabet*` | At least 3 unique ASCII characters |
| `:min-length` | `(integer 0 255)` | `+default-min-length+` (0) | Minimum output length |
| `:blocklist` | `list` | `*default-blocklist*` | Words to avoid (matched case-insensitively) |

The alphabet is shuffled **once** at construction time and cached, per spec.
Invalid arguments signal `alphabet-error` or `min-length-out-of-range-error`.

### `encode` (numbers sqids) → `string`

Encode `numbers` as a sqid string.

- `numbers` may be a single non-negative integer or a list thereof
- Empty list → empty string `""`
- If a candidate ID matches the blocklist, the encoder re-shuffles until clean
- After `(+ (length alphabet) 1)` failed attempts it signals `max-regenerate-attempts-error`

### `decode` (id sqids) → `list`

Decode sqid string `id` back to a list of non-negative integers.

- Empty string or any character outside the alphabet → returns `nil`
- Does NOT re-validate against the blocklist — old / previously-blocked IDs still decode

### Public readers (read-only)

| Function | Returns |
|---|---|
| `(alphabet s)` | The instance's shuffled alphabet (`simple-string`) |
| `(min-length s)` | Minimum length (`(integer 0 255)`) |
| `(blocklist-original s)` | The user-supplied blocklist (list) |

---

## Customization

### Custom alphabet

```lisp
(defparameter *hex-sqids*
  (cl-sqids:make-sqids :alphabet "0123456789abcdef"))

(cl-sqids:encode '(1 2 3) *hex-sqids*)
;; => "489158"
```

### Custom minimum length

```lisp
(defparameter *s* (cl-sqids:make-sqids :min-length 10))
(cl-sqids:encode '(1 2 3) *s*)
;; => "86Rf07xd4z"
```

### Disable the blocklist

```lisp
(defparameter *raw* (cl-sqids:make-sqids :blocklist '()))
(cl-sqids:encode '(4572721) *raw*)
;; => "aho1e"  (the default instance produces "JExTR" because "aho1e" is blocked)
```

---

## Errors

Every error is a subtype of `cl-sqids:sqids-error`, so one `handler-case`
clause catches the whole family:

```lisp
(handler-case
    (cl-sqids:make-sqids :alphabet "ab")
  (cl-sqids:alphabet-too-short-error (c)
    (format t "Alphabet too short: ~A~%" (cl-sqids:alphabet c))))
```

| Condition | Triggered when |
|---|---|
| `sqids-error` | Base class for every cl-sqids error |
| `alphabet-error` | Base class for alphabet errors (read via `alphabet`) |
| `alphabet-too-short-error` | Alphabet has fewer than 3 characters |
| `alphabet-duplicates-error` | Alphabet contains duplicate characters |
| `alphabet-multibyte-error` | Alphabet contains a non-ASCII char (code > 127) |
| `min-length-out-of-range-error` | `min-length` not in `[0, 255]` |
| `max-regenerate-attempts-error` | Blocklist can't be satisfied in alphabet-length + 1 attempts |
| `unsupported-numbers-type-error` | `encode` got something other than a non-negative int / list |

---

## Tests

The test system is decoupled from the main system and depends on FiveAM:

```bash
sbcl --non-interactive \
     --eval '(require :asdf)' \
     --eval "(pushnew (truename \"/path/to/cl-sqids/\") asdf:*central-registry* :test #'equal)" \
     --eval '(asdf:test-system :cl-sqids)'
```

Same for CCL:

```bash
ccl --batch \
    --eval '(require :asdf)' \
    --eval "(pushnew (truename \"/path/to/cl-sqids/\") asdf:*central-registry* :test #'equal)" \
    --eval '(asdf:test-system :cl-sqids)' \
    --eval '(ccl:quit)'
```

Expected output:

```
Running test suite CL-SQIDS
 Running test SIMPLE-NUMBERS ..
 ...
 Did 281 checks.
    Pass: 281 (100%)
    Skip: 0 ( 0%)
    Fail: 0 ( 0%)
```

Or interactively in a REPL:

```lisp
(ql:quickload :cl-sqids/tests)
(fiveam:run! :cl-sqids)
```

---

## Compatibility

| Implementation | Version | Status |
|---|---|---|
| SBCL | 2.6.6 and newer | ✅ all 281 checks pass |
| CCL (Clozure CL) | 1.13 and newer | ✅ all 281 checks pass |

No implementation-specific packages (`sb-ext:`, `ccl:`, ...) are used — every
line is portable ANSI Common Lisp. String and list constants use `defparameter`
(not `defconstant`) to avoid SBCL's "redefining a constant" warning and CCL
quirks.

---

## Project layout

```
cl-sqids/
├── cl-sqids.asd              # ASDF system (also defines :cl-sqids/tests subsystem)
├── TASK.md                   # Refactor task notes (Chinese)
├── README.md                 # Chinese README
├── README.en.md              # This file
├── USAGE.md                  # Chinese hands-on guide
├── USAGE.en.md               # English hands-on guide
├── LICENSE                   # Apache 2.0
├── src/
│   ├── package.lisp          # Package definition and exports
│   ├── conditions.lisp       # Condition hierarchy with :report
│   ├── constants.lisp        # Defaults (defparameter / defconstant)
│   ├── blocklist.lisp        # 3-tier blocklist matching
│   ├── codec.lisp            # Core algorithm (8 spec bugs fixed + macro dedup)
│   └── sqids.lisp            # CLOS class and constructor
└── t/
    ├── packages.lisp         # Test package
    ├── suite.lisp            # FiveAM master suite
    ├── test-encoding.lisp    # Encoding vectors
    ├── test-minlength.lisp   # MIN-LENGTH padding cascade
    ├── test-blocklist.lisp   # 3-tier matching + reshuffle
    ├── test-alphabet.lisp    # Alphabet validation
    └── test-roundtrip.lisp   # Round-trip / property tests
```

---

## License

[Apache License, Version 2.0](./LICENSE) — © David Gao.
