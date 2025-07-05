#!/bin/bash

echo "==============================================="
echo "欢迎使用 VLESS + TCP + Reality 自动安装脚本"
echo "==============================================="

# 检查是否root权限
if [ "$EUID" -ne 0 ]; then
  echo "请以root用户运行此脚本！"
  exit 1
fi

apt update && apt install -y curl wget unzip socat qrencode jq

# 生成UUID函数
generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

# 生成Reality密钥对函数
generate_reality_keys() {
  TMPDIR=$(mktemp -d)
  echo "正在下载xray临时版本用于生成Reality密钥..."
  XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f 4)
  wget -q -O $TMPDIR/xray.zip https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip
  unzip -q $TMPDIR/xray.zip -d $TMPDIR
  chmod +x $TMPDIR/xray

  KEYS_JSON=$($TMPDIR/xray x25519)
  rm -rf $TMPDIR

  PRIVATE_KEY=$(echo $KEYS_JSON | jq -r '.privateKey')
  PUBLIC_KEY=$(echo $KEYS_JSON | jq -r '.publicKey')

  SHORT_ID=$(echo -n $PUBLIC_KEY | xxd -r -p | sha256sum | awk '{print $1}' | cut -c1-16)

  echo "$PRIVATE_KEY|$PUBLIC_KEY|$SHORT_ID"
}

# 用户输入端口和伪装域名
read -p "请输入VLESS监听端口（建议1024-65535，例如443）: " PORT
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "端口号输入错误，退出。"
  exit 1
fi

read -p "请输入伪装域名（必须已解析到本服务器IP）: " REALITY_REPLACE_DOMAIN
if [ -z "$REALITY_REPLACE_DOMAIN" ]; then
  echo "伪装域名不能为空，退出。"
  exit 1
fi

UUID=$(generate_uuid)
echo "生成的UUID为：$UUID"

KEYS=$(generate_reality_keys)
PRIVATE_KEY=$(echo $KEYS | cut -d '|' -f1)
PUBLIC_KEY=$(echo $KEYS | cut -d '|' -f2)
SHORT_ID=$(echo $KEYS | cut -d '|' -f3)

echo "生成的Reality密钥对和shortId如下："
echo "PrivateKey: $PRIVATE_KEY"
echo "PublicKey:  $PUBLIC_KEY"
echo "ShortId:    $SHORT_ID"

echo "正在安装xray-core..."
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -q -O xray.zip https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip
unzip -o xray.zip -d /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json << EOF
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
          "dest": "$REALITY_REPLACE_DOMAIN:443",
          "xver": 0,
          "serverNames": [
            "$REALITY_REPLACE_DOMAIN"
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
      "protocol": "freedom"
    }
  ]
}
EOF

cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 生成客户端链接（VLESS URI）
# 格式示例：
# vless://UUID@domain:port?security=reality&encryption=none&type=tcp&flow=xtls-rprx-direct&pb=PUBLIC_KEY_BASE64&sid=SHORT_ID&fp=chrome#备注
# 其中pb需要base64编码公钥，sid是shortId，fp可随意填写（常用chrome）

# base64公钥无换行，无加号换成-
PB_BASE64=$(echo -n $PUBLIC_KEY | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')

CLIENT_LINK="vless://${UUID}@${REALITY_REPLACE_DOMAIN}:${PORT}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-direct&pb=${PB_BASE64}&sid=${SHORT_ID}&fp=chrome#VLESS+Reality"

echo "==============================================="
echo "安装完成！"
echo "VLESS + TCP + Reality 服务已启动"
echo "监听端口：$PORT"
echo "伪装域名：$REALITY_REPLACE_DOMAIN"
echo "UUID：$UUID"
echo "Reality shortId：$SHORT_ID"
echo ""
echo "客户端连接链接 (VLESS URI)："
echo "$CLIENT_LINK"
echo ""
echo "下面是二维码（用手机客户端扫码导入）："
qrencode -t ansiutf8 "$CLIENT_LINK"
echo "==============================================="
