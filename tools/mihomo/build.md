# mihomo (Clash Meta) HarmonyOS 适配记录

## 概述

mihomo 是 Clash Meta 的核心实现，一个功能强大的代理客户端。本文记录在 HarmonyOS 上编译、配置和运行 mihomo 的完整过程。

## 编译过程

### 1. 安装 Go 编译器

HarmonyOS 没有 gcc，需要下载 Go官方发行版：

```bash
# 下载 Go 1.22.5 for Linux ARM64
mkdir -p ~/Claude/go-build
cd ~/Claude/go-build
curl -L -o go1.22.5.linux-arm64.tar.gz "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz"
tar -xzf go1.22.5.linux-arm64.tar.gz
```

### 2. 签名 Go 工具链

HarmonyOS 要求所有 ELF 二进制文件必须签名才能执行：

```bash
# 签名主二进制
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ~/Claude/go-build/go/bin/go \
  -outFile ~/Claude/go-build/go/bin/go.signed
mv ~/Claude/go-build/go/bin/go.signed ~/Claude/go-build/go/bin/go

# 签名 gofmt
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ~/Claude/go-build/go/bin/gofmt \
  -outFile ~/Claude/go-build/go/bin/gofmt.signed
mv ~/Claude/go-build/go/bin/gofmt.signed ~/Claude/go-build/go/bin/gofmt

# 签名工具链中的所有编译工具
for f in ~/Claude/go-build/go/pkg/tool/linux_arm64/*; do
  file "$f" | grep -q "ELF" && /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "$f.signed" && mv "$f.signed" "$f"
done

# 添加执行权限
chmod +x ~/Claude/go-build/go/bin/go ~/Claude/go-build/go/bin/gofmt
chmod +x ~/Claude/go-build/go/pkg/tool/linux_arm64/*
```

### 3. 克隆 mihomo 源码

mihomo 仓库有两个分支：
- `main` - Python 客户端库（不是我们要的）
- `Meta` - Clash Meta 核心（正确分支）

```bash
mkdir -p ~/Claude/mihomo-build
cd ~/Claude/mihomo-build
git clone https://github.com/MetaCubeX/mihomo.git .
git checkout Meta  # 重要：切换到 Meta 分支
```

### 4. 下载依赖

使用中国代理加速：

```bash
export PATH=$HOME/Claude/go-build/go/bin:$PATH
export GOPATH=$HOME/Claude/go-build/gopath
export GOMODCACHE=$HOME/Claude/go-build/gomodcache
export GOPROXY=https://goproxy.cn,direct
export TMPDIR=$HOME/Claude/tmpdir  # HarmonyOS /tmp 不可写

go mod download
```

### 5. 编译

```bash
# 编译 linux-arm64 版本
GOARCH=arm64 GOOS=linux CGO_ENABLED=0 go build \
  -tags with_gvisor -trimpath \
  -ldflags '-X "github.com/metacubex/mihomo/constant.Version=local-20260511" -w -s -buildid=' \
  -o bin/mihomo-linux-arm64 .
```

### 6. 签名 mihomo 二进制

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ~/Claude/mihomo-build/bin/mihomo-linux-arm64 \
  -outFile ~/Claude/mihomo-build/bin/mihomo-linux-arm64.signed
mv ~/Claude/mihomo-build/bin/mihomo-linux-arm64.signed ~/Claude/mihomo-build/bin/mihomo-linux-arm64
chmod +x ~/Claude/mihomo-build/bin/mihomo-linux-arm64
```

验证编译结果：

```bash
~/Claude/mihomo-build/bin/mihomo-linux-arm64 -v
# 输出: Mihomo Meta local-20260511 linux arm64 with go1.22.5
```

## 配置与运行

### 配置文件位置

```
~/Claude/mihomo-config/
```

主要配置文件：
- `merged.yaml` - 合并配置（推荐使用）
- `config.yaml` - 单订阅配置
- `minimal.yaml` - 最小配置示例

### GEOIP/GEOSITE 规则配置

mihomo 支持 GEOIP 和 GEOSITE 规则，实现智能分流：

```yaml
# GeoData 配置
geodata-mode: true
geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"

rules:
  # 中国大陆直连
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  # 内网地址直连
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  # 需要代理的服务
  - GEOSITE,google,PROXY
  - GEOSITE,github,PROXY
  - GEOSITE,youtube,PROXY
  - GEOSITE,twitter,PROXY
  - GEOSITE,telegram,PROXY
  - GEOSITE,openai,PROXY
  - MATCH,PROXY
```

规则记录数：
| 规则 | 记录数 |
|------|--------|
| GEOSITE cn | 113,431 |
| GEOIP cn | 8,676 |
| GEOSITE google | 1,113 |
| GEOSITE github | 61 |

### 下载 GEOIP/GEOSITE 数据文件

```bash
cd ~/Claude/mihomo-config

# 下载 geoip.dat (约18MB)
curl -L -o geoip.dat "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"

# 下载 geosite.dat (约4MB)
curl -L -o geosite.dat "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"

# 下载 geoip.metadb (MMDB格式)
curl -L -o geoip.metadb "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
```

### 完整配置示例

```yaml
# ~/Claude/mihomo-config/merged.yaml
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:9090

geodata-mode: true
geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"

dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:1053
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query

