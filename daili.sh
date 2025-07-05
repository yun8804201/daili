#!/bin/bash
# 一键安装 Xray VLESS+TCP+Reality 脚本（兼容新版x25519）

set -e

echo "欢迎使用 Xray VLESS+TCP+Reality 一键安装脚本"

# 读取监听端口
read -rp "请输入监听端口（默认443）: " PORT
PORT=${PORT:-443}

# 读取伪装域名
read -rp "请输入伪装域名（必须真实可访问）: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "伪装域名不能为空，脚本退出"
  exit 1
fi

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

# 下载 Xray 核心
TMPDIR=$(mktemp -d)
echo "下载 Xray 核心..."
wget -q -O $TMPDIR/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -o $TMPDIR/xray.zip -d $TMPDIR
chmod +x $TMPDIR/xray

# 生成 Reality 密钥对
KEYS=$($TMPDIR/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk -F': ' '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk -F': ' '{print $2}')
echo "Reality PrivateKey: $PRIVATE_KEY"
echo "Reality PublicKey: $PUBLIC_KEY"

# 处理 Base64 URL 编码，补齐 padding
PUB_BASE64_STD=$(echo "$PUBLIC_KEY" | tr '_-' '/+')
mod4=$(( ${#PUB_BASE64_STD} % 4 ))
if [ $mod4 -ne 0 ]; then
  padding=$((4 - mod4))
  PUB_BASE64_STD="${PUB_BASE64_STD}$(printf '=%.0s' $(seq 1 $padding))"
fi
echo "$PUB_BASE64_STD" | base64 -d > $TMPDIR/pubkey.bin
SHORT_ID=$(sha256sum $TMPDIR/pubkey.bin | cut -c1-16)
rm $TMPDIR/pubkey.bin

echo "生成 shortId: $SHORT_ID"

# 安装 Xray 到系统路径
install -m 755 $TMPDIR/xray /usr/local/bin/xray

# 创建配置目录
mkdir -p /usr/local/etc/xray

# 写入配置文件
CONFIG_FILE="/usr/local/etc/xray/config.json"
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
          "serverNames": ["$DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
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

# 写入 systemd 服务文件
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 显示配置信息
echo -e "\n✅ Xray 安装并启动成功！"

# 客户端配置链接
CLIENT_LINK="vless://$UUID@$DOMAIN:$PORT?security=reality&encryption=none&type=tcp&flow=xtls-rprx-direct&pb=$PUBLIC_KEY&sid=$SHORT_ID&fp=chrome#Reality_VLESS"

echo -e "\n📎 客户端配置链接：\n$CLIENT_LINK"

# 显示二维码
if command -v qrencode >/dev/null 2>&1; then
  echo -e "\n📱 配置二维码："
  echo "$CLIENT_LINK" | qrencode -o - -t utf8
else
  echo -e "\n（可选）你可以安装二维码工具：sudo apt install qrencode"
fi

# 完成提示
echo -e "\n🎉 全部完成，请使用支持 Reality 的客户端导入配置链接或二维码。"
