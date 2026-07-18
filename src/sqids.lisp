;;;; sqids.lisp — CLOS class, generic API and constructor
;;;; (c) David Gao. Licensed under Apache 2.0.
(in-package #:cl-sqids)

;;; The SQIDS class is an immutable (after construction) handle holding
;;; the alphabet (shuffled once at construction time per the spec), the
;;; MIN-LENGTH, and three pre-filtered blocklist tiers. All slots are
;;; read-only via the exported readers — there is intentionally no
;;; SETF, so the original buggy pattern of `:accessor` + manual SETF
;;; override is gone.

(defclass sqids ()
  ((%alphabet :type simple-string
              :reader alphabet
              :initarg :alphabet
              :documentation " shuffled alphabet (mutable copy is taken by ENCODE/DECODE).")
   (%min-length :type (integer 0 255)
                :reader min-length
                :initarg :min-length
                :documentation "Minimum length of generated IDs (0 means no padding).")
   (%blocklist-exact :type list
                     :reader blocklist-exact
                     :initarg :blocklist-exact
                     :documentation "Words compared by exact equality only.")
   (%blocklist-ends :type list
                    :reader blocklist-ends
                    :initarg :blocklist-ends
                    :documentation "Words compared by prefix or suffix match.")
   (%blocklist-anywhere :type list
                        :reader blocklist-anywhere
                        :initarg :blocklist-anywhere
                        :documentation "Words compared by substring match.")
   (%blocklist-original :type list
                        :reader blocklist-original
                        :initarg :blocklist-original
                        :documentation "User-supplied blocklist, unmodified."))
  (:documentation
   "Immutable sqids encoder/decoder.

Construct with MAKE-SQIDS. Use ENCODE and DECODE to convert between
lists of non-negative integers and short sqid strings."))

(defgeneric encode (numbers sqids)
  (:documentation
   "Encode NUMBERS into a sqid string using SQIDS.

NUMBERS may be a non-negative integer or a list of non-negative
integers. Returns a SIMPLE-STRING that satisfies MIN-LENGTH and avoids
every word in the blocklist. The empty list returns the empty string."))

(defgeneric decode (id sqids)
  (:documentation
   "Decode ID (a string) into a list of non-negative integers using
SQIDS. Returns NIL when ID is empty or contains characters absent
from the alphabet. Does NOT re-validate against the blocklist — old
or previously-blocked IDs still decode."))

(defmethod encode ((numbers integer) (sqids sqids))
  (if (minusp numbers)
      (error 'unsupported-numbers-type-error :value numbers)
      (encode (list numbers) sqids)))

(defmethod encode ((numbers list) (sqids sqids))
  ;; Empty list short-circuits to the empty string per spec.
  (when (endp numbers)
    (return-from encode ""))
  ;; Negative integers in a list are rejected.
  (dolist (n numbers)
    (unless (and (integerp n) (not (minusp n)))
      (error 'unsupported-numbers-type-error :value numbers)))
  (let ((alpha (alphabet sqids)))
    (declare (type simple-string alpha))
    (labels ((try (increment)
               (when (> increment (length alpha))
                 (error 'max-regenerate-attempts-error))
               (let ((id (%encode-numbers numbers increment alpha (min-length sqids))))
                 (if (blocked-p id
                                (slot-value sqids '%blocklist-exact)
                                (slot-value sqids '%blocklist-ends)
                                (slot-value sqids '%blocklist-anywhere))
                     (try (1+ increment))
                     id))))
      (try 0))))

;; Catch-all for unsupported argument types (e.g. strings, floats).
(defmethod encode ((numbers t) (sqids sqids))
  (error 'unsupported-numbers-type-error :value numbers))

(defmethod decode ((id string) (sqids sqids))
  (%decode-id id (alphabet sqids)))

;; Convenience for callers that pass NIL (the original API tolerated it).
(defmethod decode ((id (eql nil)) (sqids sqids))
  nil)

;;; ------------------------------------------------------------------
;;;  Constructor & validation
;;; ------------------------------------------------------------------

(defun %check-alphabet (alphabet)
  "Signal the appropriate ALPHABET-ERROR if ALPHABET is invalid; otherwise return ALPHABET."
  (declare (type string alphabet))
  (let ((len (length alphabet)))
    (when (< len 3)
      (error 'alphabet-too-short-error :alphabet alphabet))
    ;; Uniqueness check.
    (loop for i from 1 below len
          with sorted = (sort (copy-seq alphabet) #'char<)
          do (when (char= (char sorted i) (char sorted (1- i)))
               (error 'alphabet-duplicates-error :alphabet alphabet)))
    ;; Multibyte / non-ASCII check.
    (loop for c across alphabet
          do (when (> (char-code c) 127)
               (error 'alphabet-multibyte-error :alphabet alphabet :char c))))
  alphabet)

(defun %check-min-length (min-length)
  "Signal MIN-LENGTH-OUT-OF-RANGE-ERROR unless MIN-LENGTH is an integer in [0, 255]."
  (unless (and (integerp min-length) (<= 0 min-length) (<= min-length 255))
    (error 'min-length-out-of-range-error :value min-length))
  min-length)

(defun make-sqids (&key
                   (alphabet *default-alphabet*)
                   (min-length +default-min-length+)
                   (blocklist *default-blocklist*))
  "Construct and return a SQIDS encoder/decoder.

Keyword arguments:
  :ALPHABET   — string of >= 3 unique ASCII characters (default *DEFAULT-ALPHABET*).
  :MIN-LENGTH — integer in [0, 255] (default +DEFAULT-MIN-LENGTH+, the spec's 0).
  :BLOCKLIST  — list of profanity/leet-speak words to avoid (default *DEFAULT-BLOCKLIST*).

The alphabet is shuffled once at construction time and cached on the
instance. Signals ALPHABET-ERROR or MIN-LENGTH-OUT-OF-RANGE-ERROR on
invalid arguments."
  (check-type alphabet string)
  (check-type blocklist list)
  (%check-alphabet alphabet)
  (%check-min-length min-length)
  (multiple-value-bind (exact ends anywhere)
      (filter-blocklist blocklist alphabet)
    ;; Per spec: alphabet is shuffled ONCE in the constructor and reused
    ;; verbatim by every ENCODE / DECODE call. We work on a private copy
    ;; so the user's input string is never mutated.
    (let ((shuffled (copy-seq alphabet)))
      (declare (type simple-string shuffled))
      (%shuffle shuffled)
      (make-instance 'sqids
                     :alphabet shuffled
                     :min-length min-length
                     :blocklist-exact exact
                     :blocklist-ends ends
                     :blocklist-anywhere anywhere
                     :blocklist-original (copy-list blocklist)))))
