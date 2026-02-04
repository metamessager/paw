# AI Agent Hub - 密码管理系统

安全的 AI Agent 移动应用，支持密码保护和加密存储。

## 🔐 核心功能

### 1. 首次密码设置
- 用户首次使用时，必须先设置密码
- 密码要求：
  - 长度 6-20 位
  - 必须包含字母和数字
  - 建议包含特殊字符增强安全性
- 设置后自动跳转到登录页

### 2. 密码验证登录
- 已设置密码的用户直接进入登录页
- 输入密码验证后进入应用
- 支持密码可见性切换
- 3次错误尝试后锁定

### 3. 密码修改
- 登录后可在设置中修改密码
- 需要验证当前密码
- 新密码不能与当前密码相同
- 修改成功后立即生效

## 🛡️ 安全特性

### 密码加密存储
- 使用 SHA-256 哈希算法
- 每个密码使用唯一的盐值（Salt）
- 只存储哈希值，不存储明文
- 使用 AES-256-GCM 加密敏感数据

### 安全机制
- ✅ 密码哈希 + 盐值
- ✅ 本地加密存储（SharedPreferences）
- ✅ 登录失败限制（3次锁定）
- ✅ 密码强度验证
- ✅ 可选的重置功能

## 📱 应用流程

```
启动应用
    ↓
[SplashScreen]
检查密码状态
    ↓
    ├─→ 未设置密码 → [PasswordSetupScreen] → 设置密码 → [LoginScreen]
    │
    └─→ 已设置密码 → [LoginScreen] → 验证密码 → [HomeScreen]
                                            ↓
                                        [SettingsScreen]
                                            ↓
                                    [ChangePasswordScreen]
```

## 🗂️ 项目结构

```
lib/
├── main.dart                           # 应用入口
├── services/
│   └── password_service.dart          # 密码管理服务
└── screens/
    ├── password_setup_screen.dart     # 首次密码设置
    ├── login_screen.dart              # 登录页面
    ├── home_screen.dart               # 主页
    └── change_password_screen.dart    # 密码修改
```

## 🔧 技术栈

- **Flutter**: >=3.0.0
- **状态管理**: Provider
- **本地存储**: SharedPreferences
- **加密**: 
  - `crypto`: SHA-256 哈希
  - `encrypt`: AES-256-GCM 加密

## 📦 依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.2  # 本地存储
  crypto: ^3.0.3              # 密码哈希
  encrypt: ^5.0.3             # 数据加密
  provider: ^6.1.1            # 状态管理
```

## 🚀 使用方法

### 安装依赖

```bash
flutter pub get
```

### 运行应用

```bash
# Web
flutter run -d chrome

# Android
flutter run -d android

# iOS
flutter run -d ios
```

### 构建发布版

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## 🔐 PasswordService API

### 核心方法

```dart
// 初始化服务
await passwordService.init();

// 检查是否已设置密码
bool isSet = await passwordService.isPasswordSet();

// 设置密码（首次）
bool success = await passwordService.setPassword('password123');

// 验证密码
bool valid = await passwordService.verifyPassword('password123');

// 修改密码
bool changed = await passwordService.changePassword('oldPass', 'newPass');

// 重置密码（清除所有数据）
await passwordService.resetPassword();

// 加密/解密数据
String encrypted = passwordService.encryptData('sensitive data');
String decrypted = passwordService.decryptData(encrypted);
```

## 📝 密码策略

### 当前策略
- 最小长度：6位
- 最大长度：20位
- 必须包含：字母 + 数字
- 建议包含：特殊字符

### 未来计划
- [ ] 生物识别（指纹/面部识别）
- [ ] 密码找回（邮箱/短信）
- [ ] 密码过期提醒
- [ ] 登录历史记录
- [ ] 多设备同步

## ⚠️ 安全注意事项

1. **加密密钥管理**
   - 当前密钥硬编码在代码中
   - 生产环境应使用更安全的密钥管理方案
   - 建议使用 Flutter Secure Storage 或服务器端密钥管理

2. **密码重置**
   - 当前重置会清除所有本地数据
   - 建议实现邮箱/短信验证的找回机制

3. **网络传输**
   - 密码在本地验证，不传输到服务器
   - 如需服务器验证，务必使用 HTTPS + Token

## 🧪 测试

### 测试流程

1. **首次使用**
   - 启动应用 → 自动跳转到密码设置页
   - 设置密码 `Test123` → 跳转到登录页
   - 输入密码登录 → 进入主页

2. **再次启动**
   - 启动应用 → 自动跳转到登录页
   - 输入密码登录 → 进入主页

3. **修改密码**
   - 主页 → 设置 → 修改密码
   - 输入当前密码 + 新密码 → 确认修改

4. **错误处理**
   - 登录时输入错误密码 3 次 → 锁定
   - 修改时输入错误的当前密码 → 提示错误

## 📄 许可证

MIT License

## 👨‍💻 作者

AI Agent Hub Development Team

---

**版本**: 1.0.0  
**更新日期**: 2026-02-04
