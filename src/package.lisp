;;;; package.lisp — Package definition for cl-sqids
;;;; (c) David Gao. Licensed under Apache 2.0.
(in-package :cl-user)

(defpackage #:cl-sqids
  (:documentation
   "Common Lisp implementation of sqids — short, unique, reversible IDs.

A sqid encodes a list of non-negative integers into a short, URL-safe
string. The same sqid can be decoded back to the original list. Encoding
is deterministic and an optional profanity blocklist is enforced.

Public API:
  MAKE-SQIDS — construct an encoder/decoder
  ENCODE     — numbers -> sqid string
  DECODE     — sqid string -> list of numbers")
  (:use #:common-lisp)
  (:export
    ;; Class and constructor
    #:sqids
    #:make-sqids
    ;; Generic functions
    #:encode
    #:decode
    ;; Introspection readers (on SQIDS instances)
    #:alphabet
    #:min-length
    #:blocklist-original
    ;; Condition readers (on condition instances)
    #:condition-char
    #:condition-value
    ;; Condition hierarchy
    #:sqids-error
    #:alphabet-error
    #:alphabet-too-short-error
    #:alphabet-duplicates-error
    #:alphabet-multibyte-error
    #:min-length-out-of-range-error
    #:max-regenerate-attempts-error
    #:unsupported-numbers-type-error))
