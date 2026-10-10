;;;; blocklist.lisp — Pre-filtering and matching of the sqids blocklist
;;;; (c) David Gao. Licensed under Apache 2.0.
(in-package #:cl-sqids)

;;; The sqids spec defines a 3-tier blocklist match for a candidate ID and
;;; a single word:
;;;
;;;   * len(id) <= 3 OR len(word) <= 3  → exact equality (id == word)
;;;   * len(id)  > 3 AND word has digit → prefix or suffix match
;;;   * len(id)  > 3 AND word is plain  → substring match
;;;
;;; At construction time we pre-filter and split the raw blocklist into 3
;;; lists so runtime matching is O(blocklist) per tier (and short IDs only
;;; ever touch the exact tier). This mirrors sqids-python's optimisation.

(declaim (inline %ascii-digit-p))

(defun %ascii-digit-p (char)
  "Return CHAR if it is an ASCII digit, otherwise NIL."
  (declare (type character char))
  (and (char<= #\0 char #\9) char))

(defun %all-chars-in-alphabet-p (word alphabet-table)
  "Return T if every character of WORD (already lowercased) is present in
ALPHABET-TABLE (a hash-table of alphabet characters, also lowercased)."
  (declare (type simple-string word))
  (loop for c across word always (gethash c alphabet-table)))

(defun %build-alphabet-table (alphabet)
  "Return a hash-table containing the lowercased characters of ALPHABET."
  (let ((table (make-hash-table :size (length alphabet))))
    (loop for c across (string-downcase alphabet)
          do (setf (gethash c table) t))
    table))

(defun filter-blocklist (raw-blocklist alphabet)
  "Filter and split RAW-BLOCKLIST into 3 VALUES:
  1. EXACT — words of length 3 (always compared by exact equality)
  2. ENDS  — words with digits (compared by prefix or suffix when ID > 3 chars)
  3. ANYWHERE — plain words (compared by substring when ID > 3 chars)

Words shorter than 3 characters or containing characters not in ALPHABET are
dropped, matching sqids-python's __init__ behaviour. Order is preserved."
  (declare (type list raw-blocklist)
           (type simple-string alphabet))
  (let ((table (%build-alphabet-table alphabet))
        exact ends anywhere)
    (dolist (word raw-blocklist (values (nreverse exact)
                                        (nreverse ends)
                                        (nreverse anywhere)))
      (let ((word-low (string-downcase word)))
        (when (and (>= (length word-low) 3)
                   (%all-chars-in-alphabet-p word-low table))
          (cond
            ((= 3 (length word-low))
             (push word-low exact))
            ((loop for c across word-low thereis (%ascii-digit-p c))
             (push word-low ends))
            (t
             (push word-low anywhere))))))))

(declaim (inline %starts-with-p %ends-with-p))

(defun %starts-with-p (prefix seq)
  "Return T if SEQ starts with PREFIX (character-wise)."
  (declare (type simple-string prefix seq))
  (let ((p-len (length prefix)))
    (and (<= p-len (length seq))
         (string= prefix seq :end2 p-len))))

(defun %ends-with-p (suffix seq)
  "Return T if SEQ ends with SUFFIX (character-wise)."
  (declare (type simple-string suffix seq))
  (let ((s-len (length seq))
        (suf-len (length suffix)))
    (and (<= suf-len s-len)
         (string= suffix seq :start1 0 :end1 suf-len
                                :start2 (- s-len suf-len) :end2 s-len))))

(defun blocked-p (id exact-list ends-list anywhere-list)
  "Return T if ID matches any word in the 3 pre-split blocklist tiers.
The match follows sqids-spec exactly:
  * short ID (len <= 3): exact equality only;
  * long ID: exact equality for length-3 words, prefix/suffix for leet
    words, substring for plain words."
  (declare (type simple-string id))
  (let ((id-low (string-downcase id))
        (id-len (length id)))
    (or
     ;; Exact-equality tier (covers both short ID and length-3 words).
     (dolist (word exact-list)
       (when (string= id-low word)
         (return t)))
     ;; Remaining tiers only apply to IDs strictly longer than 3 chars.
     (when (> id-len 3)
       (or
        (dolist (word ends-list)
          (when (or (%starts-with-p word id-low)
                    (%ends-with-p word id-low))
            (return t)))
        (dolist (word anywhere-list)
          (when (search word id-low)
            (return t))))))))
