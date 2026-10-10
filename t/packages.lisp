;;;; packages.lisp — Test package definitions for cl-sqids.
(in-package #:cl-user)

(defpackage #:cl-sqids/tests
  (:documentation "FiveAM test suite for CL-SQIDS, mirroring the official sqids-python test vectors.")
  (:use #:common-lisp #:cl-sqids #:fiveam)
  (:import-from #:fiveam
                #:def-suite
                #:in-suite
                #:is
                #:is-false
                #:is-true
                #:signals
                #:test
                #:finishes))
