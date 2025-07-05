#!/bin/bash
# 一键安装 Xray VLESS+TCP+Reality 脚本（兼容新版 x25519 输出）

set -e

echo "欢迎使用 Xray VLESS+TCP+Reality 一键安装脚本"

# 读端口
read -rp "请输入监听端口（默认443）: " PORT
PORT=${PORT:-443}

# 读伪装域名
read -rp "请输入伪装域名（必须真实可访问）: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "伪装域名不能为空，退出"
  exit 1
fi

# 生成UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的UUID：$UUID"

# 下载并准备xray
TMPDIR=$(mktemp -d)
echo "下载并解压Xray核心..."
wget -q -O $TMPDIR/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -o $TMPDIR/xray.zip -d $TMPDIR
chmod +x $TMPDIR/xray

# 生成Reality密钥对
KEYS=$($TMPDIR/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk -F': ' '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk -F': ' '{print $2}')

# 计算shortId
PUB_BASE64_STD=$(echo "$PUBLIC_KEY" | tr '_-' '/+')
echo "$PUB_BASE64_STD" | base64 -d > $TMPDIR/pubkey.bin
SHORT_ID=$(sha256sum $TMPDIR/pubkey.bin | cut -c1-16)
rm $TMPDIR/pubkey.bin

echo "Reality privateKey: $PRIVATE_KEY"
echo "Reality publicKey: $PUBLIC_KEY"
echo "Reality shortId: $SHORT_ID"

# 写配置文件
CONFIG_FILE="/usr/local/etc/xray/config.json"
mkdir -p /usr/local/etc/xray

cat > $CONFIG_FILE <<EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-direct"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DOMAIN:443",
          "xver": 0,
          "serverNames": [
            "$DOMAIN"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 安装xray二进制
echo "安装xray二进制..."
install -m 755 $TMPDIR/xray /usr/local/bin/xray

# 创建systemd服务文件
SERVICE_FILE="/etc/systemd/system/xray.service"
cat > $SERVICE_FILE <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config $CONFIG_FILE
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 重新加载服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo -e "\nXray已启动，监听端口：$PORT"

# 生成客户端链接

# pb 参数是 base64 URL 公钥，无需转换
CLIENT_LINK="vless://$UUID@$DOMAIN:$PORT?security=reality&encryption=none&type=tcp&flow=xtls-rprx-direct&pb=$PUBLIC_KEY&sid=$SHORT_ID&fp=chrome#${DOMAIN}_Reality_TCP"

echo -e "\n客户端配置链接:\n$CLIENT_LINK"

# 安装二维码工具生成二维码（如果可用）
if command -v qrencode >/dev/null 2>&1; then
  echo -e "\n客户端配置二维码："
  echo "$CLIENT_LINK" | qrencode -o - -t utf8
else
  echo -e "\n未安装 qrencode，无法生成二维码。你可以手动安装：apt install qrencode"
fi

echo -e "\n安装完成！请确保伪装域名已解析到本VPS IP，且端口已放行。"
