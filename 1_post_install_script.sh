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

rm -rf /tmp/lshttpd

if [[ ! -d /opt/uny/ols ]]; then
    mkdir -pv /opt/uny/ols/admin
    cp -av {logs,cachedata,tmp,gdata,cgid} /opt/uny/ols
    cp -av {admin/logs,admin/tmp,admin/cgid,admin/fcgi-bin,admin/html} /opt/uny/ols/admin
fi

cd /opt/uny/ols || exit
for linkdir in {Example,bin,docs,share,fcgi-bin,add-ons,lsrecaptcha,modules,admin/html.open,admin/misc}; do
    ln -sfvn "$unypkg_root_dir"/"$linkdir" "$linkdir"
done

if [[ ! -d /etc/uny/ols ]]; then
    mkdir -pv /etc/uny/ols/admin
    cp -av {autoupdate,conf} /etc/uny/ols
    cp -av admin/conf /etc/uny/ols/admin
    ln -sfvn /etc/uny/ols/autoupdate autoupdate
    ln -sfvn /etc/uny/ols/conf conf
    ln -sfvn /etc/uny/ols/admin/conf admin/conf
fi

cd "$unypkg_root_dir" || exit
cp -a admin/misc/lshttpd.service /etc/systemd/system/uny-ols.service
sed "s|$unypkg_root_dir|/opt/uny/ols|" -i /etc/systemd/system/uny-ols.service
sed "s|KillMode=none|KillMode=mixed|" -i /etc/systemd/system/uny-ols.service
sed "s|PIDFile=/var/run/openlitespeed.pid|PIDFile=/run/openlitespeed.pid|" -i /etc/systemd/system/uny-ols.service
sed "s|.*Alias=.*||g" -i /etc/systemd/system/uny-ols.service
sed -e '/\[Install\]/a\' -e 'Alias=ols.service openlitespeed.service litespeed.service httpd.service apache2.service' -i /etc/systemd/system/uny-ols.service
systemctl daemon-reload

#############################################################################################
### End of script

cd "$current_dir" || exit
