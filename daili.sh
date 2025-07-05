#!/bin/bash

set -e

# 1. 配置参数，修改为你自己的域名和端口
DOMAIN="npc.qzz.io"    # 伪装域名，务必已正确解析到VPS IP
PORT=4433               # 建议使用443端口，也可改为其他（1-65535）

echo "开始部署 Xray VLESS+TCP+Reality 节点"
echo "域名: $DOMAIN"
echo "端口: $PORT"

# 2. 安装依赖
apt update
apt install -y curl jq

# 3. 安装 Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 4. 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID：$UUID"

# 5. 生成 Reality 公私钥
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk 'NR==1{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk 'NR==2{print $2}')
echo "生成 Reality 密钥对完成"

# 6. 生成配置文件
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

echo "配置文件已写入 $CONFIG_PATH"

# 7. 启用并启动 Xray 服务
systemctl enable xray
systemctl restart xray

# 8. 输出客户端配置和示例链接
echo -e "\n部署完成！请保存以下信息：\n"
echo "服务器域名（伪装域名）：$DOMAIN"
echo "端口：$PORT"
echo "UUID：$UUID"
echo "Reality 公钥（客户端填写）：$PUBLIC_KEY"
echo "Reality 私钥（服务器端保留）：$PRIVATE_KEY"

echo -e "\n小火箭（Shadowrocket）示例订阅链接："
echo "vless://$UUID@$DOMAIN:$PORT?security=reality&encryption=none&type=tcp&headerType=none&flow=&pbk=$PUBLIC_KEY#Reality节点"

echo -e "\n请确保域名已正确解析，端口已放行。"
