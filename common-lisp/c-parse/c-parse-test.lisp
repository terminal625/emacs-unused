(in-package :c-parse)

(fiveam:in-suite* c-parse)

(defun run-tests ()
  (let ((results (fiveam:run 'c-parse)))
    (fiveam:explain! results)
    (unless (fiveam:results-status results)
      (error "Tests failed."))))

(defun regex-character-class-to-esrap-liquid (regex)
  (lex-rule-dump (parse-with-garbage 'lex-rule-character-class regex)))
(fiveam:test what
  (fiveam:is (char= (c-parse-parse 'lex-char-or-escaped-char "\\\\")
		    #\\))
  (fiveam:is (char= (c-parse-parse 'lex-char-or-escaped-char "\\t")
		    #\Tab))
  (fiveam:is (string= (c-parse-parse 'lex-string "\"234\\t234\"")
		      "234	234"))
  (fiveam:is (string= (char-to-escaped-char #\Newline)
		      "\\n"))
  (fiveam:is (string= (char-to-escaped-char #\s)
		      "s"))
  (fiveam:is (char= (parse-with-garbage
		     (regex-character-class-to-esrap-liquid "[^a-zA-Z_0-9]")
		     "$"))
	     #\$)
  (fiveam:is (char= (parse-with-garbage
		     (regex-character-class-to-esrap-liquid "[a-zA-Z_0-9]")
		     "S"))
	     #\S))

(defmacro parse-with-garbage (rule text &rest rest &key &allow-other-keys)
  `(c-parse-parse ,rule ,text :junk-allowed t ,@rest))

(defun test-parse-rules (&optional (rules *lex-rules-lines*))
  (mapcar (lambda (text)
	    (parse-with-garbage 'lex-rule-start text))
	  rules))

(define-c-parse-rule lex-line-def ()
  (cap :def-name (v lex-token-string))
  (v whitespace)
  ;;(cap :rule (v lex-rule-start))
  (list
   (recap :def-name)
   (stringify (postimes character))))
(defun spec-lex-rule-rule (spec)
  (second spec))
(defun spec-lex-rule-name (spec)
  (first spec))

(define-c-parse-rule lex-line-rule ()
  (prog1-v lex-rule-start
	   whitespace))

;;*defs* is a list of ("name" "rule")
(defun split-lex-line-def (&optional (item "NS [a-zA-Z_]"))
  (destructuring-bind (name rule-string) (parse-with-garbage 'lex-line-def item)
    (list name (parse-with-garbage 'lex-rule-start rule-string))))

(defun split-lex-line-rule (&optional (string "asd[a-zA-Z_]fasd   {return; /* */}"))
  (multiple-value-bind (form end)
      (parse-with-garbage 'lex-line-rule string)
    ;;;FIXME::assumes that } terminates the line, which for this file does
    (let ((last-bracket (position #\} string :from-end t)))
      (list form
	    (subseq string (1+ end)
		    last-bracket)))))

;;run split-lex-2 to set the dynamic variables
(defun test-lines (&optional (rule 'lex-rule-start) (rules *lex-rules-lines*))
  (let ((correct 0)
	(wrong 0))
    (terpri)
    (mapc (lambda (text)
	    (let* ((obj (parse-with-garbage rule text))
		   (a (princ-to-string 
		       obj)))
	      (flet ((dump ()
		       (princ a)
		       (terpri)
		       (princ text)
		       (terpri)))
		(cond ((string-a-prefix-b-p
			a
			text)
		       (progn
			 (format t "~%same:~%") 
			 (dump))
		       (incf correct))
		      (t
		       (incf wrong)
		       (format t "~%DIFFERENT:~%")
		       (dump)
	;	       (inspect obj)
		       )))))
	  rules)
    (format t "correct: ~a wrong: ~a~%" correct wrong)
    (list wrong correct)))

(defun teststuff ()
  (test-lines)
  (test-lines 'lex-rule-start
	      (mapcar 'spec-lex-rule-rule
		      (mapcar
		       (lambda (item)
			 (parse-with-garbage 'lex-line-def item))
		       *lex-definitions-lines*))))

;;(string-a-prefix-b-p "a" "ab") -> T
;;(string-a-prefix-b-p "ac" "ab") -> 
(defun string-a-prefix-b-p (a b)
  "test whether string a is a prefix of b"
  (when (> (length a)
	   (length b))
    ;;(error "a is longer than b")
    (return-from string-a-prefix-b-p nil)
    )
  (dotimes (index (length a))
    (unless (char= (aref a index)
		   (aref b index))
      (return-from string-a-prefix-b-p nil)))
  t)

(defun setup ()
  (split-lex2)
  (split-yacc2)
  (values))
(setup) ;;fixme:: better load setup
(defun test-things (&optional not-pretty)
  (let ((*print-raw* not-pretty))
    (teststuff))
  (values))

(defparameter *processed-definitions* (mapcar 'split-lex-line-def
					      *lex-definitions-lines*))
(defun pipeline (&optional (def "hello [90]"))
  (compile-to-esrap-liquid (split-lex-line-def def)))
(defun compile-to-esrap-liquid (item)
  (destructuring-bind (name rule) item
    (let ((form `(define-c-parse-rule ,(find-lex-symbol name) ()
		   ,(lex-rule-dump rule))))
      form)))
(defun load-processed-definitions ()
  `(progn
     ,@(mapcar
	'compile-to-esrap-liquid
	*processed-definitions*)))
(defparameter *processed-rules* (mapcar 'split-lex-line-rule
					*lex-rules-lines*))
(defparameter *syms* nil)
(defun bar ()
  (let* ((iota (alexandria:iota (length *processed-rules*)))
	 (syms (mapcar 'sym-name iota)))
    (setf *syms* syms)
    `(progn       
       ,@(mapcar (lambda (name x)
		   (let ((what-fun (parse-lex-def (second x))))
		     (utility:with-gensyms (parse-result)
		       `(define-c-parse-rule ,name ,()
			  (let ((,parse-result ,(lex-rule-dump (first x))))
			    (list
			     ,parse-result
			     ,what-fun
			     ,(flet ((convert-to-token (x)
				       (yacc-symbol x)))
				(case what-fun
				  (:comment
				   `(progn (v lex-comment-end)
					   ,(convert-to-token nil)))
				  (:check-type  ;;:check-type
				   `(cond (nil ;;FIXME::actually check for enums
					   (quote ,(convert-to-token "ENUMERATION_CONSTANT")))
					  ((member (print (stringy ,parse-result))
						   *typedef-env* :test 'string=)
					   (quote ,(convert-to-token "TYPEDEF_NAME")))
					  (t
					   (quote
					    ,(convert-to-token "IDENTIFIER"))))
				   ;;FIXME::detect typedefs and enums
				   )
				  (otherwise `(quote ,(convert-to-token what-fun)))))))))))
		 syms
		 *processed-rules*)
       (define-c-parse-rule lexer-foo ()
	 ;;why? it was taking around 13 to 20 seconds to compile
	 ;;most-full-parse
	 (v reimplemented-most-full-parse *syms*)))))

(in-package :esrap-liquid)
;;change sort ->stable-sort nreverse
(defmacro esrap-liquid::most-full-parse2 (clauses)
  (once-only (clauses)
    (with-gensyms (g!-result g!-the-length g!-successful-parses
			     ;;g!-parse-errors
			     b!-max-length
			     b!-max-result
			     b!-max-cap-stash
			     b!-list-iterator)
      `(tracing-level
	 (if-debug "MOST-FULL-PARSE")
	 (multiple-value-bind (,g!-result ,g!-the-length)
	   (let (;;,g!-parse-errors
		 ,b!-max-result
		 ,g!-successful-parses
		 ,b!-max-cap-stash
		 (,b!-max-length 0))
	     (dolist (,b!-list-iterator ,clauses)
	       (the-position-boundary
		 (print-iter-state)
		 (with-saved-iter-state (the-iter)
		   (with-fresh-cap-stash
		     (handler-case (descend-with-rule ,b!-list-iterator)
		       (internal-esrap-error (e)
			 (declare (ignorable e))
			 (restore-iter-state)
			 ;;(push e ,g!-parse-errors)
			 )
		       (:no-error (res)
			 (restore-iter-state)
			 (when (> the-length ,b!-max-length)
			   (setf ,b!-max-length the-length)
			   (setf ,g!-successful-parses t)
			   (setf ,b!-max-result res)
			   (setf ,b!-max-cap-stash *cap-stash*))
			 #+nil
			 (push (list res the-length *cap-stash*)
			       ,g!-successful-parses)))))))
	     (if ,g!-successful-parses
		 (multiple-value-bind (res length stash) (values ,b!-max-result
								 ,b!-max-length
								 ,b!-max-cap-stash)
		   ,(propagate-cap-stash-upwards '*cap-stash* 'stash nil)
		   (fast-forward the-iter length)
		   (values res length))
		 (progn (if-debug "|| before failing P ~a L ~a" the-position the-length)
			(fail-parse "MOST-FULL-PARSE failed."))))
	   (if-debug "MOST-FULL-PARSE aftermath ~a ~a" the-length ,g!-the-length)
	   (incf the-length ,g!-the-length)
	   ,g!-result)))))
(in-package :c-parse)

(define-c-parse-rule reimplemented-most-full-parse (syms)
  (esrap-liquid::most-full-parse2 syms))

(defun stringy (tree)
  ;;turn a tree of nil's and characters produced by esrap-liquid into a
  ;;string
  (with-output-to-string (stream)
    (labels ((rec (node)
	       (when node
		 (if (atom node)
		     (princ node stream)
		     (progn (rec (car node))
			    (rec (cdr node)))))))
      (rec tree))))

(defun sym-name (x)
  (find-lex-symbol (format nil "LEX-GENERATED~a" x)))

(defun eval-lexer ()
  (print "loading defs:")
  (eval (load-processed-definitions))
  (print "loading rules:")
  (eval (bar)))

;;;yacc and lex comments are the same?
(define-c-parse-rule lex-yacc-multiline-comment ()
  (progn-v
   "/*"
   lex-comment-end))
(define-c-parse-rule lex-comment-end-token ()
  (progn (v #\*)
	 (v #\/)))
(define-c-parse-rule lex-comment-end ()
  (prog1 (postimes
	  (progn (! lex-comment-end-token)
		 (v character))
	  )
    (v lex-comment-end-token))
   nil
  )
(defun parse-lex-def (text)
  (parse-with-garbage 'ad-hoc-lex-read-file text))

;;;FIXME:: fragile hack that picks out two irregular cases?
;;;or is this how to do it?
(define-c-parse-rule ad-hoc-lex-read-file ()
  (|| (progn (? whitespace)
	     (v "comment();")
	     :comment)
      (progn
	(? whitespace)
	(v "return check_type();")
	:check-type)
      lex-read-return))

(define-c-parse-rule lex-read-return ()
  (? whitespace)
  (v "return")
  (? whitespace)
  (cap :thing (|| lex-read-char
		  lex-read-token
		  lex-token-string))
  (? whitespace)
  (v #\;)
  (recap :thing))

(define-c-parse-rule lex-read-char ()
  (progm #\'
	 character
	 #\'))
(define-c-parse-rule lex-read-token ()
  (progm #\(
	 lex-token-string
	 #\)))
;;(string-thing lex-token-type yacc-token-type)
(defun lex (string &optional (stream *standard-output*))
  (let ((start 0))
    (loop
       (multiple-value-bind (result len)
	   (parse-with-garbage 'lexer-foo string :start start)
	 (when (zerop len)
	   (return))
	 (destructuring-bind (string-thing ignorable yacc-token-type) result
	   (declare (ignorable string-thing yacc-token-type ignorable))
	   ;;(write-char (char-code-object yacc-token-type) stream)
	   (princ (stringy (car result)) stream)
	   )
	 (incf start len)))))

(defun lex2 (string)
  (with-output-to-string (stream)
    (lex string stream)))

(defparameter *file1* (alexandria:read-file-into-string
		       #+nl
		       "/home/imac/install/src/pycparser-master/examples/c_files/funky.c"
		       "/home/imac/install/src/pycparser-master/examples/c_files/hash.c"))

;;FIXME:: hack -> using unicode characters to represent tokens, thus simplifyng tokens
#+nil
(progn
  (defparameter *char-code-pointer* nil)
  (defparameter *objects-to-characters* nil)
  (defun reset-char-code-object-table ()
    (setf *char-code-pointer* 32)
    (setf *objects-to-characters* (make-hash-table :test 'equal)))
  (reset-char-code-object-table)
  (defun char-code-object (obj)
    (let ((there? (gethash obj *objects-to-characters*)))
      (unless there?
	(let ((new (code-char *char-code-pointer*)))
	  (setf (gethash obj *objects-to-characters*)
		new)
	  (setf there? new))
	(incf *char-code-pointer*))
      there?)))

(define-c-parse-rule left-recursion? ()
  (progn-v left-recursion?
	   #\(
	   character
	   #\)))
