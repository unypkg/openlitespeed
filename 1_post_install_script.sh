#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154,SC1003

current_dir="$(pwd)"
unypkg_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
unypkg_root_dir="$(cd -- "$unypkg_script_dir"/.. &>/dev/null && pwd)"

cd "$unypkg_root_dir" || exit

#############################################################################################
### Start of script

groupadd unyweb
unyweb_gid=$(grep "^unyweb:" /etc/group | awk -F : '{ print $3; }')
useradd -g "$unyweb_gid" -d /uny/home/unyweb -r -s /sbin/nologin unyweb
usermod -a -G unyweb unyweb

useradd -M -r -s /sbin/nologin lsadm

rm -rf /tmp/lshttpd

if [[ ! -d /etc/uny/openlitespeed ]]; then
    mkdir -pv /etc/uny/openlitespeed/admin
    cp -av conf /etc/uny/openlitespeed
    cp -av admin/conf /etc/uny/openlitespeed/admin
fi

if [[ ! -L conf ]]; then
    [[ -d conf_bak ]] && rm -rf conf_bak admin/conf_bak
    mv conf conf_bak
    mv admin/conf admin/conf_bak
    ln -sfvn /etc/uny/openlitespeed/conf conf
    ln -sfvn /etc/uny/openlitespeed/admin/conf admin/conf
fi

mkdir -pv /var/log/openlitespeed/{admin,logs} /var/log/openlitespeed/admin/logs
if [[ ! -L logs ]]; then
    ln -sfvn /var/log/openlitespeed/logs logs
    ln -sfvn /var/log/openlitespeed/admin/logs admin/logs
fi

mkdir -pv /var/www

chgrp unyweb admin/tmp admin/cgid cgid
chmod g+x admin/tmp admin/cgid cgid

chown root:root autoupdate tmp cachedata gdata Example     #SDIR_OWN
chown root:unyweb logs admin/logs                          #LOGDIR_OWN
chown unyweb:unyweb tmp/ocspcache cachedata autoupdate tmp #DIR_OWN

chmod 755 autoupdate tmp cachedata gdata Example #DIR_MOD
chmod 750 logs admin/logs admin/conf             #NO_VARIABLE

chown -R root:root admin lsrecaptcha fcgi-bin add-ons Example bin #SDIR_OWN
chown -R lsadm:lsadm conf share/autoindex admin/conf admin/tmp    #CONF_OWN

chmod -R 644 admin/cgid/secret                            #SDIR_MOD
chmod -R 555 admin lsrecaptcha fcgi-bin bin               #EXEC_MOD
chmod -R 755 admin/tmp admin/conf admin/cgid cgid Example #DIR_MOD
chmod -R 644 add-ons share/autoindex docs                 #DOC_MOD
chmod -R 600 conf                                         #CONF_MOD

#chmod -R 0750 "$SERVERROOT/conf/"

#chmod 0600 "$SERVERROOT/conf/httpd_config.conf"
#chmod 0600 "$SERVERROOT/conf/vhosts/Example/vhconf.conf"

#util_cpfile "$CONF_OWN" $DOC_MOD conf/${SSL_HOSTNAME}.crt
#util_cpfile "$CONF_OWN" $DOC_MOD conf/${SSL_HOSTNAME}.key

#chown lsadm:lsadm admin/conf/jcryption_keypair
#chmod 0600 admin/conf/jcryption_keypair

cp -a admin/misc/lshttpd.service /etc/systemd/system/uny-openlitespeed.service
sed "s|.*Alias=.*||g" -i /etc/systemd/system/uny-openlitespeed.service
sed -e '/\[Install\]/a\' -e 'Alias=ols.service openlitespeed.service litespeed.service httpd.service apache2.service' -i /etc/systemd/system/uny-openlitespeed.service
systemctl daemon-reload
systemctl enable uny-openlitespeed
systemctl restart uny-openlitespeed

#############################################################################################
### End of script

cd "$current_dir" || exit
