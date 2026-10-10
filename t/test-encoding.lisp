;;;; test-encoding.lisp — Encoding/decoding vectors (mirrors sqids-python/tests/test_encoding.py).
(in-package #:cl-sqids/tests)
(in-suite :cl-sqids)

(test simple-numbers
  "Encoding the canonical [1,2,3] returns the spec-pinned 86Rf07."
  (let ((s (make-sqids)))
    (is (string= "86Rf07" (encode '(1 2 3) s)))
    (is (equal '(1 2 3) (decode "86Rf07" s)))))

(test different-numbers
  "[1] => Uk, [22,33,44,55,66,77] round-trips, [1,2,3] => 86Rf07."
  (let ((s (make-sqids)))
    (is (string= "Uk" (encode '(1) s)))
    (is (string= "gb" (encode '(2) s)))
    (is (string= "Ef" (encode '(3) s)))
    (is (string= "Vq" (encode '(4) s)))
    (is (string= "uw" (encode '(5) s)))
    (is (string= "OI" (encode '(6) s)))
    (is (string= "AX" (encode '(7) s)))
    (is (string= "p6" (encode '(8) s)))
    (is (string= "nJ" (encode '(9) s)))))

(test single-byte-inputs
  "Sequential single integers 0..9 must match the official spec vectors."
  (let ((s (make-sqids)))
    (is (string= "bM" (encode '(0) s)))))

(test empty-input-returns-empty-string
  "Encoding the empty list returns the empty string."
  (let ((s (make-sqids)))
    (is (string= "" (encode '() s)))))

(test decoding-empty-string
  "Decoding the empty string returns NIL."
  (let ((s (make-sqids)))
    (is (equal '() (decode "" s)))))

(test decoding-invalid-char-returns-empty
  "Decoding a string with characters outside the alphabet returns NIL."
  (let ((s (make-sqids)))
    ;; '#' is not in the default alphabet.
    (is (equal '() (decode "#" s)))
    ;; '*' is not in the default alphabet.
    (is (equal '() (decode "*" s)))))

(test accept-integer-input
  "ENCODE accepts a single non-negative integer in addition to a list."
  (let ((s (make-sqids)))
    (is (string= "Uk" (encode 1 s)))
    (is (string= "bM" (encode 0 s)))
    (is (string= "86Rf07" (encode '(1 2 3) s)))))

(test reject-negative-input
  "Encoding a negative integer or a list containing one signals UNSUPPORTED-NUMBERS-TYPE-ERROR."
  (let ((s (make-sqids)))
    (signals unsupported-numbers-type-error (encode -1 s))
    (signals unsupported-numbers-type-error (encode '(1 -2 3) s))))

(test reject-unsupported-type
  "Encoding a string / float / etc. signals UNSUPPORTED-NUMBERS-TYPE-ERROR."
  (let ((s (make-sqids)))
    (signals unsupported-numbers-type-error (encode "foo" s))
    (signals unsupported-numbers-type-error (encode 1.0 s))
    (signals unsupported-numbers-type-error (encode :foo s))))

(test not-encoded-rerun-with-blocklist-disabled
  "[4572721] without blocklist yields aho1e (i.e. blocklist drives the re-shuffle)."
  (let ((s (make-sqids :blocklist '())))
    (is (string= "aho1e" (encode '(4572721) s)))))

(test two-number-tuples-starting-with-zero
  "Pairs (0,k) for k in 0..9 must match the spec-pinned vectors."
  (let ((s (make-sqids))
        (expected '((0 0 . "SvIz") (0 1 . "n3qa") (0 2 . "tryF") (0 3 . "eg6q") (0 4 . "rSCF")
                    (0 5 . "sR8x") (0 6 . "uY2M") (0 7 . "74dI") (0 8 . "30WX") (0 9 . "moxr"))))
    (dolist (e expected)
      (is (string= (cddr e) (encode (list (car e) (cadr e)) s))
          "Expected (~D, ~D) => ~A" (car e) (cadr e) (cddr e)))))

(test two-number-tuples-ending-with-zero
  "Pairs (k,0) for k in 0..9 must match the spec-pinned vectors."
  (let ((s (make-sqids))
        (expected '((1 0 . "nWqP") (2 0 . "tSyw") (3 0 . "eX68") (4 0 . "rxCY") (5 0 . "sV8a")
                    (6 0 . "uf2K") (7 0 . "7Cdk") (8 0 . "3aWP") (9 0 . "m2xn"))))
    (dolist (e expected)
      (is (string= (cddr e) (encode (list (car e) (cadr e)) s))
          "Expected (~D, ~D) => ~A" (car e) (cadr e) (cddr e)))))