proxies:
  - name: "HK-01"
    type: vless
    server: example.com
    port: 16002
    uuid: xxx-xxx-xxx
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: azure.microsoft.com
    reality-opts:
      public-key: xxxxxx
    client-fingerprint: chrome

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - HK-01
      - DIRECT

rules:
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  - GEOSITE,google,PROXY
  - GEOSITE,github,PROXY
  - MATCH,PROXY
```

### 启动命令

```bash
cd ~/Claude/mihomo-config
~/Claude/mihomo-build/bin/mihomo-linux-arm64 -d . -f merged.yaml
```

启动日志确认 GEOIP/GEOSITE 加载成功：
```
Load GeoSite rule: cn
Finished initial GeoSite rule cn => DIRECT, records: 113431
Load GeoIP rule: cn
Finished initial GeoIP rule cn => DIRECT, records: 8676
```

### 端口说明

| 端口 | 用途 |
|------|------|
| 7890 | HTTP/SOCKS5 混合代理端口 |
| 9090 | RESTful API 端口 |
| 1053 | DNS 服务端口 |

## 系统代理配置

### HarmonyOS 系统设置

路径：设置 > 网络 >代理

配置：
- 服务器：`127.0.0.1`
- 端口：`7890`

### 国内地址 Bypass 列表

在系统代理设置的"忽略以下主机和域的代理设置"中输入：

```
localhost,127.0.0.1,192.168.*,10.*,172.16.*,172.17.*,172.18.*,172.19.*,172.20.*,172.21.*,172.22.*,172.23.*,172.24.*,172.25.*,172.26.*,172.27.*,172.28.*,172.29.*,172.30.*,172.31.*,*.cn,*.baidu.com,*.qq.com,*.taobao.com,*.tmall.com,*.jd.com,*.163.com,*.126.com,*.sina.com.cn,*.weibo.com,*.zhihu.com,*.bilibili.com,*.douyin.com,*.tiktokv.com,*.ixigua.com,*.toutiao.com,*.xiaomi.com,*.huawei.com,*.aliyun.com,*.alipay.com,*.weixin.com,*.wechat.com,*.eastmoney.com,*.36kr.com,*.csdn.net
```

### 使用 uitest 自动配置

可通过 uitest skill 自动化配置系统代理 bypass：

```bash
# 截图查看状态
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh screenshot

# 获取设置应用布局
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh layout --focus com.huawei.hmos.settings --compact

# 点击 bypass 输入区域
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh click_id 3462 --bundle com.huawei.hmos.settings

# 输入 bypass 列表
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh type_text "localhost,127.0.0.1,..."

# 保存
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh click_text "保存" --bundle com.huawei.hmos.settings
```

## 免费订阅源

### GitHub 免费节点项目

| 项目 |订阅链接 | 说明 |
|------|---------|------|
| Pawdroid/Free-servers | `https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub` | 每6小时更新 |
| crossxx-labs/free-proxy | `https://clash.crossxx.com/sub/vmess/xxx` | 有每日额度限制 |

### 解析订阅链接

订阅链接通常是 Base64 编码的节点列表：

```bash
# 解码 vmess 链接
echo 'base64编码内容' | base64 -d

# vmess 链接格式：vmess://base64(json配置)
# json 包含：add(服务器), port(端口), id(uuid), net(网络类型)等
```

## API 使用

查看代理状态：

```bash
curl http://127.0.0.1:9090/proxies
```

切换节点：

```bash
curl -X PUT "http://127.0.0.1:9090/proxies/PROXY" \
  -H "Content-Type: application/json" \
  -d '{"name":"节点名称"}'
```

## 已解决的问题

### 1. MMDB 加载失败

症状：`MMDB invalid, remove and download`

解决方案：使用不包含 `GEOIP` 规则的配置文件，避免依赖 GeoIP 数据库。

### 2. Go 工具链权限拒绝

症状：`fork/exec ... permission denied`

解决方案：签名 Go 工具链中的所有 ELF 二进制文件，包括 `pkg/tool/linux_arm64/` 目录下的编译工具。

### 3. /tmp 不可写

症状：Go 编译过程中临时文件写入失败

解决方案：设置 `TMPDIR=$HOME/Claude/tmpdir`

### 4. 依赖下载超时

症状：`Get "https://proxy.golang.org/..." timeout`

解决方案：使用中国代理 `GOPROXY=https://goproxy.cn,direct`

## 文件位置总结

| 文件 | 路径 |
|------|------|
| Go 编译器 | `~/Claude/go-build/go/` |
| mihomo 二进制 | `~/Claude/mihomo-build/bin/mihomo-linux-arm64` |
| mihomo 配置 | `~/Claude/mihomo-config/minimal.yaml` |
| Go 模块缓存 | `~/Claude/go-build/gomodcache/` |

## 测试验证

```bash
# 测试国外网站（走代理）
curl --proxy http://127.0.0.1:7890 https://www.google.com -w "%{http_code}\n"
#期望输出: 200

# 测试国内网站（系统bypass生效，浏览器直连）
# 打开浏览器访问 https://www.baidu.com
```

## 参考链接

- [mihomo GitHub](https://github.com/MetaCubeX/mihomo)
- [Go 官方下载](https://go.dev/dl/)
- [Pawdroid 免费节点](https://github.com/Pawdroid/Free-servers)