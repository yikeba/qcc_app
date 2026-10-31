<p align="center"><img src="assets/qcc.png" width="120" alt="QCC"></p>

# qcc_app — QCC Flutter 客户端

> QCC（Quantum Container Chain）官方开源客户端。基于 Flutter，使用 **ML-DSA-87（FIPS 204）** 后量子签名，一套代码覆盖 Android / iOS / macOS / Windows / Linux。

*An open-source Flutter wallet & client for QCC — a post-quantum blockchain OS. All transactions are signed with ML-DSA-87 via liboqs.*

---

## 功能概览

| 模块 | 目录 | 说明 |
|---|---|---|
| 后量子钱包 | `lib/qccwallet` | 24 词助记词、由种子确定性派生 ML-DSA-87 密钥对、本地加密存储、签名与验签 |
| 转账与交易 | `lib/txdata/tx`、`lib/txdata/Multi` | 单签转账、多签发起与跟签、交易确认与状态追踪 |
| 资产规则 | `lib/rule/asset` | 资产 / 稳定币发行、多签铸造、销毁、冻结、白名单资产 |
| 用户规则 | `lib/rule/user` | 标签（Tag）、支付、商户、开发者等用户级规则，多签账户创建 |
| 质押 | `lib/rule/pledge` | 单签 / 多签质押、授权、节点质押、质押记录 |
| 链上数据 | `lib/txdata/data` | 实体数据上链（存证）与记录查询 |
| 继承与借贷 | `lib/txdata/inherit`、`lib/txdata/txloan` | 资产继承设置、链上借贷的发放与还款 |
| DEX | `lib/views/dex` | 开放市场、挂单撮合、行情与订单管理 |
| 节点 | `lib/qccnodemap` | 节点地图、生产者集群、矿工奖励与利息账本 |
| 系统 | `lib/qccsys` | 创世容器、系统资金池查看 |
| QccMail | `lib/email` | 内置邮件客户端（收发、MIME 解析、本地缓存） |
| 协议层 | `lib/procotol` | QCC 交易 / 规则 / 数据的报文结构与 HTTP API 封装 |

---

## 环境要求

- Flutter SDK：Dart `^3.11.0`
- 后量子加密：[liboqs](https://github.com/open-quantum-safe/liboqs)（Dart 绑定 `liboqs: ^1.2.0`）
- 各平台对应的原生工具链（Xcode / Android Studio / Visual Studio 2022）

---

## 编译

### Android / iOS / macOS ✅ 已测试

可直接一次性编译，无需额外步骤：

```bash
flutter pub get
flutter run            # 或 flutter build apk / ios / macos
```

> iOS / macOS 首次编译前请先 `cd ios && pod install`（macOS 同理）。

### Windows ⚠️ 需要手动准备 liboqs

Windows 平台**不能依赖 pub 的本地拉取**，需要开发者自行下载 / 编译 liboqs 1.2.0，并放到指定目录：

1. **获取 liboqs 1.2.0**

   从 [open-quantum-safe/liboqs](https://github.com/open-quantum-safe/liboqs/releases) 下载 1.2.0 源码，用 Visual Studio 2022 编译为动态库（必须包含 ML-DSA）：

   ```powershell
   cmake -S liboqs -B build -G "Visual Studio 17 2022" -A x64 ^
         -DBUILD_SHARED_LIBS=ON -DOQS_BUILD_ONLY_LIB=ON
   cmake --build build --config Release
   ```

   产物为 `build\bin\Release\oqs.dll`。

2. **放入指定目录**

   客户端在 Windows 上通过 `DynamicLibrary.open('oqs.dll')` 加载（见 `lib/qccwallet/MLDSA87Sizes.dart`），因此 `oqs.dll` 必须与可执行文件位于同一目录：

   ```
   windows/<指定目录>/oqs.dll                    ← 替代本地拉取的版本
   build/windows/x64/runner/Release/oqs.dll     ← 运行时实际加载位置
   ```

3. **编译运行**

   ```bash
   flutter pub get
   flutter build windows
   ```

   若启动时报 `Failed to load dynamic library 'oqs.dll'`，说明 dll 未拷贝到 exe 同级目录，或位数不匹配（必须是 x64）。

### Linux ❓ 未测试

代码已包含 Linux 分支（加载 `liboqs.so`），但**官方尚未测试**，请开发者自行验证。大致步骤：编译 liboqs 1.2.0 为共享库（`-DBUILD_SHARED_LIBS=ON`），确保 `liboqs.so` 位于系统库路径或 `LD_LIBRARY_PATH` 中，然后 `flutter build linux`。

欢迎提交 Linux 的测试结果和修复 PR。

---

## 平台支持状态

| 平台 | 状态 |
|---|---|
| Android | ✅ 已测试 |
| iOS | ✅ 已测试 |
| macOS | ✅ 已测试 |
| Windows | ✅ 可用（需手动放置 `oqs.dll`） |
| Linux | ❓ 未测试 |

---

## 安全说明

- 私钥与助记词仅保存在本地，任何情况下都不会上传。
- 签名算法统一为 ML-DSA-87，与 QCC 节点端（Java）保持一致；**请勿替换为其他参数集**，否则签名将无法上链验证。
- 发现安全问题请邮件联系 dev@osnsg.com，不要直接公开提交 issue。

---

## 相关链接

| 文档 | 中文 | English |
|---|---|---|
| 白皮书（全版） | [QCC_FULL_CN.md](assets/qcc/QCC_FULL_CN.md) | [QCC_FULL_EN.md](assets/qcc/QCC_FULL_EN.md) |
| 简约版 | [QCC_MINI_CN.md](assets/qcc/QCC_MINI_CN.md) | [QCC_MINI_EN.md](assets/qcc/QCC_MINI_EN.md) |
| 演示稿 | [qcc_ppt.html](assets/qcc/qcc_ppt.html)（下载后用浏览器打开） | |

- 测试网浏览器：https://test.qccio.com

## License

见 [LICENSE](LICENSE)。