# Apple 根证书（验签用，**入库**）

| 项 | 值 |
|---|---|
| 文件 | `AppleRootCA-G3.pem` |
| 来源 | https://www.apple.com/certificateauthority/AppleRootCA-G3.cer |
| 下载日期 | 2026-11-05 |
| 主体 | `CN=Apple Root CA - G3, OU=Apple Certification Authority, O=Apple Inc., C=US` |
| 有效期 | 2014-04-30 → 2039-04-30 |
| SHA-256 | `63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79` |
| SHA-1 | `B5:2C:B0:2F:D5:67:E0:35:9F:E8:FA:4D:4C:41:03:79:70:FE:01:B0` |

## 为什么入库、不运行时下载

验签发生在**每个** `/v1/billing/verify` 与 Apple 通知请求上。如果运行时去 apple.com 拉证书，
那就等于把"支付验签"挂在一个网络请求上：网络抖动 = 验签失败 = 用户买了却开通不了；
更糟的是"拉回来的到底是不是 Apple 的根"这件事本身也需要一条信任链（引导问题）。
所以根证书**随代码入库**，启动与请求都**不联网**；轮换时人工换文件并改这里。

## 怎么核这个文件没被换掉

```bash
openssl x509 -in server/apple/AppleRootCA-G3.pem -noout -fingerprint -sha256
# 应当输出上面表格里那串 SHA-256
```

`server/billing.mjs` 里也**写死了**这个 SHA-256（`APPLE_ROOT_SHA256`），启动时自检：
文件被换掉、或有人"顺手更新"了证书却没改常量，`server/billing.selftest.mjs` 会红。
