#!/bin/bash

# 一键部署 Xray VLESS+TCP+Reality 服务器脚本
# 适用 Ubuntu 20.04+ 系统
# 只需修改 DOMAIN 和 PORT 即可

set -e

# 1. 配置参数
DOMAIN="npc.qzz.io"   # 替换成你的伪装域名，必须DNS解析指向VPS
PORT=5634                 # 推荐443，非必需，可以改成其他端口（1-65535）

echo "正在部署 VLESS+TCP+Reality 节点..."
echo "域名: $DOMAIN"
echo "端口: $PORT"

# 2. 安装依赖与 Xray
apt update && apt install -y curl jq
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 3. 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

# 4. 生成 Reality 公私钥对
echo "生成 Reality 公私钥对..."
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk 'NR==1{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk 'NR==2{print $2}')
echo "Private key: $PRIVATE_KEY"
echo "Public key: $PUBLIC_KEY"

# 5. 写入 Xray 配置文件
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

# 6. 开启并启动 xray 服务
systemctl enable xray
systemctl restart xray

# 7. 输出客户端配置信息和示例链接

echo -e "\n部署完成！请保存以下信息：\n"
echo "服务器地址（伪装域名）：$DOMAIN"
echo "端口：$PORT"
echo "UUID：$UUID"
echo "Reality 公钥（客户端填写）：$PUBLIC_KEY"
echo "Reality 私钥（客户端可选，主要服务器端用）：$PRIVATE_KEY"

# 8. 生成小火箭(Shadowrocket)客户端链接示范
echo -e "\n小火箭(Shadowrocket)示例订阅链接 (请根据实际信息替换)："
echo "vless://$UUID@$DOMAIN:$PORT?security=reality&encryption=none&type=tcp&headerType=none&flow=&pbk=$PUBLIC_KEY#Reality节点"

echo -e "\n脚本执行完毕。请确认域名已正确解析，端口未被占用。"
