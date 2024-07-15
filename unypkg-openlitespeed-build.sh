#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154

set -vx

######################################################################################################################
### Setup Build System and GitHub

##apt install -y autopoint

wget -qO- uny.nu/pkg | bash -s buildsys

### Installing build dependencies
unyp install curl cmake libaio go pcre expat libxml2 brotli boringssl/5555991 re2c \
    libevent libbcrypt libinjection ip2location libmaxminddb udns lmdb yajl

#pip3_bin=(/uny/pkg/python/*/bin/pip3)
#"${pip3_bin[0]}" install --upgrade pip
#"${pip3_bin[0]}" install docutils pygments

### Getting Variables from files
UNY_AUTO_PAT="$(cat UNY_AUTO_PAT)"
export UNY_AUTO_PAT
GH_TOKEN="$(cat GH_TOKEN)"
export GH_TOKEN

source /uny/git/unypkg/fn
uny_auto_github_conf

######################################################################################################################
### Timestamp & Download

uny_build_date

mkdir -pv /uny/sources
cd /uny/sources || exit

pkgname="openlitespeed"
pkggit="https://github.com/litespeedtech/openlitespeed.git refs/tags/*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9.]+$" | tail --lines=1)"
latest_ver="$(echo "$latest_head" | grep -o "v[0-9.].*" | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

version_details

# Release package no matter what:
echo "newer" >release-"$pkgname"

git_clone_source_repo

cd "$pkgname" || exit

if [ -e lsquic ]; then
    ls src/ | grep liblsquic
    if [ $? -eq 0 ]; then
        echo Need to git download the submodule ...
        rm -rf lsquic
        git clone https://github.com/litespeedtech/lsquic.git
        cd lsquic

        LIBQUICVER=$(cat ../LSQUICCOMMIT)
        echo "LIBQUICVER is ${LIBQUICVER}"
        git checkout "${LIBQUICVER}"
        git submodule update --init --recursive
        cd .. || exit
    fi
fi

git clone https://github.com/cloudflare/zlib.git zlib-cf

cd /uny/sources || exit

archiving_source

phpgit="https://github.com/php/php-src.git refs/tags/php-8.2*"
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $phpgit | grep -E "php-[0-9.]*$" | tail --lines=1)"
# shellcheck disable=SC2001
pkg_head="$(echo "$latest_head" | sed "s|.*refs/[^/]*/||")"
pkg_git_repo="$(echo "$phpgit" | cut --fields=1 --delimiter=" ")"
git clone $gitdepth --recurse-submodules -j8 --single-branch -b "$pkg_head" "$pkg_git_repo"

######################################################################################################################
### Build

# unyc - run commands in uny's chroot environment
# shellcheck disable=SC2154
unyc <<"UNYEOF"
set -vx
source /uny/git/unypkg/fn

pkgname="openlitespeed"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

source /uny/git/unypkg/fn

# Build minimal lsphp/admin_php
#pkgname="php"
#version_verbose_log_clean_unpack_cd
#get_env_var_values
#get_include_paths
#./buildconf -f
#./configure --prefix=/tmp --disable-all --enable-litespeed --enable-session \
#    --enable-posix --enable-xml --with-expat --with-zlib --enable-sockets \
#    --enable-bcmath --enable-json
#make -j"$(nproc)"

####################################################
### Start of individual build script

unset LD_RUN_PATH

