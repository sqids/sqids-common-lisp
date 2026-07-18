;;;; conditions.lisp — Condition types for cl-sqids
;;;; (c) David Gao. Licensed under Apache 2.0.
(in-package #:cl-sqids)

;;; All cl-sqids errors inherit from SQIDS-ERROR. Sub-types carry the data
;;; needed to produce a human-readable report and to allow programs to
;;; recover programmatically via HANDLER-CASE.

(define-condition sqids-error (error)
  ()
  (:documentation "Base condition type for every error signalled by cl-sqids."))

;;; Alphabet-related errors form their own subtree so user code can match
;;; the whole family with a single HANDLER-CASE clause.
(define-condition alphabet-error (sqids-error)
  ((%alphabet :initarg :alphabet :reader alphabet))
  (:documentation "Alphabet validation failed. The offending alphabet is available via ALPHABET."))

(define-condition alphabet-too-short-error (alphabet-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Alphabet length must be at least 3 (got ~D character~:P)."
                     (length (alphabet condition)))))
  (:documentation "Raised when an alphabet has fewer than 3 characters."))

(define-condition alphabet-duplicates-error (alphabet-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Alphabet must contain unique characters: ~S."
                     (alphabet condition))))
  (:documentation "Raised when an alphabet contains duplicate characters."))

(define-condition alphabet-multibyte-error (alphabet-error)
  ((%char :initarg :char :reader condition-char))
  (:report (lambda (condition stream)
             (let ((ch (condition-char condition)))
               (format stream "Alphabet cannot contain multibyte characters: ~S has code point ~D."
                       ch (char-code ch)))))
  (:documentation "Raised when an alphabet contains a non-ASCII (code point > 127) character."))

(define-condition min-length-out-of-range-error (sqids-error)
  ((%value :initarg :value :reader condition-value))
  (:report (lambda (condition stream)
             (format stream "MIN-LENGTH must be an integer in [0, 255] (got ~S)."
                     (condition-value condition))))
  (:documentation "Raised when MIN-LENGTH is not an integer in the inclusive range [0, 255]."))

(define-condition max-regenerate-attempts-error (sqids-error)
  ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "Reached maximum attempts to re-generate the ID; ~
                             every candidate was blocked by the blocklist.")))
  (:documentation "Raised when the blocklist cannot be satisfied within ALPHABET-LENGTH + 1 attempts."))

(define-condition unsupported-numbers-type-error (sqids-error)
  ((%value :initarg :value :reader condition-value))
  (:report (lambda (condition stream)
             (format stream "NUMBERS must be a non-negative integer or a list thereof (got ~S)."
                     (condition-value condition))))
  (:documentation "Raised when ENCODE receives something other than a non-negative integer or a list of them."))
