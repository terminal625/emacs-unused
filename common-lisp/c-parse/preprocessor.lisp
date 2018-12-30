(in-package :c-parse)

;;be loud when doing things
(defparameter *verbose* t)

(defun path-for-original (path)
  (reroot path :prefix "_original__"))

(defun cache-those-originals (path)
  "save a copy of a file in the shadowroot, returning the path to the shadowroot file"
  (let ((new-path (path-for-original path)))
    (when *verbose*
      (format t  "caching original files:~%for ~a ~%at ~a~%" path new-path))
    (uiop:copy-file
     path
     new-path)
    new-path))
;;;;C preprocessor
;;;;ignore trigraphs
;;;;non-portably use newlines to iindicate line breaks, not mac or windows
;;;;lines which end in backslash are joined
;;LF -> unix, CR LF ->DOS,VMS, CR ->classic mac os
;;just support unix? uiop:read-file-lines

(defun line-attach-p (line)
  (let ((len (length line)))
    (unless (zerop len)
      (char= #\\ (uiop:last-char line)))))
(defun all-but-last-char-string (str)
  (let ((len (length str)))
    (if (zerop len)
	""
	(subseq str 0 (1- len)))))
(defun attach (lines end)
  (%concatenate-string
   (nconc (mapcar 'all-but-last-char-string lines)
	  (list end))))
(defun join-lines-list (&optional (file-lines '("bar\\" "foo")))
  (let ((acc nil)
	(lines-acc))
    (dolist (line file-lines)
      (if (line-attach-p line)
	  (push line lines-acc)
	  (progn
	    (push (attach (nreverse lines-acc) line)
		  acc)
	    (setf lines-acc nil))))
    (when lines-acc
      (push (attach (nreverse (butlast lines-acc))
		    (car (last lines-acc)))
	    acc))
    (nreverse acc)))
(defun path-for-joined-lines (path)
  (reroot path :prefix "_no_continued_lines__"))
;;;;FIXME::put the file prefix/suffix code somewhere? 
(defun cache-those-joined-lines (&optional (file *testpath*))
  (let ((original-path (path-for-original file)))
    ;;FIXME::better way to ensure things? a pipeline?
    (unless (file-exists-p original-path)
      (setf original-path (cache-those-originals file)))
    (let* ((file-lines (uiop:read-file-lines file))
	   (list (join-lines-list file-lines))
	   (path (path-for-joined-lines file)))
      (when *verbose*
	(format t "caching joined lines:~%for ~a ~%at ~a~%" file path))
      (with-open-file (output
		       path
		       :direction :output :if-exists :overwrite :if-does-not-exist :create)
	(let ((len (list-length list))
	      (count 0))
	  (dolist (line list)
	    (when (< 0 count (1- len))
	      (write-char #\Newline output))
	    (write-string line output)
	    (incf count))))
      path)))

(define-c-parse-rule //comment ()
  (progn-v #\/
	   #\/
	   (times (progn (! #\Newline)
			 (v character)))))

(define-c-parse-rule white-char-no-newline ()
  (|| #\Space #\tab))
(define-c-parse-rule whitespace-no-newline ()
  (postimes white-char-no-newline)
  nil)

(define-c-parse-rule directive ()
  (progn-v (times white-char-no-newline)
	   #\#
	   (stringy (times (progn (! #\Newline)
				  (v character))))))

(define-c-parse-rule thing ()
  (|| directive
      (progn
	(|| whitespace-no-newline
	    lex-yacc-multiline-comment
	    //comment
	    character)
	nil)))
;;FIXME:: non-consing esrap-liquid?
(defparameter *acc* nil)
(defun get-directives (&optional (fun 'per-iter) (text *text-test-file*))
  (catch 'out
    (let ((start 0))
      (loop (multiple-value-bind (directive place)
		(parse-with-garbage 'thing text :start start)
	      (when (eql 0 place)
		(throw 'out nil))
	      (when directive
		(funcall fun directive start place)
		)
	      (incf start place)))))
  (values))
(defun per-iter (directive start end)
  (terpri)
  (princ directive) (print (list start end))
  (push directive *acc*))

(defun path-for-cached-directive-intervals (path)
  (reroot path :prefix "_directive_interval__"))

(defun file-exists-p (&optional (path *testpath*))
  (probe-file path))

(defun cache-those-directives (&optional (path *testpath*))
  ;;depends on the lines being joined
  (let ((joined-lines (path-for-joined-lines path)))
    (unless (file-exists-p joined-lines)
      (setf joined-lines (cache-those-joined-lines path))
      #+nil
      (error "no connected lines file: ~a" joined-lines))
    (let ((text (alexandria:read-file-into-string joined-lines))
	  (cache-path (path-for-cached-directive-intervals path)))
      (with-open-file (output cache-path :direction :output :if-exists :overwrite :if-does-not-exist :create)
	(get-directives
	 (lambda (directive start end)
	   (when *verbose*
	     (format *standard-output* "~%caching: start: ~a end: ~a ~% ~a" start end directive))
	   (princ (list start end) output)
	   (write-char #\newline output))
	 text)))))

(defun get-cached-directive-intervals (&optional (path *testpath*))
  (uiop:with-safe-io-syntax ()
    (uiop:read-file-forms (path-for-cached-directive-intervals path))))
