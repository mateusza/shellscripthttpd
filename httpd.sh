#!/bin/sh

# copyright (C) 2014 Mateusz Adamowski <mateusz at adamowski dot pl>
#
# This code is public domain. You are free to use it anywhere you want.
# Please drop a line once you find it useful.
#
# custom settings
TEMP_DIR="/tmp/ss"

# initial settings

SERVER_SOFTWARE="shellscripthttpd"
SERVER_VERSION="0.3.0"
SERVER_PROTOCOL="HTTP/1.0"
CHARSET="UTF-8"
CONTENT_TYPE="text/html; charset=$CHARSET"

RESPONSE_HEADERS_FILE="$TEMP_DIR/http-response-headers.$$.txt"
RESPONSE_FILE="$TEMP_DIR/http-response.$$.txt"
REQUEST_HEADERS_FILE="$TEMP_DIR/http-request-headers.$$.txt"
REQUEST_BODY="$TEMP_DIR/http-request.$$.txt"
ROUTES_FILE="$TEMP_DIR/http-routes.$$.txt"

SERVER_NAME="$SERVER_SOFTWARE/$SERVER_VERSION"

# functions

response_name(){
    [ "$1" = "200" ] && echo "OK"
    [ "$1" = "404" ] && echo "Not found"
    [ "$1" = "303" ] && echo "See other"
    [ "$1" = "500" ] && echo "Internal Server Error"
}

add_header(){
    echo "$1: $2" >> $RESPONSE_HEADERS_FILE
}

add_route(){
    echo "$1 $2" >> $ROUTES_FILE
}

require_POST(){
    if [ "$REQUEST_METHOD" != "POST" ]
    then
        CODE="500"
        VIEW="ERROR500"
        return 1
    fi    
}

read_post_var(){
    grep -o "\&$1=[^\&]\+" < $REQUEST_BODY | sed -e 's/.*=//' | urldecode
}

read_get_var(){
    echo "&$QUERY_STRING&" | grep -o "\&$1=[^\&]\+" | sed -e 's/.*=//' | urldecode
}

cleanup(){
    rm -f "$RESPONSE_HEADERS_FILE"
    rm -f "$REQUEST_HEADERS_FILE"
    rm -f "$ROUTES_FILE"
    rm -f "$RESPONSE_FILE"
    rm -f "$REQUEST_BODY"
}

request(){
    local hname
    local hvalue

    mkdir -p "$TEMP_DIR"

    touch "$RESPONSE_HEADERS_FILE"
    touch "$REQUEST_HEADERS_FILE"
    touch "$ROUTES_FILE"
    touch "$RESPONSE_FILE"
    touch "$REQUEST_BODY"

    read REQUEST_METHOD REQUEST_URI CLIENT_PROTOCOL
    SCRIPT_NAME="$( echo "$REQUEST_URI" | grep -o '^[^\?]\+' )"

    if echo "$REQUEST_URI" | grep '\?' > /dev/null
    then
        QUERY_STRING="$( echo "$REQUEST_URI" | sed -e 's/^.*?//' )"
    else
        QUERY_STRING=""
    fi

    while read -r line
    do
        line=$( echo $line | tr -d '\r' )
        [ -z "$line" ] && break
        echo "$line" >> $REQUEST_HEADERS_FILE
        hname="$( echo $line | grep -o '^[-A-Za-z]\+' | tr a-z A-Z | sed -e 's/-/_/g' )"
        hvalue="$( echo $line | sed -e 's/^.*: //' )"
        eval "HTTP_$hname='$hvalue'"
    done

    if [ "x$HTTP_CONTENT_LENGTH" != "x" ]
    then
        echo -n '&' > $REQUEST_BODY
        head -c $HTTP_CONTENT_LENGTH >> $REQUEST_BODY
        echo -n '&' >> $REQUEST_BODY
    fi

}

response(){
    view_$VIEW > $RESPONSE_FILE
    add_header "Content-Length" "$( awk 'sub("$", "\r")' < $RESPONSE_FILE | wc -c )"

    echo "$SERVER_PROTOCOL $CODE $( response_name $CODE )"
    cat "$RESPONSE_HEADERS_FILE"
    echo ""
    [ "$REQUEST_METHOD" = "HEAD" ] && return
    cat "$RESPONSE_FILE"
}

route(){
    while read route action
    do
        if echo "$SCRIPT_NAME" | grep -o "$route" > /dev/null
        then
            CODE=200
            ACTION="$action"
            break
        fi
    done < $ROUTES_FILE

    VIEW=$ACTION
    if [ "x$CODE" = "x" ]
    then
        CODE="404"
        ACTION=ERROR404
        VIEW=ERROR404
    fi
    action_$ACTION
}

urldecode(){
      /usr/bin/printf "$(sed 's/+/ /g;s/%\(..\)/\\x\1/g;')"
}

prepare(){
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %Z")
    add_header "Date" "$DATE"
    add_header "Connection" "close"
    add_header "Server" "$SERVER_VERSION"
    add_header "Content-Type" "$CONTENT_TYPE"
}

_e(){
    sed -e ' s_&_\&amp;_g; s_<_\&lt;_g; s_>_\&gt;_g; s_"_\&quot;_g; '"s_'_\&apos;_g"
}

run(){
    request
    prepare
    route
    response | awk 'sub("$", "\r")'
    cleanup
}

redirect(){
    REDIRECTION_LOCATION="$1"
    add_header "Location" "$REDIRECTION_LOCATION"
    VIEW="REDIRECT"
    CODE=303
}

template_server_signature(){
    echo "<hr><p>$SERVER_NAME</p>"
}

view_ERROR500(){
    echo "<title>Internal Server Error</title>"
    echo "<h1>Internal Server Error</h1>"
    echo "<p>Something wrong happened.</p>"
    template_server_signature
}

view_ERROR404(){
    echo "<title>404 Not found</title>"
    echo "<h1>404 Not found</h1>"
    template_server_signature
}

action_ERROR404(){
    true 
}

view_REDIRECT(){
    echo "<h1>redirecting... <code>$REDIRECTION_LOCATION</code></h1>"
    template_server_signature
}

#
# CUSTOM ACTIONS AND VIEWS
#

action_index(){
    name="Mateusz"
    os=$( uname -a )
}

view_index(){
cat <<EOF
<!doctype html>
<html>
<head>
<title>Hello from $name</title>
<style> 
body { background-color: #010; padding: 50px; font-size: 150%; color: #de9; font-family: sans-serif; text-shadow: #888 1px 1px 1px; text-align: center; } 
pre { text-align: left; } 
::selection { background-color: #4f4; color: #000; text-shadow: #242; }
</style>
</head>
<body>
<h1>Hello world!</h1>
<h2>This is front page of your <b>$SERVER_SOFTWARE</b> instance.</h2>
<p>
We are running on: <tt>$os</tt><br>
<br>
</p>
$( template_server_signature )
</body>
</html>
EOF
}

##
## ROUTES
##

add_route '^/$'             'index'

##
## process the request
##

run

