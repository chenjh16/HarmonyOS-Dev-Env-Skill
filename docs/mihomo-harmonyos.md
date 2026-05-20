# mihomo (Clash Meta) HarmonyOS Adaptation Record

## Overview

mihomo is the core implementation of Clash Meta, a powerful proxy client. This document records the complete process of compiling, configuring, and running mihomo on HarmonyOS.

## Compilation Process

### 1. Install Go Compiler

HarmonyOS doesn't have gcc, need to download official Go distribution:

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

# Sign all compiler tools in toolchain
for f in ~/Claude/go-build/go/pkg/tool/linux_arm64/*; do
  file "$f" | grep -q "ELF" && /data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -inFile "$f" -outFile "$f.signed" && mv "$f.signed" "$f"
done

# Add execute permissions
chmod +x ~/Claude/go-build/go/bin/go ~/Claude/go-build/go/bin/gofmt
chmod +x ~/Claude/go-build/go/pkg/tool/linux_arm64/*
```

### 3. Clone mihomo Source

mihomo repository has two branches:
- `main` - Python client library (not what we want)
- `Meta` - Clash Meta core (correct branch)

```bash
mkdir -p ~/Claude/mihomo-build
cd ~/Claude/mihomo-build
git clone https://github.com/MetaCubeX/mihomo.git .
git checkout Meta  # Important: switch to Meta branch
```

### 4. Download Dependencies

Use China proxy to accelerate:

```bash
export PATH=$HOME/Claude/go-build/go/bin:$PATH
export GOPATH=$HOME/Claude/go-build/gopath
export GOMODCACHE=$HOME/Claude/go-build/gomodcache
export GOPROXY=https://goproxy.cn,direct
export TMPDIR=$HOME/Claude/tmpdir  # HarmonyOS /tmp not writable

go mod download
```

### 5. Compile

```bash
# Compile linux-arm64 version
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

Verify compilation result:

```bash
~/Claude/mihomo-build/bin/mihomo-linux-arm64 -v
# Output: Mihomo Meta local-20260511 linux arm64 with go1.22.5
```

## Configuration and Running

### Configuration File Location

```
~/Claude/mihomo-config/
```

Main config files:
- `merged.yaml` - Merged config (recommended)
- `config.yaml` - Single subscription config
- `minimal.yaml` - Minimal config example

### GEOIP/GEOSITE Rule Configuration

mihomo supports GEOIP and GEOSITE rules for intelligent routing:

```yaml
# GeoData configuration
geodata-mode: true
geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"

rules:
  # China direct connection
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  # Internal network direct
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  # Services needing proxy
  - GEOSITE,google,PROXY
  - GEOSITE,github,PROXY
  - GEOSITE,youtube,PROXY
  - GEOSITE,twitter,PROXY
  - GEOSITE,telegram,PROXY
  - GEOSITE,openai,PROXY
  - MATCH,PROXY
```

Rule counts:
| Rule | Records |
|------|--------|
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

### Complete Config Example

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

### Start Command

```bash
cd ~/Claude/mihomo-config
~/Claude/mihomo-build/bin/mihomo-linux-arm64 -d . -f merged.yaml
```

Startup log confirming GEOIP/GEOSITE loaded:
```
Load GeoSite rule: cn
Finished initial GeoSite rule cn => DIRECT, records: 113431
Load GeoIP rule: cn
Finished initial GeoIP rule cn => DIRECT, records: 8676
```

### Port Descriptions

| Port | Usage |
|------|-------|
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

Enter in system proxy settings "Bypass proxy for these hosts and domains":

```
localhost,127.0.0.1,192.168.*,10.*,172.16.*,172.17.*,172.18.*,172.19.*,172.20.*,172.21.*,172.22.*,172.23.*,172.24.*,172.25.*,172.26.*,172.27.*,172.28.*,172.29.*,172.30.*,172.31.*,*.cn,*.baidu.com,*.qq.com,*.taobao.com,*.tmall.com,*.jd.com,*.163.com,*.126.com,*.sina.com.cn,*.weibo.com,*.zhihu.com,*.bilibili.com,*.douyin.com,*.tiktokv.com,*.ixigua.com,*.toutiao.com,*.xiaomi.com,*.huawei.com,*.aliyun.com,*.alipay.com,*.weixin.com,*.wechat.com,*.eastmoney.com,*.36kr.com,*.csdn.net
```

## Free Subscription Sources

### GitHub Free Node Projects

| Project | Subscription Link | Notes |
|---------|------------------|-------|
| Pawdroid/Free-servers | `https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub` | Updates every 6 hours |
| crossxx-labs/free-proxy | `https://clash.crossxx.com/sub/vmess/xxx` | Daily quota limit |

## API Usage

Check proxy status:

```bash
curl http://127.0.0.1:9090/proxies
```

Switch node:

```bash
curl -X PUT "http://127.0.0.1:9090/proxies/PROXY" \
  -H "Content-Type: application/json" \
  -d '{"name":"node-name"}'
```

## Known Issues and Solutions

### 1. MMDB Loading Failure

Symptom: `MMDB invalid, remove and download`

Solution: Use config without `GEOIP` rules to avoid GeoIP database dependency.

### 2. Go Toolchain Permission Denied

Symptom: `fork/exec ... permission denied`

Solution: Sign all ELF binaries in Go toolchain, including `pkg/tool/linux_arm64/` directory.

### 3. /tmp Not Writable

Symptom: Go compilation temp file write failure

Solution: Set `TMPDIR=$HOME/Claude/tmpdir`

### 4. Dependency Download Timeout

Symptom: `Get "https://proxy.golang.org/..." timeout`

Solution: Use China proxy `GOPROXY=https://goproxy.cn,direct`

## File Locations Summary

| File | Path |
|------|------|
| Go compiler | `~/Claude/go-build/go/` |
| mihomo binary | `~/Claude/mihomo-build/bin/mihomo-linux-arm64` |
| mihomo config | `~/Claude/mihomo-config/minimal.yaml` |
| Go module cache | `~/Claude/go-build/gomodcache/` |

## Test Verification

```bash
# Test foreign site (via proxy)
curl --proxy http://127.0.0.1:7890 https://www.google.com -w "%{http_code}\n"
# Expected: 200

# Test domestic site (system bypass生效, browser direct)
# Open browser and visit https://www.baidu.com
```

## References

- [mihomo GitHub](https://github.com/MetaCubeX/mihomo)
- [Go Official Download](https://go.dev/dl/)
- [Pawdroid Free Nodes](https://github.com/Pawdroid/Free-servers)