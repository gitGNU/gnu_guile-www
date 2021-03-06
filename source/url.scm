;;; (www url) --- URL manipulation tools

;; Copyright (C) 2008, 2009, 2012 Thien-Thi Nguyen
;; Copyright (C) 1997, 2001, 2002, 2003, 2004, 2005,
;;   2006 Free Software Foundation, Inc.
;;
;; This file is part of Guile-WWW.
;;
;; Guile-WWW is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; Guile-WWW is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public
;; License along with Guile-WWW; see the file COPYING.  If not,
;; write to the Free Software Foundation, Inc., 51 Franklin Street,
;; Fifth Floor, Boston, MA  02110-1301  USA

;;; Code:

;; TODO:
;;   * make URL parsing smarter.  This is good for most TCP/IP-based
;;     URL schemes, but parsing is actually specific to each URL scheme.
;;   * fill out url:encode, include facilities for URL-scheme-specific
;;     encoding methods (e.g. a url-scheme-reserved-char-alist)

(define-module (www url)
  #:export (url:scheme
            url:address url:unknown
            url:user url:host url:port url:path
            url:make
            url:make-http url:make-ftp url:make-mailto
            url:parse url:unparse
            url:decode url:encode)
  #:use-module (www url-coding)
  #:use-module ((srfi srfi-13) #:select (substring/shared
                                         string-index
                                         string-take
                                         string-prefix?))
  #:use-module ((ice-9 regex) #:select (match:substring
                                        match:start)))

;; Extract and return the "scheme" portion of a @var{url} object.
;; @code{url:scheme} is an unfortunate term, but it is the technical
;; name for that portion of the URL according to RFC 1738.  Sigh.
;;
(define (url:scheme url)  (vector-ref url 0))

;; Extract and return the "address" portion of the @var{url} object.
;;
(define (url:address url) (vector-ref url 1))

;; Extract and return the "unknown" portion of the @var{url} object.
;;
(define (url:unknown url) (vector-ref url 1))

;; Extract and return the "user" portion of the @var{url} object.
;;
(define (url:user url)    (vector-ref url 1))

;; Extract and return the "host" portion of the @var{url} object.
;;
(define (url:host url)    (vector-ref url 2))

;; Extract and return the "port" portion of the @var{url} object.
;;
(define (url:port url)    (vector-ref url 3))

;; Extract and return the "path" portion of the @var{url} object.
;;
(define (url:path url)    (vector-ref url 4))

;; Construct a url object with specific @var{scheme} and other @var{args}.
;; The number and meaning of @var{args} depends on the @var{scheme}.
;;
(define (url:make scheme . args)
  (apply vector scheme args))

;; Construct a HTTP-specific url object with
;; @var{host}, @var{port} and @var{path} portions.
;;
(define (url:make-http host port path)
  (vector 'http #f host port path))

;; Construct a FTP-specific url object with
;; @var{user}, @var{host}, @var{port} and @var{path} portions.
;;
(define (url:make-ftp user host port path)
  (vector 'ftp user host port path))

;; Construct a mailto-specific url object with
;; an @var{address} portion.
;;
(define (url:make-mailto address)
  (vector 'mailto address))

(define parse-http
  (let ((port-rx (make-regexp ":[0-9]+$")))
    ;; parse-http
    (lambda (string)

      (define (maybe pred)
        (string-index string pred))

      (define (after pos)
        (substring/shared string (1+ pos)))

      (define (before pos)
        (string-take string pos))

      ;; Whittle down ‘string’...
      (let ((user #f) (host #f) (port #f) (path #f))

        ;; ...removing (optional) ‘path’ on the right...
        (cond ((maybe #\/)
               => (lambda (pos)
                    (set! path (after pos))
                    (set! string (before pos)))))

        ;; ...removing (optional) ‘user’ on the left...
        (cond ((maybe #\@)
               => (lambda (pos)
                    (set! user (before pos))
                    (set! string (after pos)))))

        ;; ...removing (optional) ‘port’ on the right...
        (cond ((regexp-exec port-rx string)
               => (lambda (m)
                    (let ((pos (match:start m)))
                      (set! port (string->number (after pos)))
                      (set! string (before pos))))))

        ;; ...leaving it to represent ‘host’ (maybe).
        (or (string-null? string)
            (set! host string))

        ;; rv
        (url:make 'http user host port path)))))

(define parse-ftp
  (let ((rx (make-regexp "^(([^@:/]+)@)?([^:/]+)(:([0-9]+))?(/(.*))?$")))
    (lambda (string)
      (let ((m (regexp-exec rx string)))
        (url:make-ftp (match:substring m 2)
                      (match:substring m 3)
                      (cond ((match:substring m 5) => string->number)
                            (else #f))
                      (match:substring m 7))))))

;; Parse @var{string} and return a url object, with one of the
;; following "schemes": HTTP, FTP, mailto, unknown.
;;
(define (url:parse string)
  (define (try prefix ok)
    (and (string-prefix? prefix string)
         (ok (substring/shared string (string-length prefix)))))
  (or (try "http://" parse-http)
      (try "ftp://"  parse-ftp)
      (try "mailto:" url:make-mailto)
      (url:make 'unknown string)))

;; Return the @var{url} object formatted as a string.
;; Note: The username portion is not included!
;;
(define (url:unparse url)
  (define (fs s . args)
    (apply simple-format #f s args))
  (define (pathy scheme username url)   ; username not used!
    (fs "~A://~A~A~A"
        scheme
        (url:host url)
        (cond ((url:port url) => (lambda (port) (fs ":~A" port)))
              (else ""))
        (cond ((url:path url) => (lambda (path) (fs "/~A" path)))
              (else ""))))
  (case (url:scheme url)
    ((http) (pathy 'http #f url))
    ((ftp)  (pathy 'ftp (url:user url) url))
    ((mailto) (fs "mailto:~A" (url:address url)))
    ((unknown) (url:unknown url))))

;; Re-export @code{url-coding:decode}.  @xref{url-coding}.
;;
(define (url:decode str)
  (url-coding:decode str))

;; Re-export @code{url-coding:encode}.  @xref{url-coding}.
;;
(define (url:encode str reserved-chars)
  (url-coding:encode str reserved-chars))

;;; (www url) ends here
