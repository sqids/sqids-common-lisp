;;;; test-alphabet.lisp — Custom alphabet validation (mirrors sqids-python/tests/test_alphabet.py).
(in-package #:cl-sqids/tests)
(in-suite :cl-sqids)

(test hex-alphabet-pinned-vector
  "Encoding [1,2,3] with hex alphabet yields 489158."
  (let ((s (make-sqids :alphabet "0123456789abcdef")))
    (is (string= "489158" (encode '(1 2 3) s)))))

(test min-alphabet
  "Three-character alphabets are accepted and round-trip."
  (let ((s (make-sqids :alphabet "abc")))
    (is (equal '(1 2 3) (decode (encode '(1 2 3) s) s)))))

(test too-short-alphabet
  "Alphabets shorter than 3 characters signal ALPHABET-TOO-SHORT-ERROR."
  (signals alphabet-too-short-error (make-sqids :alphabet "ab"))
  (signals alphabet-too-short-error (make-sqids :alphabet "a"))
  (signals alphabet-too-short-error (make-sqids :alphabet "")))

(test duplicate-alphabet
  "Alphabets with duplicate characters signal ALPHABET-DUPLICATES-ERROR."
  (signals alphabet-duplicates-error (make-sqids :alphabet "aabbbc"))
  (signals alphabet-duplicates-error (make-sqids :alphabet "01234567890")))

(test multibyte-alphabet
  "Alphabets containing non-ASCII characters signal ALPHABET-MULTIBYTE-ERROR."
  (signals alphabet-multibyte-error (make-sqids :alphabet "ëabcdefghijklmnopqrstuvwxyz"))
  (signals alphabet-multibyte-error (make-sqids :alphabet "abcdeß")))

(test alphabet-is-shuffled-once-per-instance
  "The constructor shuffles the alphabet exactly once; both readers see the same string."
  (let* ((input "0123456789abcdef")
         (s (make-sqids :alphabet input)))
    ;; The shuffled alphabet is stable across calls.
    (is (string= (alphabet s) (alphabet s)))
    ;; The shuffled alphabet is (with extremely high probability) NOT the input.
    (is (not (string= input (alphabet s))))))

(test custom-alphabet-round-trips
  "A custom alphabet round-trips a range of numbers."
  (let ((s (make-sqids :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ")))
    (dolist (numbers '((0) (1) (1 2 3) (0 0 0) (100 200 300)))
      (is (equal numbers (decode (encode numbers s) s))))))
