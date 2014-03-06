#!/bin/sh

# copyright (C) 2014 Mateusz Adamowski <mateusz at adamowski dot pl>
#
# This code is public domain. You are free to use it anywhere you want.
# Please drop a line once you find it useful.
#
# Features:
#  * works with inetd
#  * supports HTTP/1.0
#  * support GET, POST and HEAD methods
#  * follows POST/Redirect/GET pattern
#  * single file
#  * exports request headers according to CGI standard: HTTP_
#
# initial settings

SERVER_VERSION="shellscripthttpd/0.2.0"
SERVER_PROTOCOL="HTTP/1.0"
CHARSET="UTF-8"
CONTENT_TYPE="text/html; charset=$CHARSET"

RESPONSE_HEADERS_FILE="/tmp/http-response-headers.$$.txt"
RESPONSE_FILE="/tmp/http-response.$$.txt"
REQUEST_HEADERS_FILE="/tmp/http-request-headers.$$.txt"
REQUEST_BODY="/tmp/http-request.$$.txt"
ROUTES_FILE="/tmp/http-routes.$$.txt"

WEBSOCKET_MAGIC_GUID="258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# functions

response_name(){
    [ "$1" = "101" ] && echo "Switching Protocols"
    [ "$1" = "200" ] && echo "OK"
    [ "$1" = "404" ] && echo "Not found"
    [ "$1" = "500" ] && echo "Internal Server Error"
    [ "$1" = "303" ] && echo "See other"
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
        response
        exit
    fi    
}

read_post_var(){
    local var
    var="$1"
    grep -o "\&$var=[^\&]\+" < $REQUEST_BODY | sed -e 's/.*=//' | urldecode
}

