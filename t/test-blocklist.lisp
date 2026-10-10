;;;; test-blocklist.lisp — Blocklist 3-tier matching & reshuffle (mirrors sqids-python/tests/test_blocklist.py).
(in-package #:cl-sqids/tests)
(in-suite :cl-sqids)

(test blocklist-reshuffle-default
  "Encoding [4572721] with the default blocklist yields JExTR (NOT aho1e)."
  (let ((s (make-sqids)))
    (is (string= "JExTR" (encode '(4572721) s)))))

(test blocklist-decoded-still-decodes
  "Decoder accepts the blocked ID 'aho1e' and returns the original numbers."
  (let ((s (make-sqids)))
    (is (equal '(4572721) (decode "aho1e" s)))))

(test blocklist-disabled-yields-aho1e
  "Encoding [4572721] with an empty blocklist yields aho1e."
  (let ((s (make-sqids :blocklist '())))
    (is (string= "aho1e" (encode '(4572721) s)))))

(test blocklist-disabled-yields-86rf07
  "Encoding [1,2,3] with an empty blocklist still yields 86Rf07 (blocklist doesn't change base output)."
  (let ((s (make-sqids :blocklist '())))
    (is (string= "86Rf07" (encode '(1 2 3) s)))))

(test decoder-accepts-blocked-variants
  "The decoder MUST accept previously-blocked encodings and decode them to the original numbers."
  ;; All five of these were valid encodings of [1,2,3] before they were blocklisted.
  (let ((s (make-sqids :blocklist '("86Rf07" "se8ojk" "ARsz1p" "Q8AI49" "5sQRZO"))))
    (is (equal '(1 2 3) (decode "86Rf07" s)))
    (is (equal '(1 2 3) (decode "se8ojk" s)))
    (is (equal '(1 2 3) (decode "ARsz1p" s)))
    (is (equal '(1 2 3) (decode "Q8AI49" s)))
    (is (equal '(1 2 3) (decode "5sQRZO" s)))))

(test all-blocked-alphabet-throws
  "Alphabet/blocklist combinations that can never produce a clean ID signal MAX-REGENERATE-ATTEMPTS-ERROR."
  (let ((s (make-sqids :alphabet "abc" :blocklist '("cab" "abc" "bca") :min-length 3)))
    (signals max-regenerate-attempts-error (encode '(0) s))))

(test short-word-in-blocklist-is-ignored
  "Words shorter than 3 characters are filtered out at construction time and never trigger reshuffle."
  ;; Default encoding of [0] is the 2-char "bM"; blocklisting it must have no effect.
  (let* ((default (make-sqids))
         (default-id (encode '(0) default))
         (s (make-sqids :blocklist (list default-id))))
    (is (= 2 (length default-id)))
    (is (string= default-id (encode '(0) s))
        "Short blocklist word ~A should be filtered out" default-id)))

(test blocklist-matching-case-insensitive
  "Blocklist matching is case-insensitive."
  (let ((s (make-sqids :blocklist '("ARSZ1P"))))
    ;; The encoder should produce something different from a case-insensitive match.
    (is (not (string= "ARsz1p" (encode '(1 2 3) s))))))
