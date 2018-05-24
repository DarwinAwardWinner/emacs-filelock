;;; filelock.el --- Functions for manipulating file locks programmatically -*- lexical-binding: t -*-

;; Copyright (C) 2018 Ryan C. Thompson

;; Filename: filelock.el
;; Author: Ryan C. Thompson
;; Created: Thu May 24 13:39:36 2018 (-0700)
;; Version: 0.1
;; Package-Requires: ((emacs "0") (cl-lib "0") (f "0"))
;; URL:
;; Keywords: extensions, files, tools

;; This file is NOT part of GNU Emacs.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:

;; Emacs has the ability to create lock files to prevent two Emacs
;; processes from editing the same file at the same time. However, the
;; internal functions to programmatically lock and unlock files are
;; not exposed in Emacs Lisp. Emacs simply locks a file when the
;; buffer visiting it becomes modified, and unlocks it after the
;; buffer is saved or reverted. Furthermore, when Emacs encounters
;; another process's lock file, by default it prompts interactively
;; for what to do.

;; This package provides a simple interface for manually locking and
;; unlocking files using the standard Emacs locks, suitable for use in
;; programming. The basic functions are `acquire-file-lock' and
;; `release-file-lock', and a macro called `with-file-lock' is also
;; provided.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(require 'f)
(eval-when-compile (require 'cl-lib))

(defsubst file-lock-owned-p (file)
  "Return non-nil if FILE is locked by the current Emacs.

If FILE is not locked or is locked by another Emacs process,
returns nil."
  (eq t (file-locked-p file)))

(defun acquire-file-lock (&optional file timeout)
  "Acquire the file lock on FILE for this Emacs.

If TIMEOUT is non-nil, a `file-locked' signal will be raised if the
lock on FILE cannot be acquired after that many seconds. If
TIMEOUT is nil, this will wait forever for the lock.

Note that acquiring the lock on a file does not automatically
create the file. You can use a lock on a nonexistent file as a
mutex. However, Emacs needs to have write permissions in the
file's directory in order to create the lock file."
  (cl-letf
      ((file (f-expand (or file (buffer-file-name))))
       ((symbol-function 'ask-user-about-lock)
        (lambda (file opponent)
          (signal 'file-locked (list file opponent)))))
    (unless (eq t (file-locked-p file))
      (with-temp-buffer
        (unwind-protect
            (progn
              (setq buffer-file-name file)
              (set-buffer-modified-p t)
              (insert "something")
              (cl-loop
               with acquired = nil
               until acquired
               while (or (null timeout) (> timeout 0))
               do (condition-case err
                      (progn
                        (lock-buffer file)
                        (setq acquired t))
                    (file-locked
                     (sit-for 1)))
               do (when timeout (setq timeout (1- timeout)))
               ;; If the file still can't be locked, this will finally throw
               ;; the appropriate signal.
               finally return (lock-buffer file)))
          (set-buffer-modified-p nil))))
    (cl-assert (file-lock-owned-p file))))

(defun release-file-lock (&optional file)
  "Release any file lock this Emacs is holding on FILE."
  (let ((file (f-expand (or file (buffer-file-name))))
        (lockfile (f-join (f-dirname file)
                          (concat ".#" (f-filename file)))))
    (when (file-lock-owned-p file)
      (delete-file lockfile))
    (cl-assert (not (file-lock-owned-p file)))))

(defmacro with-file-lock (file &rest body)
  "Evaluate BODY while holding the lock for FILE.

If Emacs needed to acquire the lock for FILE before evaluating
BODY, it will release it afterward. If the lock was already held,
it will not be released."
  (declare (indent 1))
  `(if (file-lock-owned-p ,file)
       (progn ,@body)
     (unwind-protect
         (progn
           (acquire-file-lock ,file)
           ,@body)
       (release-file-lock ,file))))

(provide 'filelock)

;;; filelock.el ends here