read_get_var(){
    local var
    var="$1"
    echo "&$QUERY_STRING&" | grep -o "\&$var=[^\&]\+" | sed -e 's/.*=//' | urldecode
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

response_websocket(){
    SERVER_PROTOCOL="HTTP/1.1"
    CODE="101"
    echo "$SERVER_PROTOCOL $CODE $( response_name $CODE )"
    cat "$RESPONSE_HEADERS_FILE"
    echo ""
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
    SHOW_RESPONSE="yes"
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %Z")
    add_header "Date" "$DATE"
    add_header "Server" "$SERVER_VERSION"
    if [ "$( echo "$HTTP_CONNECTION" | grep -o '\bUpgrade\b' )" = "Upgrade" ] && [ "$HTTP_UPGRADE" = "websocket" ]
    then
        prepare_websocket
        return
    fi
    add_header "Connection" "close"
    add_header "Content-Type" "$CONTENT_TYPE"
}

prepare_websocket(){
    SHOW_RESPONSE="no"
    CODE="101"
    add_header "Upgrade" "websocket"
    add_header "Connection" "upgrade"
    WEBSOCKET_TICKET="$( /usr/bin/printf "$( echo -n $HTTP_SEC_WEBSOCKET_KEY$WEBSOCKET_MAGIC_GUID | sha1sum | grep -o '[0-9a-f]\+' | sed -e 's/../\\x\0/g' )" | base64 )"
    add_header "Sec-WebSocket-Accept" "$WEBSOCKET_TICKET"
}

_e(){
    sed -e ' s_&_\&amp;_g; s_<_\&lt;_g; s_>_\&gt;_g; s_"_\&quot;_g; '"s_'_\&apos;_g"
}

run(){
    request
    prepare
    route
    [ "x$SHOW_RESPONSE" = "xyes" ] && response | awk 'sub("$", "\r")'
    cleanup
}

redirect(){
    REDIRECTION_LOCATION="$1"
    add_header "Location" "$REDIRECTION_LOCATION"
    VIEW="REDIRECT"
    CODE=303
}

view_ERROR500(){
    echo "<h1>ERROR 500</h1>"
}

view_ERROR404(){
    echo "<h1>404 Not found</h1>"
}

action_ERROR404(){
    true 
}

view_REDIRECT(){
    echo "<h1>redirecting... <code>$REDIRECTION_LOCATION</code></h1>"
}

#
# CUSTOM ACTIONS AND VIEWS
#

action_test1(){
    XXX="`date`"
}

action_source(){
   true 
}
action_say(){
    require_POST
    redirect '/'
    echo action | espeak
}

view_test1(){
    echo "<html>"
    echo "<h1>$XXX</h1>"
    echo "<pre>HTTP_HOST"
    echo "$( echo $HTTP_HOST | _e )</pre>"
    echo "<pre>HTTP_USER_AGENT"
    echo "$( echo $HTTP_USER_AGENT | _e )</pre>"
    echo "<table border=1>"
    while read -r h
    do
      echo "<tr>"
      echo "<td><code>"
      echo "$h" | grep -o '^[-A-Za-z]\+' | _e
      echo "</code></td>"
      echo "<td><code>"
      echo "$h" | sed -e 's/^.*: //' | _e 
      echo "</code></td></tr>"
    done < $REQUEST_HEADERS_FILE
    echo "</table>"
    echo "<h2><code>[$REQUEST_METHOD] [$SCRIPT_NAME] [$SERVER_PROTOCOL]</code></h2>"
    echo "<pre>params: $QUERY_STRING</pre>"
    echo "<a href='/source/'>Source</a>"
    echo "<form action='/x/say' method=POST>"
    echo "<input type=submit>"
    echo "</form>"
    echo "</html>"
}

view_source(){
    echo "<html>"
    echo "<textarea rows=10 cols=60>"
    cat httpd.sh | _e 
    echo "</textarea>"
    echo "</html>"
}

action_form1(){
    true
}

view_form1(){
    echo '<pre>'
    touch /tmp/chat.txt
    tail -20 /tmp/chat.txt | _e
    echo '</pre>'
    echo '<form method=POST action="save">'
    echo '<input name=a>'
    echo '<input name=bb>'
    echo '<input type=submit>'
    echo '</form>'
}

action_form1_save(){
    require_POST
    redirect '/form1/'
    a=$( read_post_var a )
    bb=$( read_post_var bb )
    echo "$a: $bb" >> /tmp/chat.txt
}

action_form2(){
    aa="$( read_get_var aa )"
    bb="$( read_get_var bb )"
    [ "x$aa" = "x" ] && aa=0
    [ "x$bb" = "x" ] && bb=0
    cc=$(( $aa + $bb ))
}

view_form2(){
cat <<EOF
<!doctype html>
<html>
<h1>form 2</h1>
<form action='.' method='GET'>
<input name='aa' value='$( echo $aa | _e )'> +
<input name='bb' value='$( echo $bb | _e )'>
<input type='submit' value='='>
<output>$cc</output>
</form>
</html>
EOF
}

action_ws(){
    true
}

view_ws(){
    cat wstest.html
}

action_wsconnect(){
    local message
    local random
    local lenhex

    response_websocket | awk 'sub("$", "\r")'
    for a in 1 2 1 3 1
    do
        random=`head -c 1 /dev/urandom | hexdump -v -e '1/1 "%u"'`
        message="RX: $( ifconfig wlan0 | grep "RX bytes" | grep -o '[0-9]\+' | head -1 )"
        lenhex=$( printf "%02x" "$( echo -n $message | wc -c )" )
        /usr/bin/printf "\x81\x$lenhex%s" "$message"
        sleep $a
    done 

    /usr/bin/printf "\x88\x00"

}

view_wsconnect(){
    true
}

##
## ROUTES
##

add_route '^/$'             'test1'
add_route '^/source/$'      'source'
add_route '^/x/say$'        'say'
add_route '^/form1/$'       'form1'
add_route '^/form1/save$'   'form1_save'
add_route '^/form2/$'       'form2'
add_route '^/ws/$'          'ws'
add_route '^/wsconnect/$'   'wsconnect'
##
## process the request
##

run

