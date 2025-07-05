#!/bin/bash

# 一键部署 Xray VLESS+TCP+Reality 服务器脚本
# 适用 Ubuntu 20.04+ 系统
# 修改 DOMAIN 和 PORT 即可使用

set -e

# 配置项
DOMAIN="npc.qzz.io"   # 替换成你的伪装域名，且需DNS解析指向VPS
PORT=4433             # 监听端口（1-65535）

echo "开始部署 VLESS+TCP+Reality 节点..."
echo "伪装域名: $DOMAIN"
echo "端口: $PORT"

# 安装依赖
apt update
apt install -y curl jq

# 安装 Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

# 生成 Reality 公私钥对
echo "生成 Reality 公私钥对..."
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
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

# 启用并重启服务
systemctl enable xray
systemctl restart xray

echo -e "\n部署完成！请保存以下信息："
echo "服务器域名（伪装域名）：$DOMAIN"
echo "端口：$PORT"
echo "UUID：$UUID"
echo "Reality 公钥（客户端填写）：$PUBLIC_KEY"
echo "Reality 私钥（服务器端保留）：$PRIVATE_KEY"

echo -e "\n小火箭(Shadowrocket)示例订阅链接："
echo "vless://$UUID@$DOMAIN:$PORT?security=reality&encryption=none&type=tcp&headerType=none&flow=&pbk=$PUBLIC_KEY#Reality节点"

echo -e "\n请确保域名已正确解析，端口未被防火墙阻挡。"
