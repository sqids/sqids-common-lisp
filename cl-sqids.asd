;;;; cl-sqids.asd — ASDF system definitions for cl-sqids
;;;; (c) David Gao. Licensed under Apache 2.0.

(in-package #:asdf-user)

(defsystem #:cl-sqids
  :version "1.0.0"
  :author "David Gao <david.alpha.fox@gmail.com>"
  :maintainer "David Gao <david.alpha.fox@gmail.com>"
  :license "Apache 2.0"
  :homepage "http://www.ttalk.im/projects/cl-sqids"
  :bug-tracker "https://github.com/TTalkPro/cl-sqids/issues"
  :source-control (:git "https://github.com/TTalkPro/cl-sqids.git")
  :description "Short, unique, reversible IDs for Common Lisp (sqids spec)"
  :components ((:module "src"
                :serial t
                :components
                ((:file "package")
                 (:file "conditions")
                 (:file "constants")
                 (:file "blocklist")
                 (:file "codec")
                 (:file "sqids"))))
  :in-order-to ((test-op (test-op #:cl-sqids/tests))))

(defsystem #:cl-sqids/tests
  :description "Unit tests for cl-sqids (FiveAM, mirroring sqids-python vectors)"
  :author "David Gao <david.alpha.fox@gmail.com>"
  :license "Apache 2.0"
  :depends-on (#:cl-sqids #:fiveam)
  :components ((:module "t"
                :serial t
                :components
                ((:file "packages")
                 (:file "suite")
                 (:file "test-encoding")
                 (:file "test-minlength")
                 (:file "test-blocklist")
                 (:file "test-alphabet")
                 (:file "test-roundtrip"))))
  :perform (test-op (operation system)
                    (declare (ignore operation system))
                    (uiop:symbol-call :fiveam :run! :cl-sqids)))
