;;;; codec.lisp — Core sqids encode/decode algorithm
;;;; (c) David Gao. Licensed under Apache 2.0.
(in-package #:cl-sqids)

;;; The functions in this file implement the sqids algorithm exactly as
;;; described by https://github.com/sqids/sqids-spec — they are private
;;; (the `%` prefix) and operate on plain strings so that all the state
;;; needed lives on the SQIDS CLOS instance.
;;;
;;; Key correctness points (verified against the official TypeScript spec
;;; and sqids-python test vectors):
;;;
;;;   1. SHUFFLE is deterministic and depends only on i, j, char-codes and
;;;      alphabet length. It mutates its argument in place and returns it.
;;;   2. TO-ID uses do/while semantics: for num = 0 it returns a single
;;;      character (alphabet[0]), NOT an empty string.
;;;   3. The offset accumulator starts at NUMBERS-LENGTH, not 0.
;;;   4. Max regenerate attempts is `> alphabet-length` (strict), so
;;;      alphabet-length+1 attempts are allowed before raising.
;;;   5. The encoder rotates, reverses, then peels off the prefix;
;;;      the decoder mirrors this exactly.

(declaim (inline %rotate-string))

(defun %rotate-string (string offset)
  "Return a fresh SIMPLE-STRING built by rotating STRING left by OFFSET.
Equivalent to JavaScript's `s.slice(offset) + s.slice(0, offset)`."
  (declare (type simple-string string)
           (type (integer 0) offset))
  (if (zerop offset)
      (copy-seq string)
      (concatenate 'simple-string
                   (subseq string offset)
                   (subseq string 0 offset))))

(defmacro with-peeled-separator ((separator alphabet-without-sep alpha) &body body)
  "Bind SEPARATOR and ALPHABET-WITHOUT-SEP from the current alphabet state.
ALPHA is the live mutable alphabet (a SIMPLE-STRING). A fresh subseq is
taken for ALPHABET-WITHOUT-SEP so BODY cannot mutate ALPHA via it."
  (let ((a (gensym "ALPHA")))
    `(let* ((,a ,alpha)
            (,separator (char ,a 0))
            (,alphabet-without-sep (subseq ,a 1)))
       (declare (type simple-string ,a ,alphabet-without-sep)
                (type character ,separator))
       ,@body)))

(defun %shuffle (alphabet)
  "Deterministic in-place shuffle of ALPHABET (a mutable SIMPLE-STRING).
Returns ALPHABET. Implementation mirrors the spec exactly:

    for i = 0, j = len-1; j > 0; i++, j--:
        r = (i*j + code(ci) + code(cj)) mod len
        swap(ci, cr)
"
  (declare (type simple-string alphabet))
  (let ((len (length alphabet)))
    (declare (type (integer 0) len))
    (when (> len 1)
      (loop for i from 0
            for j downfrom (1- len) to 1
            do (let* ((ci (char alphabet i))
                      (cj (char alphabet j))
                      (r (mod (+ (* i j)
                                 (char-code ci)
                                 (char-code cj))
                              len)))
                 (rotatef (char alphabet i) (char alphabet r)))))
    alphabet))

(defun %to-id (num alphabet)
  "Encode a non-negative integer NUM as a string using ALPHABET as the digit
set. Uses do/while semantics so NUM = 0 yields a single character."
  (declare (type (integer 0) num)
           (type simple-string alphabet))
  (let ((len (length alphabet))
        (result num)
        (chars nil))
    (declare (type (integer 0) result len))
    (loop
      (push (char alphabet (mod result len)) chars)
      (setq result (nth-value 0 (floor result len)))
      (when (zerop result)
        (return)))
    (coerce chars 'simple-string)))

(defun %to-number (id alphabet)
  "Decode ID (a string over ALPHABET) back into a non-negative integer.
Inverse of %TO-ID."
  (declare (type simple-string id alphabet))
  (let ((len (length alphabet)))
    (declare (type (integer 0) len))
    (loop for c across id
          with result of-type (integer 0) = 0
          do (setq result (+ (* result len)
                             (or (position c alphabet :test #'char=)
                                 ;; Should not happen — decode validates up front.
                                 (return-from %to-number 0))))
          finally (return result))))

(defun %encode-numbers (numbers increment alphabet min-length)
  "Internal encoder. ALPHABET is the SQIDS instance's already-shuffled
alphabet; it is NOT modified by this function (we work on fresh copies).
Returns the encoded ID as a SIMPLE-STRING."
  (declare (type list numbers)
           (type (integer 0) increment min-length)
           (type simple-string alphabet))
  (let ((alpha-len (length alphabet)))
    (declare (type (integer 0) alpha-len))
    (when (> increment alpha-len)
      (error 'max-regenerate-attempts-error))
    ;; Step 1: compute offset. Per the spec, the accumulator is seeded with
    ;; (LENGTH NUMBERS), and for each (num, i) we add char-code(alpha[num mod
    ;; len]) + i. Then we add INCREMENT and reduce mod ALPHA-LEN once more.
    (let ((offset (mod (+ (length numbers)
                          (loop for num in numbers
                                for i from 0
                                sum (+ (char-code (char alphabet (mod num alpha-len)))
                                       i)))
                       alpha-len)))
      (declare (type (integer 0) offset))
      (setq offset (mod (+ offset increment) alpha-len))
      ;; Step 2: rotate, peel prefix, reverse into working mutable alphabet.
      (let* ((rotated (%rotate-string alphabet offset))
             (prefix (char rotated 0))
             (alpha (nreverse (copy-seq rotated)))
             (n (length numbers))
             (id (make-string 1 :initial-element prefix)))
        (declare (type simple-string alpha id))
        ;; Step 3: emit each number's body + separator between numbers.
        (loop for i from 0 below n
              for num in numbers
              do (with-peeled-separator (sep alpha-no-sep alpha)
                   (setq id (concatenate 'simple-string id (%to-id num alpha-no-sep)))
                   (when (< i (1- n))
                     (setq id (concatenate 'simple-string id (string sep)))
                     (%shuffle alpha))))
        ;; Step 4: min-length padding (append separator, then shuffle/chunk).
        (when (> min-length (length id))
          (with-peeled-separator (sep alpha-no-sep alpha)
            (declare (ignore alpha-no-sep))
            (setq id (concatenate 'simple-string id (string sep))))
          (loop while (> min-length (length id))
                do (%shuffle alpha)
                   (let ((chunk-size (min (- min-length (length id)) alpha-len)))
                     (setq id (concatenate 'simple-string id
                                           (subseq alpha 0 chunk-size))))))
        id))))

(defun %decode-id (id alphabet)
  "Internal decoder. ALPHABET is the SQIDS instance's stored alphabet.
Returns a list of non-negative integers, or NIL when ID is empty or
contains characters outside ALPHABET."
  (declare (type simple-string id alphabet))
  (when (string= id "")
    (return-from %decode-id nil))
  ;; Validate every character of ID against ALPHABET (per spec: any unknown
  ;; character causes the decoder to return an empty list).
  (loop for c across id
        unless (find c alphabet :test #'char=)
          do (return-from %decode-id nil))
  (let* ((prefix (char id 0))
         (offset (position prefix alphabet :test #'char=))
         (rotated (%rotate-string alphabet offset))
         (alpha (nreverse (copy-seq rotated)))
         (remaining (subseq id 1))
         (results nil))
    (declare (type simple-string alpha remaining))
    (loop while (> (length remaining) 0)
          do (with-peeled-separator (sep alpha-no-sep alpha)
               (let ((pos (position sep remaining :test #'char=)))
                 (cond
                   ;; No separator left: this is the last chunk.
                   ((null pos)
                    (push (%to-number remaining alpha-no-sep) results)
                    (return))
                   ;; Separator at position 0: padding boundary — stop.
                   ((zerop pos)
                    (return))
                   ;; Normal chunk: decode it, then shuffle for the next round.
                   (t
                    (let ((chunk (subseq remaining 0 pos)))
                      (push (%to-number chunk alpha-no-sep) results))
                    (%shuffle alpha)
                    (setq remaining (subseq remaining (1+ pos))))))))
    (nreverse results)))
