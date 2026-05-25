# mihomo (Clash Meta) HarmonyOS Adaptation Notes

> **中文版本见 build.cn.md**

## Overview

mihomo is the core implementation of Clash Meta, a powerful proxy client. This document records the complete process of compiling, configuring, and running mihomo on HarmonyOS.

## Build Process

### 1. Install Go Compiler

HarmonyOS has no gcc, need to download the official Go release:

```bash
# Download Go 1.22.5 for Linux ARM64
mkdir -p ~/Claude/go-build
cd ~/Claude/go-build
curl -L -o go1.22.5.linux-arm64.tar.gz "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz"
tar -xzf go1.22.5.linux-arm64.tar.gz
```

### 2. Sign Go Toolchain

HarmonyOS requires all ELF binaries to be signed before execution:

```bash
# Sign main binary
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ~/Claude/go-build/go/bin/go \
  -outFile ~/Claude/go-build/go/bin/go.signed
mv ~/Claude/go-build/go/bin/go.signed ~/Claude/go-build/go/bin/go

# Sign gofmt
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ~/Claude/go-build/go/bin/gofmt \
  -outFile ~/Claude/go-build/go/bin/gofmt.signed
mv ~/Claude/go-build/go/bin/gofmt.signed ~/Claude/go-build/go/bin/gofmt

# Sign all compilation tools in the toolchain
for f in ~/Claude/go-build/go/pkg/tool/linux_arm64/*; do
  file "$f" | grep -q "ELF" && /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "$f.signed" && mv "$f.signed" "$f"
done

# Add execution permissions
chmod +x ~/Claude/go-build/go/bin/go ~/Claude/go-build/go/bin/gofmt
chmod +x ~/Claude/go-build/go/pkg/tool/linux_arm64/*
```

### 3. Clone mihomo Source

The mihomo repository has two branches:
- `main` - Python client library (not what we need)
- `Meta` - Clash Meta core (correct branch)

```bash
mkdir -p ~/Claude/mihomo-build
cd ~/Claude/mihomo-build
git clone https://github.com/MetaCubeX/mihomo.git .
git checkout Meta  # Important: switch to Meta branch
```

### 4. Download Dependencies

Use China proxy for acceleration:

```bash
export PATH=$HOME/Claude/go-build/go/bin:$PATH
export GOPATH=$HOME/Claude/go-build/gopath
export GOMODCACHE=$HOME/Claude/go-build/gomodcache
export GOPROXY=https://goproxy.cn,direct
export TMPDIR=$HOME/Claude/tmpdir  # HarmonyOS /tmp is not writable

go mod download
```

### 5. Build

```bash
# Build linux-arm64 version
GOARCH=arm64 GOOS=linux CGO_ENABLED=0 go build \
  -tags with_gvisor -trimpath \
  -ldflags '-X "github.com/metacubex/mihomo/constant.Version=local-20260511" -w -s -buildid=' \
  -o bin/mihomo-linux-arm64 .
```

### 6. Sign mihomo Binary

```bash
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile ~/Claude/mihomo-build/bin/mihomo-linux-arm64 \
  -outFile ~/Claude/mihomo-build/bin/mihomo-linux-arm64.signed
mv ~/Claude/mihomo-build/bin/mihomo-linux-arm64.signed ~/Claude/mihomo-build/bin/mihomo-linux-arm64
chmod +x ~/Claude/mihomo-build/bin/mihomo-linux-arm64
```

Verify build result:

```bash
~/Claude/mihomo-build/bin/mihomo-linux-arm64 -v
# Output: Mihomo Meta local-20260511 linux arm64 with go1.22.5
```

## Configuration and Running

### Configuration File Location

```
~/Claude/mihomo-config/
```

Main configuration files:
- `merged.yaml` - Merged configuration (recommended)
- `config.yaml` - Single subscription configuration
- `minimal.yaml` - Minimal configuration example

### GEOIP/GEOSITE Rule Configuration

mihomo supports GEOIP and GEOSITE rules for intelligent traffic routing:

```yaml
# GeoData configuration
geodata-mode: true
geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"

rules:
  # China mainland direct connection
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  # Private network addresses direct connection
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  # Services requiring proxy
  - GEOSITE,google,PROXY
  - GEOSITE,github,PROXY
  - GEOSITE,youtube,PROXY
  - GEOSITE,twitter,PROXY
  - GEOSITE,telegram,PROXY
  - GEOSITE,openai,PROXY
  - MATCH,PROXY
```

Rule record counts:
| Rule | Records |
|------|---------|
| GEOSITE cn | 113,431 |
| GEOIP cn | 8,676 |
| GEOSITE google | 1,113 |
| GEOSITE github | 61 |

### Download GEOIP/GEOSITE Data Files

```bash
cd ~/Claude/mihomo-config

# Download geoip.dat (~18MB)
curl -L -o geoip.dat "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"

# Download geosite.dat (~4MB)
curl -L -o geosite.dat "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"

# Download geoip.metadb (MMDB format)
curl -L -o geoip.metadb "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
```

