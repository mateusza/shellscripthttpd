shellscripthttpd
================

HTTPD written entirely in shell (works with Busybox)

Start with [ACME micro\_inetd](http://www.acme.com/software/micro_inetd/) or any other inetd.

##Features:

###works with inetd

  micro-inetd 8080 /path/to/httpd.sh

### supports HTTP/1.0
### supports GET, POST and HEAD methods
### follows POST/Redirect/GET pattern
### single file
### exports request headers according to CGI standard: HTTP_

## built-in functions
### add\_route

