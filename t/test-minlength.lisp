;;;; test-minlength.lisp — MIN-LENGTH padding vectors (mirrors sqids-python/tests/test_minlength.py).
(in-package #:cl-sqids/tests)
(in-suite :cl-sqids)

(test minlength-cascade-for-1-2-3
  "Encoding [1,2,3] with MIN-LENGTH 6..13 produces the spec-pinned cascade."
  (let ((vectors '((6  . "86Rf07")
                   (7  . "86Rf07x")
                   (8  . "86Rf07xd")
                   (9  . "86Rf07xd4")
                   (10 . "86Rf07xd4z")
                   (11 . "86Rf07xd4zB")
                   (12 . "86Rf07xd4zBm")
                   (13 . "86Rf07xd4zBmi"))))
    (dolist (v vectors)
      (let ((s (make-sqids :min-length (car v))))
        (is (string= (cdr v) (encode '(1 2 3) s))
            "MIN-LENGTH ~D should produce ~A" (car v) (cdr v))))))

(test minlength-long-cascade
  "Encoding [1,2,3] with MIN-LENGTH 62..65 produces the spec-pinned multi-chunk cascade."
  (let ((vectors
          '((62 . "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTM")
            (63 . "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTMy")
            (64 . "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTMyf")
            (65 . "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTMyf1"))))
    (dolist (v vectors)
      (let ((s (make-sqids :min-length (car v))))
        (is (string= (cdr v) (encode '(1 2 3) s))
            "MIN-LENGTH ~D should produce ~A" (car v) (cdr v))))))

(test minlength-appends-padding
  "MIN-LENGTH strictly greater than the natural encoding length must append padding characters."
  (let ((s (make-sqids :min-length 10)))
    (let ((id (encode '(1 2 3) s)))
      (is (= 10 (length id))))))

(test minlength-zero-extension
  "Encoding (0, k) with MIN-LENGTH 62 matches the spec-pinned zero-extension vectors."
  (let ((vectors
          '((0 0 . "SvIzsqYMyQwI3GWgJAe17URxX8V924Co0DaTZLtFjHriEn5bPhcSkfmvOslpBu")
            (0 1 . "n3qafPOLKdfHpuNw3M61r95svbeJGk7aAEgYn4WlSjXURmF8IDqZBy0CT2VxQc"))))
    (dolist (v vectors)
      (let ((s (make-sqids :min-length 62)))
        (is (string= (cddr v) (encode (list (car v) (cadr v)) s))
            "MIN-LENGTH 62 (~D, ~D) should produce ~A" (car v) (cadr v) (cddr v))))))

(test minlength-out-of-range
  "MIN-LENGTH outside [0, 255] signals MIN-LENGTH-OUT-OF-RANGE-ERROR."
  (signals min-length-out-of-range-error (make-sqids :min-length -1))
  (signals min-length-out-of-range-error (make-sqids :min-length 256))
  (signals min-length-out-of-range-error (make-sqids :min-length 1000))
  (signals min-length-out-of-range-error (make-sqids :min-length :foo)))
