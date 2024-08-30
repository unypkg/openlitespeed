#!/usr/bin/env bash
# shellcheck disable=SC2010,SC2034,SC1091,SC2154

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

wget -O dist/admin/html.open/lib/jCryption.php https://raw.githubusercontent.com/unysrc/openlitespeed/php-8-fixes/dist/admin/html.open/lib/jCryption.php
wget -O dist/admin/misc/genjCryptionKeyPair.php https://raw.githubusercontent.com/unysrc/openlitespeed/php-8-fixes/dist/admin/misc/genjCryptionKeyPair.php

if [ -e lsquic ]; then
    if ls src/ | grep liblsquic; then
        echo Need to git download the submodule ...
        rm -rf lsquic
        git clone https://github.com/litespeedtech/lsquic.git
        cd lsquic || exit

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

phpgit="https://github.com/php/php-src.git refs/tags/php-*"
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

cmake -DCMAKE_BUILD_TYPE=Release \
    -DMOD_PAGESPEED="OFF" \
    -DMOD_SECURITY="OFF" \
    -DMOD_LUA="OFF" ..

make -j"$(nproc)"
cd .. || exit

# Build simplified php for OLS
cur_dir="$(pwd)"
cd /sources/php-src || exit

./buildconf --force
./configure --prefix=/tmp --disable-all --enable-litespeed --enable-session --enable-posix --enable-xml --without-libxml --with-expat --with-zlib --enable-sockets --enable-bcmath
make -j"$(nproc)"
chmod a+rx sapi/litespeed/php

cd "$cur_dir" || exit

########################################################
# Installation

cp build/src/openlitespeed dist/bin/
cp -a bin/* dist/bin/

if [ -e build/support/unmount_ns/unmount_ns ]; then
    cp build/support/unmount_ns/unmount_ns dist/bin/
fi

if [ ! -d dist/modules/ ]; then
    mkdir dist/modules/
fi
for module in build/src/modules/*; do
    cp -f "${module}"/*.so dist/modules/
done

cat >dist/ols.conf <<END
#If you want to change the default values, please update this file.

SERVERROOT=/uny/pkg/"$pkgname"/"$pkgver"
OPENLSWS_USER=unyweb
OPENLSWS_GROUP=unyweb
OPENLSWS_ADMIN=unyadm
OPENLSWS_EMAIL=root@localhost
OPENLSWS_ADMINSSL=yes
OPENLSWS_ADMINPORT=7080
USE_LSPHP7=yes
DEFAULT_TMP_DIR=/tmp/lshttpd
PID_FILE=/tmp/lshttpd/lshttpd.pid
OPENLSWS_EXAMPLEPORT=8088

#You can set password here
OPENLSWS_PASSWORD=123456
END

source dist/ols.conf

mv dist/install.sh dist/_in.sh

function makedir {
    for arg; do
        mkdir -pv "$SERVERROOT/$arg"
    done
}

function cpdir {
    for arg; do
        cp -R "$arg/"* "$SERVERROOT/$arg/"
    done
}

makedir autoupdate logs tmp/ocspcache admin/tmp admin/logs admin/fcgi-bin cachedata gdata cgid admin/cgid/secret Example/logs Example/fcgi-bin

cp -a /sources/php-src/sapi/litespeed/php dist/bin/ols_php

cd dist || exit

sed -e "s/%ADMIN_PORT%/$OPENLSWS_ADMINPORT/" admin/conf/admin_config.conf.in >admin/conf/admin_config.conf
sed -e "s/%USER%/$OPENLSWS_USER/" -e "s/%GROUP%/$OPENLSWS_GROUP/" -e "s#%DEFAULT_TMP_DIR%#$DEFAULT_TMP_DIR#" -e "s/%ADMIN_EMAIL%/$OPENLSWS_EMAIL/" -e "s/%HTTP_PORT%/$OPENLSWS_EXAMPLEPORT/" -e "s/%RUBY_BIN%/$RUBY_PATH/" conf/httpd_config.conf.in >conf/httpd_config.conf

sed "s:%LSWS_CTRL%:$SERVERROOT/bin/lswsctrl:" admin/misc/lsws.rc.in >admin/misc/lsws.rc
sed "s:%LSWS_CTRL%:$SERVERROOT/bin/lswsctrl:" admin/misc/lsws.rc.gentoo.in >admin/misc/lsws.rc.gentoo
sed "s:%LSWS_CTRL%:$SERVERROOT/bin/lswsctrl:" admin/misc/lshttpd.service.in >admin/misc/lshttpd.service

ln -sf html.open admin/html
ln -sf openlitespeed bin/lshttpd
ln -sf openlitespeed bin/litespeed

echo "PIDFILE=/tmp/lshttpd/lshttpd.pid" >bin/lsws_env
echo "GRACEFUL_PIDFILE=/tmp/lshttpd/graceful.pid" >>bin/lsws_env

cd .. || exit

cp -a dist/* "$SERVERROOT"

ln -s ../bin/ols_php "$SERVERROOT"/fcgi-bin/lsphp
ln -s ../../bin/ols_php "$SERVERROOT"/admin/fcgi-bin/admin_php

ENCRYPT_PASS=$("$SERVERROOT/admin/fcgi-bin/admin_php" -q "$SERVERROOT/admin/misc/htpasswd.php" "$OPENLSWS_PASSWORD")
echo "$OPENLSWS_ADMIN:$ENCRYPT_PASS" >"$SERVERROOT/admin/conf/htpasswd"

"$SERVERROOT"/admin/misc/create_admin_keypair.sh
#"$SERVERROOT"/admin/misc/lscmctl --update-lib

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end
UNYEOF

######################################################################################################################
### Packaging

package_unypkg
