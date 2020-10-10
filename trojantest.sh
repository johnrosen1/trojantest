#!/usr/bin/env bash

## usage: bash speed.sh -d example.com -p 123456

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -d|--domain)
    Domain="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--password)
    Password="$2"
    shift # past argument
    shift # past value
    ;;
    -l|--lib)
    LIBPATH="$2"
    shift # past argument
    shift # past value
    ;;
    --default)
    DEFAULT=YES
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

echo "---节点域名: ${Domain}---"
echo "---节点密码: ${Password}---"

echo "-----检测域名是否合法并存在-----"

if [ ! -f /usr/bin/host ]; then
apt-get install dnsutils -y
fi

host ${Domain}

if [[ $? != 0 ]]; then
	echo "域名不存在"
	#ip_test="0"
	exit 1;
fi

remoteip=$(dig +short -t a ${Domain})

if [[ -z ${remoteip} ]]; then
	echo "域名A解析不存在"
	exit 1;
else
	echo "节点域名解析ip: ${remoteip}"
fi

echo "-----开始连通性测试-----"

echo "---------Tcping 测试----------"

if [ ! -f /usr/bin/nc ]; then
apt-get install nmap -y
fi

nc -z -v -w5 ${Domain} 443

if [[ $? != 0 ]]; then
	echo "Tcping失败!"
	#ip_test="0"
	exit 1;
fi

nping --tcp -p 443 ${Domain} -c 4

echo "-----开始路由测试-----"

echo -e "----------ICMP路由(不准确,仅供参考)----------"

traceroute ${Domain}

echo "----------TCP 443路由----------"

tcptraceroute ${Domain} 443

if [[ ! -d /etc/trojan/nodes/ ]]; then
	mkdir /etc/trojan/
	mkdir /etc/trojan/nodes/
fi

if [ ! -f /etc/systemd/system/trojan@.service ]; then
	cat > '/etc/systemd/system/trojan.service' << EOF
[Unit]
Description=trojan
Documentation=https://trojan-gfw.github.io/trojan/config https://trojan-gfw.github.io/trojan/
Before=netdata.service
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
ExecStart=/usr/sbin/trojan /etc/trojan/nodes/%i.json
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=51200
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
sytemctl daemon-reload
fi

cd /etc/trojan/nodes/

local_port=$(( $RANDOM % 10000 + 50000 ))

	cat > "${Domain}.json" << EOF
{
	"run_type": "client",
	"local_addr": "127.0.0.1",
	"local_port": ${local_port},
	"remote_addr": "${Domain}",
	"remote_port": 443,
	"password": [
		"${Password}"
	],
	"log_level": 1,
	"ssl": {
		"verify": true,
		"verify_hostname": true,
		"cert": "",
		"cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA:AES128-SHA:AES256-SHA:DES-CBC3-SHA",
		"cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
		"sni": "",
		"alpn": [
			"h2",
			"http/1.1"
		],
		"reuse_session": true,
		"session_ticket": false,
		"curves": ""
	},
	"tcp": {
		"no_delay": true,
		"keep_alive": true,
		"reuse_port": false,
		"fast_open": false,
		"fast_open_qlen": 20
	}
}
EOF
systemctl stop trojan@${Domain}
systemctl start trojan@${Domain}

if [[ $? != 0 ]]; then
	echo "启动失败"
	exit 1
fi

systemctl is-active trojan@${Domain}

if [[ $? != 0 ]]; then
	echo "启动失败"
	exit 1
fi

echo "-----获取节点IP信息ing-----"

curl --proxy socks5h://127.0.0.1:${local_port} https://ipinfo.io?token=56c375418c62c9 --connect-timeout 30

if [[ $? != 0 ]]; then
	echo "获取IP信息失败"
	ip_test="0"
	exit 1;
fi

curl --proxy socks5h://127.0.0.1:${local_port} https://ipinfo.io?token=56c375418c62c9 --connect-timeout 30 &> ${Domain}_ip.json

#echo -e "----------------------IP信息(IP Information)----------------------------"
#echo -e "ip:\t\t"$(jq -r '.ip' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "city:\t\t"$(jq -r '.city' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "region:\t\t"$(jq -r '.region' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "country:\t"$(jq -r '.country' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "loc:\t\t"$(jq -r '.loc' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "org:\t\t"$(jq -r '.org' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "postal:\t\t"$(jq -r '.postal' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "timezone:\t"$(jq -r '.timezone' "/etc/trojan/nodes/${Domain}_ip.json")
#echo -e "------------------------------------------------------------------------"

echo "-----测试Google连通性-----"

curl --proxy socks5h://127.0.0.1:${local_port} google.com --connect-timeout 30 &> /dev/null

if [[ $? != 0 ]]; then
	echo "连线Google失败"
	google_test="0"
	#exit 1;
else
	echo "---Google测试通过---"
fi

echo "-----测试Telegram连通性-----"

curl --proxy socks5h://127.0.0.1:${local_port} 91.108.56.154:443 --connect-timeout 30 &> /dev/null

if [[ $? != 0 ]]; then
	echo "连线Telegram失败"
	tg_test="0"
	#exit 1;
else
	echo "---Telegram测试通过---"
fi

echo "-----测试完成-----"
