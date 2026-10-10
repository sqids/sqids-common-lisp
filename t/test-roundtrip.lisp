;;;; test-roundtrip.lisp — Round-trip property tests over many ranges.
(in-package #:cl-sqids/tests)
(in-suite :cl-sqids)

(test round-trip-single-numbers-0-to-99
  "Encoding and decoding each of 0..99 returns the original number."
  (let ((s (make-sqids)))
    (dotimes (n 100)
      (let ((id (encode (list n) s)))
        (is (equal (list n) (decode id s))
            "Round-trip failed for ~D (id=~S)" n id)))))

(test round-trip-lists-0-to-99
  "Encoding and decoding the list (0..k) for k in 0..50 returns the original list."
  (let ((s (make-sqids)))
    (loop for k from 1 to 50
          for numbers = (loop for i from 0 below k collect i)
          do (let ((id (encode numbers s)))
               (is (equal numbers (decode id s))
                   "Round-trip failed for ~D-element list" k)))))

(test round-trip-large-numbers
  "Encoding and decoding several large integers round-trips correctly."
  (let ((s (make-sqids)))
    (dolist (n (list (expt 10 6)
                     (expt 10 9)
                     (expt 10 12)
                     most-positive-fixnum
                     (1- most-positive-fixnum)))
      (let ((id (encode (list n) s)))
        (is (equal (list n) (decode id s))
            "Round-trip failed for ~D (id=~S)" n id)))))

(test round-trip-custom-alphabet
  "Round-trip works with a custom alphabet."
  (let ((s (make-sqids :alphabet "abcdefghijklmnopqrstuvwxyz0123456789")))
    (dolist (numbers '((0 0 0) (1 2 3) (1000000 2000000 3000000)))
      (is (equal numbers (decode (encode numbers s) s))))))

(test round-trip-with-min-length
  "Round-trip works with non-zero MIN-LENGTH (decoder ignores padding)."
  (let ((s (make-sqids :min-length 20)))
    (dolist (numbers '((1) (1 2 3) (1 2 3 4 5)))
      (let ((id (encode numbers s)))
        (is (>= (length id) 20))
        (is (equal numbers (decode id s)))))))

(test encode-idempotent
  "Calling ENCODE twice on the same input yields the same string."
  (let ((s (make-sqids)))
    (dotimes (n 20)
      (is (string= (encode (list n) s)
                   (encode (list n) s))))))

(test decode-nil-returns-nil
  "DECODE of NIL returns NIL (convenience method)."
  (let ((s (make-sqids)))
    (is (null (decode nil s)))))

(test readers-return-expected-types
  "Exported readers return ALPHABET (string), MIN-LENGTH (integer 0..255), BLOCKLIST-ORIGINAL (list)."
  (let ((s (make-sqids :min-length 7 :alphabet "abcdefgXYZ" :blocklist '("foo" "bar"))))
    (is (stringp (alphabet s)))
    (is (typep (min-length s) '(integer 0 255)))
    (is (= 7 (min-length s)))
    (is (consp (blocklist-original s)))))
