#!/bin/bash

set -e

DOMAIN="npc.qzz.io"   # 伪装域名，替换成你的
PORT=4433             # 端口

echo "部署 VLESS+TCP+Reality 节点..."
echo "域名: $DOMAIN"
echo "端口: $PORT"

# 安装依赖和 Xray
apt update && apt install -y curl jq
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

# 生成 Reality 公私钥对，准确提取
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "public key" | awk '{print $3}')

echo "Private key: $PRIVATE_KEY"
echo "Public key: $PUBLIC_KEY"

# 写配置文件
CONFIG_PATH="/usr/local/etc/xray/config.json"

cat > $CONFIG_PATH <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$UUID",
        "flow": ""
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$DOMAIN:443",
        "xver": 0,
        "servers": [{
          "server": "$DOMAIN",
          "publicKey": "$PUBLIC_KEY"
        }]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

# 启动服务
systemctl enable xray
systemctl restart xray

# 输出信息
echo -e "\n部署完成！请保存以下信息：\n"
echo "服务器域名（伪装域名）：$DOMAIN"
echo "端口：$PORT"
echo "UUID：$UUID"
echo "Reality 公钥（客户端填写）：$PUBLIC_KEY"
echo "Reality 私钥（服务器端保留）：$PRIVATE_KEY"

echo -e "\n小火箭(Shadowrocket)示例订阅链接："
echo "vless://$UUID@$DOMAIN:$PORT?security=reality&encryption=none&type=tcp&headerType=none&flow=&pbk=$PUBLIC_KEY#Reality节点"

echo -e "\n脚本执行完毕，请确认域名已正确解析，端口未被占用。"
