#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154

source ./ols.conf

mkdir -p "$SERVERROOT" >/dev/null 2>&1

groupadd unyweb
unyweb_gid=$(grep "^unyweb:" /etc/group | awk -F : '{ print $3; }')
useradd -g "$unyweb_gid" -d / -r -s /sbin/nologin unyweb
usermod -a -G unyweb unyweb

VERSION="$(cat VERSION)"

chown "$SDIR_OWN" "$SERVERROOT"

function util_mkdir {
    OWNER=$1
    PERM=$2
    shift
    shift
    for arg; do
        if [ ! -d "$SERVERROOT/$arg" ]; then
            mkdir "$SERVERROOT/$arg"
        fi
        chown "$OWNER" "$SERVERROOT/$arg"
        chmod "$PERM" "$SERVERROOT/$arg"
    done
}
function util_cpfile {
    OWNER=$1
    PERM=$2
    shift
    shift
    for arg; do
        if [ -f "$arg" ]; then
            cp -f "$arg" "$SERVERROOT/$arg"
            chown "$OWNER" "$SERVERROOT/$arg"
            chmod "$PERM" "$SERVERROOT/$arg"
        fi
    done
}
function util_ccpfile {
    OWNER=$1
    PERM=$2
    shift
    shift
    for arg; do
        if [ ! -f "$SERVERROOT/$arg" ] && [ -f "$arg" ]; then
            cp "$arg" "$SERVERROOT/$arg"
        fi
        if [ -f "$SERVERROOT/$arg" ]; then
            chown "$OWNER" "$SERVERROOT/$arg"
            chmod "$PERM" "$SERVERROOT/$arg"
        fi
    done
}
function util_cpdir {
    OWNER=$1
    PERM=$2
    shift
    shift
    for arg; do
        cp -R "$arg/"* "$SERVERROOT/$arg/"
        chown -R "$OWNER" "$SERVERROOT/$arg/"*
    done
}
function util_cp_htaccess {
    OWNER=$1
    PERM=$2
    arg=$3
    cp -R "$arg/".htaccess "$SERVERROOT/$arg/"
    chown -R "$OWNER" "$SERVERROOT/$arg/".htaccess
}

DIR_MOD=755
SDIR_MOD=700
EXEC_MOD=555
CONF_MOD=600
DOC_MOD=644

DIR_OWN="unyweb:unyweb"
CONF_OWN="lsadm:lsadm"
SDIR_OWN="root:root"
LOGDIR_OWN="root:unyweb"

chgrp unyweb admin/tmp admin/cgid cgid
chmod g+x admin/tmp admin/cgid cgid

chown root:root autoupdate tmp cachedata gdata Example     #SDIR_OWN
chown root:unyweb logs admin/logs                          #LOGDIR_OWN
chown unyweb:unyweb tmp/ocspcache cachedata autoupdate tmp #DIR_OWN

chmod 755 autoupdate tmp cachedata gdata Example #DIR_MOD
chmod 750 logs admin/logs                        #NO_VARIABLE

chown -R root:root admin lsrecaptcha fcgi-bin add-ons                         #SDIR_OWN
chown -R lsadm:lsadm conf share/autoindex admin/conf admin/tmp conf/templates #CONF_OWN

chmod -R 644 admin/conf admin/tmp cgid admin/cgid admin/cgid/secret #SDIR_MOD
chmod -R 755 admin lsrecaptcha fcgi-bin                             #DIR_MOD
chmod -R 555 admin lsrecaptcha fcgi-bin                             #EXEC_MOD
chmod -R 644 add-ons share/autoindex admin/misc                     #DOC_MOD
chmod -R 600 admin/conf conf/templates                              #CONF_MOD

util_cpfile "$CONF_OWN" $CONF_MOD admin/conf/php.ini #admin/conf/${SSL_HOSTNAME}.key admin/conf/${SSL_HOSTNAME}.crt
util_cpfile "$CONF_OWN" $CONF_MOD conf/httpd_config.conf conf/mime.properties conf/httpd_config.conf
util_cpdir "$CONF_OWN" $CONF_MOD conf/vhosts/Example
util_mkdir "$SDIR_OWN" $DIR_MOD Example/html Example/cgi-bin
util_cpdir "$SDIR_OWN" $DOC_MOD Example/html Example/cgi-bin
util_cp_htaccess "$SDIR_OWN" $DOC_MOD Example/html

chown -R unyweb:unyweb "$SERVERROOT/conf/"

chmod -R 0750 "$SERVERROOT/conf/"

chmod 0600 "$SERVERROOT/conf/httpd_config.conf"
chmod 0600 "$SERVERROOT/conf/vhosts/Example/vhconf.conf"

#util_cpfile "$CONF_OWN" $DOC_MOD conf/${SSL_HOSTNAME}.crt
#util_cpfile "$CONF_OWN" $DOC_MOD conf/${SSL_HOSTNAME}.key

util_mkdir "$DIR_OWN" $DIR_MOD Example/logs Example/fcgi-bin
util_cpdir "$SDIR_OWN" $DOC_MOD admin/html."$VERSION"
rm -rf "$SERVERROOT"/admin/html
ln -sf ./html."$VERSION" "$SERVERROOT"/admin/html

util_cpfile "$SDIR_OWN" $EXEC_MOD bin/updateagent
util_cpfile "$SDIR_OWN" $EXEC_MOD bin/wswatch.sh
util_cpfile "$SDIR_OWN" $EXEC_MOD bin/unmount_ns
util_cpfile "$SDIR_OWN" $EXEC_MOD bin/lswsctrl bin/openlitespeed

ln -sf ./openlitespeed "$SERVERROOT"/bin/lshttpd
ln -sf lshttpd "$SERVERROOT"/bin/litespeed

util_cpfile "$SDIR_OWN" $DOC_MOD docs/* docs/css/* docs/img/* docs/ja-JP/* docs/zh-CN/*
util_cpfile "$SDIR_OWN" $DOC_MOD VERSION GPL.txt

chown "$CONF_OWN" "$SERVERROOT/admin/conf/jcryption_keypair"
chmod 0600 "$SERVERROOT/admin/conf/jcryption_keypair"

echo "PIDFILE=$PID_FILE" >"$SERVERROOT/bin/lsws_env"
echo "GRACEFUL_PIDFILE=$DEFAULT_TMP_DIR/graceful.pid" >>"$SERVERROOT/bin/lsws_env"