mkdir -p /sources/third-party/lib
#cp /uny/pkg/brotli/*/lib/*.a /sources/third-party/lib/
find /uny/pkg/brotli/*/lib/ -name "*.a" -exec bash -c 'subs="$(basename $1)"; cp "$1" "/sources/third-party/lib/${subs%.a}-static.a"' _ {} \;
cp /uny/pkg/boringssl/*/lib/*.a /sources/third-party/lib/
cp /uny/pkg/libxml2/*/lib/*.a /sources/third-party/lib/
cp /uny/pkg/expat/*/lib/*.a /sources/third-party/lib/

cd zlib-cf || exit
CFLAGS="-fPIC -O3" ./configure --prefix=/sources/third-party --static
make install
cd .. || exit

function commentout {
    sed -i -e "s/$1/#$1/g" "$2"
}

commentout 'add_definitions(-DRUN_TEST)' CMakeLists.txt
commentout 'add_definitions(-DPOOL_TESTING)' CMakeLists.txt
commentout 'add_definitions(-DTEST_OUTPUT_PLAIN_CONF)' CMakeLists.txt
commentout 'add_definitions(-DDEBUG_POOL)' CMakeLists.txt

commentout 'set(libUnitTest' CMakeLists.txt

commentout 'find_package(ZLIB' CMakeLists.txt
commentout 'find_package(PCRE' CMakeLists.txt
# commentout 'find_package(EXPAT REQUIRED)'
commentout 'add_subdirectory(test)' CMakeLists.txt

commentout 'SET (CMAKE_C_COMPILER' CMakeLists.txt
commentout 'SET (CMAKE_CXX_COMPILER' CMakeLists.txt

sed -i -e "s/\${unittest_STAT_SRCS}//g" src/CMakeLists.txt
sed -i -e "s/libstdc++.a//g" src/CMakeLists.txt
sed -i -e "s/-nodefaultlibs //g" src/CMakeLists.txt
sed -i -e "s/-nodefaultlibs libstdc++.a//g" src/modules/modsecurity-ls/CMakeLists.txt
sed -i -e "s/-nodefaultlibs libstdc++.a//g" src/modules/lua/CMakeLists.txt

commentout ls_llmq.c src/lsr/CMakeLists.txt
commentout ls_llxq.c src/lsr/CMakeLists.txt

CUR_PATH="$(pwd)"
cd src/modules/lsrecaptcha || exit
export GOPATH=$CUR_PATH/src/modules/lsrecaptcha
export GO111MODULE=off
go build lsrecaptcha
cp lsrecaptcha ../../../dist/lsrecaptcha/_recaptcha
cd ../../../

rm -f CMakeCache.txt
rm -f build/CMakeCache.txt

mkdir build
cd build || exit

cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DMOD_PAGESPEED="OFF" \
    -DMOD_SECURITY="OFF" \
    -DMOD_LUA="OFF" ..

make -j"$(nproc)"
cd .. || exit

########################################################
# Installation

cp build/src/openlitespeed dist/bin/
if [ -e build/support/unmount_ns/unmount_ns ]; then
    cp build/support/unmount_ns/unmount_ns dist/bin/
fi

if [ ! -d dist/modules/ ]; then
    mkdir dist/modules/
fi
for module in build/src/modules/*; do
    cp -f "${module}"/*.so dist/modules/
done

cat >./ols.conf <<END
#If you want to change the default values, please update this file.

SERVERROOT=/uny/pkg/"$pkgname"/"$pkgver"
OPENLSWS_USER=unyweb
OPENLSWS_GROUP=unyweb
OPENLSWS_ADMIN=unyweb
OPENLSWS_EMAIL=root@localhost
OPENLSWS_ADMINSSL=yes
OPENLSWS_ADMINPORT=7080
USE_LSPHP7=yes
DEFAULT_TMP_DIR=/run/lshttpd
PID_FILE=/run/lshttpd/lshttpd.pid
OPENLSWS_EXAMPLEPORT=8088

#You can set password here
OPENLSWS_PASSWORD=123456
END

mv dist/install.sh dist/_in.sh

source ./ols.conf

mkdir -p "$SERVERROOT" >/dev/null 2>&1
cd dist || exit

groupadd unyweb
unyweb_gid=$(grep "^unyweb:" /etc/group | awk -F : '{ print $3; }')
useradd -g "$unyweb_gid" -d / -r -s /sbin/nologin unyweb
usermod -a -G unyweb unyweb

# Install libatomic?

cp -a bin/* "$SERVERROOT"/bin/

sed -e "s/%ADMIN_PORT%/$OPENLSWS_ADMINPORT/" admin/conf/admin_config.conf.in >admin/conf/admin_config.conf
sed -e "s/%USER%/$OPENLSWS_USER/" -e "s/%GROUP%/$OPENLSWS_GROUP/" -e "s#%DEFAULT_TMP_DIR%#$DEFAULT_TMP_DIR#" -e "s/%ADMIN_EMAIL%/$OPENLSWS_EMAIL/" -e "s/%HTTP_PORT%/$OPENLSWS_EXAMPLEPORT/" -e "s/%RUBY_BIN%/$RUBY_PATH/" conf/httpd_config.conf.in >/conf/httpd_config.conf

sed "s:%LSWS_CTRL%:$SERVERROOT/bin/lswsctrl:" admin/misc/lsws.rc.in >admin/misc/lsws.rc
sed "s:%LSWS_CTRL%:$SERVERROOT/bin/lswsctrl:" admin/misc/lsws.rc.gentoo.in >admin/misc/lsws.rc.gentoo
sed "s:%LSWS_CTRL%:$SERVERROOT/bin/lswsctrl:" admin/misc/lshttpd.service.in >admin/misc/lshttpd.service

DIR_MOD=755
SDIR_MOD=700
EXEC_MOD=555
CONF_MOD=600
DOC_MOD=644

DIR_OWN="unyweb:unyweb"
CONF_OWN="unyweb:unyweb"
SDIR_OWN="root:root"
LOGDIR_OWN="root:unyweb"

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

util_mkdir "$SDIR_OWN" "$DIR_MOD" admin bin docs fcgi-bin lsrecaptcha php lib modules backup autoupdate tmp cachedata gdata docs/css docs/img docs/ja-JP docs/zh-CN add-ons share share/autoindex share/autoindex/icons admin/fcgi-bin admin/html."$VERSION" admin/misc lsns lsns/bin lsns/conf
util_mkdir "$LOGDIR_OWN" "0750" logs admin/logs lsns/logs
util_mkdir "$CONF_OWN" "$SDIR_MOD" conf conf/cert conf/templates conf/vhosts conf/vhosts/Example admin/conf admin/tmp phpbuild
util_mkdir "$SDIR_OWN" "$SDIR_MOD" cgid admin/cgid admin/cgid/secret
util_mkdir "$DIR_OWN" "$SDIR_MOD" tmp/ocspcache
chgrp unyweb "$SERVERROOT"/admin/tmp "$SERVERROOT"/admin/cgid "$SERVERROOT"/cgid
chmod g+x "$SERVERROOT"/admin/tmp "$SERVERROOT"/admin/cgid "$SERVERROOT"/cgid
chown "$CONF_OWN" "$SERVERROOT"/admin/tmp/sess_* 1>/dev/null 2>&1
chown "$DIR_OWN" "$SERVERROOT"/cachedata
chown "$DIR_OWN" "$SERVERROOT"/autoupdate
chown "$DIR_OWN" "$SERVERROOT"/tmp
util_mkdir "$SDIR_OWN" "$DIR_MOD" Example

util_cpdir "$SDIR_OWN" $DOC_MOD add-ons
util_cpdir "$CONF_OWN" $DOC_MOD share/autoindex

util_ccpfile "$SDIR_OWN" $EXEC_MOD fcgi-bin/lsperld.fpl fcgi-bin/RackRunner.rb fcgi-bin/lsnode.js
util_cpfile "$SDIR_OWN" $EXEC_MOD fcgi-bin/RailsRunner.rb fcgi-bin/RailsRunner.rb.2.3

pkill _recaptcha
util_cpfile "$SDIR_OWN" $EXEC_MOD lsrecaptcha/_recaptcha lsrecaptcha/_recaptcha.shtml
util_cpfile "$SDIR_OWN" $EXEC_MOD admin/misc/rc-inst.sh admin/misc/admpass.sh admin/misc/rc-uninst.sh admin/misc/uninstall.sh admin/misc/lsws.rc admin/misc/lsws.rc.gentoo admin/misc/enable_phpa.sh admin/misc/mgr_ver.sh admin/misc/gzipStatic.sh admin/misc/fp_install.sh admin/misc/create_admin_keypair.sh admin/misc/awstats_install.sh admin/misc/update.sh admin/misc/cleancache.sh admin/misc/lsup.sh admin/misc/testbeta.sh
util_cpfile "$SDIR_OWN" $EXEC_MOD admin/misc/ap_lsws.sh.in admin/misc/build_ap_wrapper.sh admin/misc/cpanel_restart_httpd.in admin/misc/build_admin_php.sh admin/misc/convertxml.sh admin/misc/lscmctl
util_cpfile "$SDIR_OWN" $DOC_MOD admin/misc/gdb-bt admin/misc/htpasswd.php admin/misc/php.ini admin/misc/genjCryptionKeyPair.php admin/misc/purge_cache_byurl.php
util_cpfile "$SDIR_OWN" $DOC_MOD admin/misc/convertxml.php admin/misc/lshttpd.service

util_ccpfile "$CONF_OWN" $CONF_MOD admin/conf/htpasswd

util_cpfile "$CONF_OWN" $CONF_MOD admin/conf/admin_config.conf
util_cpfile "$CONF_OWN" $CONF_MOD conf/templates/ccl.conf conf/templates/phpsuexec.conf conf/templates/rails.conf
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

# Build simplified php for OLS
cd /sources/php-src || exit
./buildconf --force
./configure --prefix=/tmp --disable-all --enable-litespeed --enable-session --enable-posix --enable-xml --without-libxml --with-expat --with-zlib --enable-sockets --enable-bcmath
make -j"$(nproc)"
strip sapi/litespeed/php
chmod a+rx sapi/litespeed/php
cp -a sapi/litespeed/php "$SERVERROOT"/admin/fcgi-bin/admin_php
cp -a sapi/litespeed/php "$SERVERROOT"/fcgi-bin/lsphp
cd ../openlitespeed-*/dist || exit

ENCRYPT_PASS=$("$SERVERROOT/admin/fcgi-bin/admin_php" -q "$SERVERROOT/admin/misc/htpasswd.php" "$OPENLSWS_PASSWORD")
echo "$ADMIN_USER:$ENCRYPT_PASS" >"$SERVERROOT/admin/conf/htpasswd"

"$SERVERROOT"/admin/misc/create_admin_keypair.sh

chown "$CONF_OWN" "$SERVERROOT/admin/conf/jcryption_keypair"
chmod 0600 "$SERVERROOT/admin/conf/jcryption_keypair"

chown "$CONF_OWN" "$SERVERROOT/admin/conf/htpasswd"
chmod 0600 "$SERVERROOT/admin/conf/htpasswd"

echo "PIDFILE=$PID_FILE" >"$SERVERROOT/bin/lsws_env"
echo "GRACEFUL_PIDFILE=$DEFAULT_TMP_DIR/graceful.pid" >>"$SERVERROOT/bin/lsws_env"

"$SERVERROOT"/admin/misc/lscmctl --update-lib

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end
UNYEOF

######################################################################################################################
### Packaging

package_unypkg
