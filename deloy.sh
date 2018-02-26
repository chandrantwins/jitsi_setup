#!/bin/bash
#######################################################
# Deloy jitsi server 
# Version 1.0
#######################################################

#check root user
if [ $(id -u) != "0" ]; then
    printf "You need to be root to perform this command. Run \"sudo su\" to become root!\n"
    exit
fi
cd ~/

printf "=========================================================================\n"
printf "Check cai cau hinh phat da \n"
printf "=========================================================================\n"
cpu_name=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo )
cpu_cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
cpu_freq=$( awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo )
server_ram_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
server_ram_mb=`echo "scale=0;$server_ram_total/1024" | bc`
server_hdd=$( df -h | awk 'NR==2 {print $2}' )
server_swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
server_swap_mb=`echo "scale=0;$server_swap_total/1024" | bc`

printf "=========================================================================\n"
printf "Thong so server cua ban nhu sau \n"
printf "=========================================================================\n"
echo "Loai CPU : $cpu_name"
echo "Tong so CPU core : $cpu_cores"
echo "Toc do moi core : $cpu_freq MHz"
echo "Tong dung luong RAM : $server_ram_mb MB"
echo "Tong dung luong swap : $server_swap_mb MB"
echo "Tong dung luong o dia : $server_hdd GB"
printf "=========================================================================\n"
printf "=========================================================================\n"

sleep 3

printf "=========================================================================\n"
printf "Chuan bi qua trinh cai dat... \n"
printf "=========================================================================\n"

sleep 3
#update server
apt-get update
home_dir=$( getent passwd "$USER" | cut -d: -f6 )
apt-get install -y default-jre
apt-get install -y default-jdk maven

export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

printf "=========================================================================\n"
printf "Cai dat PROSODY... \n"
printf "=========================================================================\n"

printf "\nNhap vao domain (khong http, khong www): " 
read server_name
if [ "$server_name" = "" ]; then
	echo "Nhap sai cmnr. Say googbye!!!"
	exit
fi

printf "\nNhat mat khau server jvb (de trong de tao tu dong): " 
read jvb_secret
if [ "$jvb_secret" = "" ]; then
	jvb_secret=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
fi

printf "\nNhat mat khau server jcofo (de trong de tao tu dong): " 
read jcofo_secret
if [ "$jcofo_secret" = "" ]; then
	jcofo_secret=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
fi

printf "\nNhat mat khau server auth (de trong de tao tu dong): " 
read auth_secret
if [ "$auth_secret" = "" ]; then
	auth_secret=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
fi

printf "=========================================================================\n"
printf "Tien hanh cai dat prosody... \n"
printf "Server name: \t $server_name \n"
printf "JVB secret:\t $jvb_secret \n"
printf "JCOFO secret: \t $jcofo_secret \n"
printf "AUTH secret: \t $jcofo_secret \n"
printf "=========================================================================\n"

apt-get install -y prosody

cat > "/etc/prosody/conf.avail/$server_name" <<END
VirtualHost "$server_name"
    authentication = "anonymous"
    ssl = {
        key = "/var/lib/prosody/$server_name.key";
        certificate = "/var/lib/prosody/$server_name.crt";
    }
    modules_enabled = {
        "bosh";
        "pubsub";
    }
    c2s_require_encryption = false

VirtualHost "auth.$server_name"
    ssl = {
        key = "/var/lib/prosody/auth.$server_name.key";
        certificate = "/var/lib/prosody/auth.$server_name.crt";
    }
    authentication = "internal_plain"

admins = { "focus@auth.$server_name" }

Component "conference.$server_name" "muc"

Component "jitsi-videobridge.$server_name"
    component_secret = "$jvb_secret"

Component "focus.$server_name"
    component_secret = "$jcofo_secret"
END

sleep 3

# Sync config file
ln -s "/etc/prosody/conf.avail/$server_name.cfg.lua" "/etc/prosody/conf.d/$server_name.cfg.lua"

# Generate certificates file 
prosodyctl cert generate "$server_name"
prosodyctl cert generate "auth.$server_name"

# Add certificate to the trusted certificates on the local machine
ln -sf "/var/lib/prosody/auth.$server_name.crt" "/usr/local/share/ca-certificates/auth.$server_name.crt"
update-ca-certificates -f

#Create conference focus user:
prosodyctl register focus "auth.$server_name" "$auth_secret"

printf "=========================================================================\n"
printf "Cai dat thanh cong PROSODY. Restart... \n"
printf "=========================================================================\n"
prosodyctl restart

sleep 3

printf "=========================================================================\n"
printf "Cai dat NGINX... \n"
printf "=========================================================================\n"

apt-get install -y nginx 

mkdir /etc/nginx/ssl/
openssl dhparam 2048 -out /etc/nginx/ssl/dhparam.pem

cat > "/etc/nginx/sites-available/$server_name" <<END
server_names_hash_bucket_size 64;
server {
    listen 443 ssl;
    server_name $server_name;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA256:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EDH+aRSA+AESGCM:EDH+aRSA+SHA256:EDH+aRSA:EECDH:!aNULL:!eNULL:!MEDIUM:!LOW:!3DES:!MD5:!EXP:$
	
	add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
 	add_header 'Access-Control-Allow-Headers' 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Content-Range,Range';
    add_header Strict-Transport-Security "max-age=31536000";

    ssl_certificate /etc/letsencrypt/live/$server_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$server_name/privkey.pem;

    root /usr/share/jitsi-meet;
    index index.html index.htm;
    error_page 404 /static/404.html;

    location ~ ^/([a-zA-Z0-9=\?]+)$ {
        rewrite ^/(.*)$ / break;
    }

    location / {
        ssi on;
    }

    # BOSH
    location /http-bind {
        proxy_pass      http://localhost:5280/http-bind;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $http_host;
    }
}
END

printf "=========================================================================\n"
printf "Cai dat SSL... \n"
printf "=========================================================================\n"

git clone https://github.com/letsencrypt/letsencrypt /opt/letsencrypt

service nginx stop

cd /opt/letsencrypt
./letsencrypt-auto certonly --standalone

printf "=========================================================================\n"
printf "Cai dat JVB... \n"
printf "=========================================================================\n"

cd ~/
wget https://download.jitsi.org/jitsi-videobridge/linux/jitsi-videobridge-linux-x64-1031.zip
unzip jitsi-videobridge-linux-x64-1031.zip

mkdir "$home_dir/.sip-communicator"

cat > "$home_dir/.sip-communicator/sip-communicator.properties" <<END
org.jitsi.impl.neomedia.transform.srtp.SRTPCryptoContext.checkReplay=false
END

cat > "/etc/rc.local" <<END
/bin/bash /root/jitsi-videobridge-linux-x64-1031/jvb.sh --host=localhost --domain=$server_name --port=5347 --secret=$jvb_secret </dev/null >> /var/log/jvb.log 2>&1
END


