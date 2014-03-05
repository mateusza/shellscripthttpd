shellscripthttpd
================

HTTPD written entirely in shell (works with Busybox)

Start with [ACME micro\_inetd](http://www.acme.com/software/micro_inetd/) or any other inetd.

##Features:

* works with inetd
* supports HTTP/1.0
* supports GET, POST and HEAD methods
* follows POST/Redirect/GET pattern
* single file
* exports request headers according to CGI standard: HTTP_

## built-in functions
* add\_route
* require\_POST
* redirect
* read\_post\_var
* \_e

## create own actions

Add following:

```
add\_route '^/hello/$' hello
action\_hello(){
    X=`wc -l < /etc/passwd`
}

view\_hello(){
    echo "<html>"
    echo "<p>lines in passwd: $X</p>"
    cat file.txt | \_e
    echo "</html>"
}
```

## start the HTTPD

    $ micro-inetd 8080 /path/to/httpd.sh

