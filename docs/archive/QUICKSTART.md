# 🚀 AI Agent Hub - 快速开始

## 📱 功能概述

**AI Agent Hub** 是一个安全的移动应用，实现了完整的密码管理系统：

- ✅ 首次使用密码设置
- ✅ 密码验证登录
- ✅ 登录后修改密码
- ✅ 企业级加密存储

---

## 🎯 使用流程

### 1️⃣ 首次使用

```
启动应用
    ↓
[自动检测：未设置密码]
    ↓
[密码设置页面]
    ↓
输入密码 (至少6位，包含字母+数字)
确认密码
    ↓
[点击"完成设置"]
    ↓
自动跳转到登录页
```

**示例密码**: `Test123`, `Agent2024`, `Secure123`

---

### 2️⃣ 再次启动

```
启动应用
    ↓
[自动检测：已设置密码]
    ↓
[登录页面]
    ↓
输入密码
    ↓
[点击"登录"]
    ↓
进入主页
```

---

### 3️⃣ 修改密码

```
主页
    ↓
[点击右上角"设置"图标]
    ↓
[设置页面] → 点击"修改密码"
    ↓
[密码修改页面]
    ↓
输入当前密码
输入新密码
确认新密码
    ↓
[点击"确认修改"]
    ↓
修改成功，2秒后返回
```

---

## 🔐 密码要求

| 规则 | 说明 |
|------|------|
| **长度** | 6-20 位 |
| **字母** | 必须包含 (a-z, A-Z) |
| **数字** | 必须包含 (0-9) |
| **建议** | 包含特殊字符增强安全性 |

### ✅ 有效密码示例
- `Test123` ✅
- `Agent2024` ✅
- `MyPass@123` ✅
- `Secure#456` ✅

### ❌ 无效密码示例
- `12345` ❌ (无字母)
- `abcdef` ❌ (无数字)
- `Test` ❌ (长度不足)

---

## 🛡️ 安全特性

### 加密存储
- 🔐 **SHA-256** 哈希
- 🧂 **独立盐值** (每密码唯一)
- 🔒 **AES-256-GCM** 数据加密
- ✅ **只存哈希** (不存明文)

### 安全机制
- 🔒 密码输入默认遮挡
- 👁️ 可切换密码可见性
- 🚫 3次错误锁定
- 🔄 密码重置选项

---

## 💻 开发者快速开始

### 前置条件
- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0

### 1. 克隆/进入项目
```bash
cd /projects/clawd/ai-agent-hub
```

### 2. 安装依赖
```bash
flutter pub get
```

### 3. 运行测试
```bash
./test-password-system.sh
```

### 4. 启动应用
```bash
# Web (推荐用于快速测试)
flutter run -d chrome

# Android
flutter run -d android

# iOS
flutter run -d ios
```

### 5. 构建发布版
```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

---

## 📦 核心文件

```
lib/
├── main.dart                       # 应用入口 + 启动页
├── services/
│   └── password_service.dart      # 密码管理核心服务
└── screens/
    ├── password_setup_screen.dart  # 首次密码设置
    ├── login_screen.dart          # 登录验证
    ├── change_password_screen.dart # 密码修改
    └── home_screen.dart           # 主页 + 设置
```

---

## 🔧 PasswordService API

```dart
// 初始化
await passwordService.init();

// 检查是否已设置密码
bool isSet = await passwordService.isPasswordSet();

// 设置密码 (首次)
bool success = await passwordService.setPassword('Test123');

// 验证密码
bool valid = await passwordService.verifyPassword('Test123');

// 修改密码
bool changed = await passwordService.changePassword('oldPass', 'newPass');

// 重置密码 (清除数据)
await passwordService.resetPassword();
```

---

## 🐛 常见问题

### Q1: 忘记密码怎么办？
**A**: 点击登录页的"忘记密码？"，选择"确认重置"。
> ⚠️ 注意：重置会清除所有本地数据

### Q2: 密码修改失败？
**A**: 确认：
1. 当前密码输入正确
2. 新密码符合要求（6-20位，包含字母+数字）
3. 新密码与当前密码不同
4. 两次新密码输入一致

### Q3: 密码输入错误3次被锁定？
**A**: 等待一段时间后会自动解锁，或重启应用

### Q4: 如何增强密码安全性？
**A**: 建议使用：
- 大小写字母混合
- 特殊字符 (`!@#$%^&*`)
- 避免常见密码
- 定期修改密码

---

## 📊 测试状态

| 测试项 | 状态 |
|--------|------|
| 项目结构 | ✅ 8/8 |
| 依赖配置 | ✅ 4/4 |
| 代码质量 | ✅ 6/6 |
| 安全特性 | ✅ 4/4 |
| UI 流程 | ✅ 5/5 |
| 文档完整性 | ✅ 4/4 |
| **总计** | **✅ 31/31 (100%)** |

---

## 📞 支持

- 📖 **完整文档**: [README.md](README.md)
- 📝 **测试报告**: [TEST-REPORT-2026-02-04.md](TEST-REPORT-2026-02-04.md)
- 🔧 **测试脚本**: `./test-password-system.sh`

---

## 🎉 开始使用

```bash
# 1. 进入项目
cd /projects/clawd/ai-agent-hub

# 2. 安装依赖
flutter pub get

# 3. 运行测试
./test-password-system.sh

# 4. 启动应用
flutter run -d chrome
```

**祝您使用愉快！** 🚀