### Complete Configuration Example

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

### Startup Command

```bash
cd ~/Claude/mihomo-config
~/Claude/mihomo-build/bin/mihomo-linux-arm64 -d . -f merged.yaml
```

Startup log confirms GEOIP/GEOSITE loaded successfully:
```
Load GeoSite rule: cn
Finished initial GeoSite rule cn => DIRECT, records: 113431
Load GeoIP rule: cn
Finished initial GeoIP rule cn => DIRECT, records: 8676
```

### Port Description

| Port | Purpose |
|------|---------|
| 7890 | HTTP/SOCKS5 mixed proxy port |
| 9090 | RESTful API port |
| 1053 | DNS service port |

## System Proxy Configuration

### HarmonyOS System Settings

Path: Settings > Network > Proxy

Configuration:
- Server: `127.0.0.1`
- Port: `7890`

### Domestic Address Bypass List

In the system proxy settings "Skip proxy for these hosts and domains", enter:

```
localhost,127.0.0.1,192.168.*,10.*,172.16.*,172.17.*,172.18.*,172.19.*,172.20.*,172.21.*,172.22.*,172.23.*,172.24.*,172.25.*,172.26.*,172.27.*,172.28.*,172.29.*,172.30.*,172.31.*,*.cn,*.baidu.com,*.qq.com,*.taobao.com,*.tmall.com,*.jd.com,*.163.com,*.126.com,*.sina.com.cn,*.weibo.com,*.zhihu.com,*.bilibili.com,*.douyin.com,*.tiktokv.com,*.ixigua.com,*.toutiao.com,*.xiaomi.com,*.huawei.com,*.aliyun.com,*.alipay.com,*.weixin.com,*.wechat.com,*.eastmoney.com,*.36kr.com,*.csdn.net
```

### Using uitest for Auto-Configuration

You can automate system proxy bypass configuration via the uitest skill:

```bash
# Screenshot to view status
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh screenshot

# Get settings app layout
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh layout --focus com.huawei.hmos.settings --compact

# Click bypass input area
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh click_id 3462 --bundle com.huawei.hmos.settings

# Type bypass list
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh type_text "localhost,127.0.0.1,..."

# Save
sh ~/Claude/.claude/skills/uitest/scripts/uitest_helper.sh click_text "保存" --bundle com.huawei.hmos.settings
```

## Free Subscription Sources

### GitHub Free Node Projects

| Project | Subscription Link | Description |
|---------|-------------------|-------------|
| Pawdroid/Free-servers | `https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub` | Updated every 6 hours |
| crossxx-labs/free-proxy | `https://clash.crossxx.com/sub/vmess/xxx` | Has daily quota limit |

### Parsing Subscription Links

Subscription links are usually Base64-encoded node lists:

```bash
# Decode vmess link
echo 'base64-encoded-content' | base64 -d

# vmess link format: vmess://base64(json config)
# json contains: add(server), port, id(uuid), net(network type), etc.
```

## API Usage

View proxy status:

```bash
curl http://127.0.0.1:9090/proxies
```

Switch node:

```bash
curl -X PUT "http://127.0.0.1:9090/proxies/PROXY" \
  -H "Content-Type: application/json" \
  -d '{"name":"node-name"}'
```

## Resolved Issues

### 1. MMDB Loading Failure

Symptom: `MMDB invalid, remove and download`

Solution: Use a configuration file that does not include `GEOIP` rules, avoiding dependency on the GeoIP database.

### 2. Go Toolchain Permission Denied

Symptom: `fork/exec ... permission denied`

Solution: Sign all ELF binaries in the Go toolchain, including compilation tools in the `pkg/tool/linux_arm64/` directory.

### 3. /tmp Not Writable

Symptom: Go compilation temporary file write failure

Solution: Set `TMPDIR=$HOME/Claude/tmpdir`

### 4. Dependency Download Timeout

Symptom: `Get "https://proxy.golang.org/..." timeout`

Solution: Use China proxy `GOPROXY=https://goproxy.cn,direct`

## File Location Summary

| File | Path |
|------|------|
| Go compiler | `~/Claude/go-build/go/` |
| mihomo binary | `~/Claude/mihomo-build/bin/mihomo-linux-arm64` |
| mihomo config | `~/Claude/mihomo-config/minimal.yaml` |
| Go module cache | `~/Claude/go-build/gomodcache/` |

## Test Verification

```bash
# Test international website (via proxy)
curl --proxy http://127.0.0.1:7890 https://www.google.com -w "%{http_code}\n"
# Expected output: 200

# Test domestic website (system bypass active, browser direct connection)
# Open browser and visit https://www.baidu.com
```

## Reference Links

- [mihomo GitHub](https://github.com/MetaCubeX/mihomo)
- [Go Official Download](https://go.dev/dl/)
- [Pawdroid Free Nodes](https://github.com/Pawdroid/Free-servers)