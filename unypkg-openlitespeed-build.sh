#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154

set -vx

######################################################################################################################
### Setup Build System and GitHub

##apt install -y autopoint

wget -qO- uny.nu/pkg | bash -s buildsys

### Installing build dependencies
unyp install curl cmake libaio go pcre2 expat libxml2 brotli boringssl \
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
        git checkout ${LIBQUICVER}
        git submodule update --init --recursive
        cd ..

    fi
fi

cd /uny/sources || exit

archiving_source

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

function commentout {
    sed -i -e "s/$1/#$1/g" $2
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

cd src/modules/lsrecaptcha
export GOPATH=$CUR_PATH/src/modules/lsrecaptcha
export GO111MODULE=off
go build lsrecaptcha
cp lsrecaptcha ../../../dist/lsrecaptcha/_recaptcha
cd ../../../

rm -f CMakeCache.txt
rm -f build/CMakeCache.txt

mkdir build
cd build || exit

cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"

cp build/src/openlitespeed dist/bin/
if [ -e build/support/unmount_ns/unmount_ns ]; then
    cp build/support/unmount_ns/unmount_ns dist/bin/
fi

if [ ! -d dist/modules/ ]; then
    mkdir dist/modules/
fi
for module in build/src/modules/*; do
    cp -f ${module}/*.so dist/modules/
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

########################################################
cat >./install.sh <<END

CONFFILE=./ols.conf

./_in.sh "\${SERVERROOT}" "\${OPENLSWS_USER}" "\${OPENLSWS_GROUP}" "\${OPENLSWS_ADMIN}" "\${OPENLSWS_PASSWORD}" "\${OPENLSWS_EMAIL}" "\${OPENLSWS_ADMINSSL}" "\${OPENLSWS_ADMINPORT}" "\${USE_LSPHP7}" "\${DEFAULT_TMP_DIR}" "\${PID_FILE}" "\${OPENLSWS_EXAMPLEPORT}" no

cp -f modules/*.so \${SERVERROOT}/modules/
cp -f bin/openlitespeed \${SERVERROOT}/bin/

if [ "\${PASSWDFILEEXIST}" = "no" ]; then
    echo -e "\e[31mYour webAdmin password is \${OPENLSWS_PASSWORD}, written to file \$SERVERROOT/adminpasswd.\e[39m"
else
    echo -e "\e[31mYour webAdmin password not changed.\e[39m"
fi
echo

if [ -f ../needreboot.txt ]; then
    rm ../needreboot.txt
    echo -e "\e[31mYou must reboot the server to ensure the settings change take effect!\e[39m"
    echo
    exit 0
fi

if [ "\${ISRUNNING}" = "yes" ]; then
    \${SERVERROOT}/bin/lswsctrl start
fi
END
chmod 777 ./install.sh
./install.sh

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end
UNYEOF

######################################################################################################################
### Packaging

package_unypkg
