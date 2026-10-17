# iOS调试助手 (iOSDebugHelper)

基于开源 [FLEX (Flipboard FLEX)](https://github.com/FLEXTool/FLEX) 框架二次开发的 iOS 调试工具 dylib 动态库。

## 项目信息

| 项目 | 值 |
|---|---|
| 项目名称 | iOS调试助手 |
| 内部标识 | iOSDebugHelper |
| 架构 | arm64, arm64e |
| 最低系统 | iOS 14.0 |
| 语言 | 纯 Objective-C（无 Swift、无 Dart） |
| 底层依赖 | MobileSubstrate (Cydia Substrate) |
| 分发方式 | 越狱Tweak / 证书注入IPA侧载 |

## 模块清单

### 1. FLEX 原生调试能力（完整保留）
- 视图层级浏览器、对象浏览器、OC方法调用器、类浏览器
- 沙盒文件浏览器、SQLite数据库查看编辑
- Keychain钥匙串读写、UserDefaults编辑
- 系统日志查看、堆内存快照、Cookie查看、APNS推送捕获

### 2. 网络监控与拦截
- Hook NSURLSession / NSURLConnection，记录全部HTTP/WebSocket事务
- URL正则匹配规则管理器，持久化到NSUserDefaults
- 请求头重写、JSON-Path (JSON Patch) 修改响应JSON、正则替换报文
- **预置默认规则**：匹配 `/api/User/Info`，将 `result.isVip` 设为 `true`

### 3. Hook与补丁管理
- 基于 MSHookFunction / method swizzling 实现运行时OC方法Hook
- 可视化选择方法，直接修改返回值：true/false/nil/0/自定义字符串/数字
- Hook配置、补丁集合持久化存入NSUserDefaults，启动自动加载
- 一键导出为 Logos Tweak.x 代码

### 4. AES加密监控捕获
- Hook CommonCrypto (CCCrypt)、OpenSSL/BoringSSL (AES_*, EVP_*)、Security (SecKey*)、CryptoKit
- 捕获AES Key、IV、输入输出数据
- 按线程ID关联对应网络请求，自动解密响应

### 5. 智能广告&VIP扫描
- 内置关键词词库：Ad, Vip, Premium, Member, Purchase, Pay, Subscribe, Trial, Unlock, Restriction 等
- 支持用户自定义关键词，全局扫描已加载ObjC类与方法
- 自动分类：广告相关 / VIP会员付费相关 / 其他可疑类
- 展示格式：`方法名 In Class: 类名`
- **批量复制N条功能**：输入数字N，提取前N条结果拼接换行复制到剪贴板，边界校验

### 6. AI辅助分析
- 对接 DeepSeek Chat Completions API
- 支持自定义 API-Key、接口地址、模型名称
- 提交类/方法信息给AI，输出建议Hook点，自动生成Logos代码
- 可一键添加到Hook购物车

### 7. 悬浮球UI入口
- 可拖拽悬浮按钮，可调大小(30-100)、透明度、位置
- 主菜单高级功能区：智能扫描助手、数据分析、补丁管理、网络规则、全局扫描、日志查看
- 关于区：关于本工具、使用说明、版本信息、重置配置
- **已移除**：JS脚本订阅、插件官网、TG频道、原作者信息

### 8. 日志系统
- 分级日志：DEBUG / INFO / WARN / ERROR
- 持久化写入 Documents/iOSDebugHelper_Logs/ 目录
- 按日期命名：`DebugHelper_yyyyMMdd.log`

## 项目结构

```
iOSDebugHelper/
├── Makefile                          # Theos构建配置
├── iOSDebugHelper.plist              # Filter配置
├── Tweak.x                           # 入口（%ctor初始化）
├── Headers/
│   └── FLEX/                         # FLEX头文件（作为子模块引入）
├── Logger/
│   ├── DHLogManager.h/m             # 分级日志
├── Network/
│   ├── DHInterceptRule.h/m          # 拦截规则模型
│   ├── DHRuleManager.h/m            # 规则管理器
│   ├── DHJSONPatch                   # JSON Patch（集成在Rule中）
│   └── DHNetworkInterceptor.h/m      # 网络拦截器
├── Hook/
│   ├── DHHookInfo.h/m               # Hook信息模型
│   ├── DHPatch.h/m                  # 补丁模型
│   └── DHHookManager.h/m            # Hook管理器
├── Crypto/
│   └── DHCryptManager.h/m           # AES加密监控
├── Scanner/
│   ├── DHScannerResult.h/m          # 扫描结果模型
│   └── DHAdScanner.h/m              # 广告/VIP扫描器
├── AI/
│   └── DHAIManager.h/m              # DeepSeek AI分析
└── UI/
    ├── DHButtonManager.h/m          # 悬浮球
    └── DHMainMenuViewController.h/m  # 主菜单
```

## 构建方法（Theos）

```bash
# 1. 安装 Theos
git clone --recursive https://github.com/theos/theos.git $THEOS

# 2. 将 FLEX 作为子模块放入 Headers/
cd iOSDebugHelper/Headers
git clone https://github.com/FLEXTool/FLEX.git FLEX

# 3. 编译
cd ..
make package

# 输出：
# .theos/obj/debug/ios_debug_helper.dylib
# 或 deb 安装包
```

## NSUserDefaults 键一览

| Key | 用途 |
|---|---|
| `DHInterceptRules` | 网络拦截规则数组 |
| `DHInterceptEnabled` | 全局拦截开关 |
| `DHSavedHooks` | 已保存Hook列表 |
| `DHSavedPatches` | 已保存补丁列表 |
| `DHButtonSize` | 悬浮球大小 |
| `DHButtonAlpha` | 悬浮球透明度 |
| `DHButtonPosX/PosY` | 悬浮球位置 |
| `DH_AIConfig` | AI配置（Key/URL/Model） |

## 约束
- 纯 Objective-C，不引入 Swift
- 不加壳、不混淆、不反调试、不做越狱检测
- 所有配置持久化在 NSUserDefaults
- 无外部社区/作者主页跳转
