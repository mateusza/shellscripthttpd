#!/bin/sh

# copyright (C) 2014 Mateusz Adamowski <mateusz at adamowski dot pl>
#
# This code is public domain. You are free to use it anywhere you want.
# Please drop a line once you find it useful.
#
# custom settings
TEMP_DIR="/tmp/ss"
SESSION_COOKIE_NAME="SessionId"
SESSION_LIFETIME="$(( 60 * 60 ))"
# initial settings

SERVER_SOFTWARE="shellscripthttpd"
SERVER_VERSION="0.4.0"
SERVER_PROTOCOL="HTTP/1.0"
CHARSET="UTF-8"
CONTENT_TYPE="text/html; charset=$CHARSET"

RESPONSE_HEADERS_FILE="$TEMP_DIR/http-response-headers.$$.txt"
RESPONSE_FILE="$TEMP_DIR/http-response.$$.txt"
REQUEST_HEADERS_FILE="$TEMP_DIR/http-request-headers.$$.txt"
REQUEST_BODY="$TEMP_DIR/http-request.$$.txt"
ROUTES_FILE="$TEMP_DIR/http-routes.$$.txt"
ERRORS_FILE="$TEMP_DIR/http-errors.$$.txt"

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

require_XSRF(){
    if [ "x$XSRF" != "x$( read_post_var XSRF )" ]
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
    rm -f "$ERRORS_FILE"
    [ "$( head -c 1 /dev/urandom | hexdump -e '1/1 "%u"' )" -lt "26" ] && session_cleanup_stale_files
}

session_cleanup_stale_files(){
    local currdate
    local filedate
    currdate=$( date +%s )
    ls "$TEMP_DIR" | grep 'session-.*-.*\.txt' | while read f
    do
        filedate=$( date +%s -r "$TEMP_DIR/$f" )
        if [ "$(( $currdate - $filedate > $SESSION_LIFETIME ))" -eq "1" ]
        then
            rm "$TEMP_DIR/$f"
        fi
    done

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
    
    if [ "x$REQUEST_METHOD" != "x" ]
    then
        session_load_cookie
        session_check_cookie
        xsrf_init
    fi
    
#    add_header "X-Test" "$REQUEST_METHOD $REQUEST_URI $CLIENT_PROTOCOL"
}

session_load_cookie(){
    SESSION_ID="$( echo "$HTTP_COOKIE" | grep -o "\b$SESSION_COOKIE_NAME=[^;]\+" | sed -e 's/^.\+=//' )"
}

session_check_cookie(){
    if echo "$SESSION_ID" | grep "^[0-9a-f]\{32\}$" > /dev/null
    then
        true
    else
        session_gen_id
        EXPIRES=$( date +"%a, %d %b %Y %H:%M:%S %Z" -d @$(( `date +%s` + $SESSION_LIFETIME )) )
        add_header "Set-Cookie" "$SESSION_COOKIE_NAME=$SESSION_ID; Expires=$EXPIRES; HttpOnly; Path=/"
    fi
}

session_gen_id(){
    SESSION_ID=$( head -c 128 /dev/urandom | md5sum | cut -d " " -f 1 )
}

session_set_value(){
    cat > "$TEMP_DIR/session-$SESSION_ID-${1}.txt"
}

session_unset_value(){
    [ -e "$TEMP_DIR/session-$SESSION_ID-${1}.txt" ] && rm "$TEMP_DIR/session-$SESSION_ID-${1}.txt"
}

session_get_value(){
    [ -e "$TEMP_DIR/session-$SESSION_ID-${1}.txt" ] && cat "$TEMP_DIR/session-$SESSION_ID-${1}.txt"
}

session_regenerate_id(){
    local old_id
    local newname
    old_id="$SESSION_ID"
    session_gen_id
    for filename in $TEMP_DIR/session-$old_id-*.txt
    do
        newname=$( echo $filename | sed -e "s/$old_id/$SESSION_ID/" )
        mv "$filename" "$newname"
    done
    add_header "Set-Cookie" "$SESSION_COOKIE_NAME=$SESSION_ID; HttpOnly; Path=/"
}

xsrf_init(){
    XSRF="$( session_get_value XSRF )"
    if [ "x$XSRF" = "x" ]
    then
        XSRF="$( head -c 32 /dev/urandom | md5sum | cut -d " " -f 1 )"
        echo $XSRF | session_set_value XSRF
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
    add_header "Content-Type" "$CONTENT_TYPE"
}

urldecode(){
      /usr/bin/printf "$(sed 's/+/ /g;s/%\(..\)/\\x\1/g;')"
}

prepare(){
    DATE=$(date +"%a, %d %b %Y %H:%M:%S %Z")
    add_header "Date" "$DATE"
    add_header "Connection" "close"
    add_header "Server" "$SERVER_VERSION"
}

_e(){
    sed -e ' s_&_\&amp;_g; s_<_\&lt;_g; s_>_\&gt;_g; s_"_\&quot;_g; '"s_'_\&apos;_g"
}

run(){
    request
    prepare
    route 2> "$ERRORS_FILE"
    handle_errors
    response | awk 'sub("$", "\r")'
    cleanup
}

handle_errors(){
    [ -s "$ERRORS_FILE" ] || return
    VIEW="ERROR500"
    CODE="500"
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
    echo "<h2>Error:</h2>"
    echo "<pre style='padding: 10px; background-color: #eee;'>"
    cat "$ERRORS_FILE" | _e
    echo "</pre>"
    echo "<h2>request headers &amp; content</h2>"
    echo "<pre style='padding: 10px; background-color: #eee;'>"
    echo -n "$REQUEST_METHOD $REQUEST_URI $CLIENT_PROTOCOL" | _e
    cat "$REQUEST_HEADERS_FILE" | _e
    echo 
    cat "$REQUEST_BODY" | _e
    echo "</pre>"
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
    githublink="https://github.com/mateusza/shellscripthttpd"
    os=$( uname -a )
}

view_index(){
cat <<EOF
<!doctype html>
<html>
<head>
<title>Hello from $name</title>
<style> 
body { background-color: #242; padding: 50px; font-size: 150%; color: #fff; font-family: monospace; text-shadow: #000 1px 1px 1px; text-align: center; } 
pre { text-align: left; } 
::selection { background-color: #4f4; color: #000; text-shadow: #242; }
a { color: #f90; }
</style>
</head>
<body>
<h1>Hello world!</h1>
<h2>This is front page of your <b>$SERVER_SOFTWARE</b> instance.</h2>
<p>You can browse the source code on <a href='$githublink'>GitHub</a>.</p>
<p><small>
Running on: <tt>$os</tt>
</small></p>
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

