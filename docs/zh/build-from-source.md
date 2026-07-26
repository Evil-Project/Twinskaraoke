---
outline: deep
---

# 从源码构建

如果你熟悉 Swift 开发，可以直接跳转到[第 6C 步](#c-部分更新-watch-应用的-info-设置)。

## 环境要求

1. **一台 Mac 电脑**（Xcode 仅支持 macOS，任意 Mac 均可）。
2. **一个 Apple ID**（标准免费账号即可）。
3. **你的 iPhone/iPad** 及用于连接 Mac 的 USB 数据线。

::: tip 遇到问题？
如果安装过程遇到问题，可以在 Neuro-sama Discord 服务器（neurocord）的 *「Neuro & Evil Karaoke Web Player」* 讨论串中提问，但请先自行搜索一下。
:::

## 第 1 步：准备 Apple 开发者账号

你**不需要**支付每年 $99 的 Apple Developer Program 费用即可在自己的设备上安装本应用。一个标准免费 Apple ID 即可充当个人侧载的开发者账号。

- **如果你已有 Apple ID：** 直接使用你 iPhone 上登录的那个即可。
- **如果你没有 Apple ID，或想单独注册一个：**
  1. 访问 [appleid.apple.com](https://appleid.apple.com/)。
  2. 点击右上角的**「创建你的 Apple ID」**。
  3. 填写所需信息并验证邮箱/手机号。

## 第 2 步：下载并安装 Xcode

Xcode 是 Apple 官方用于构建 iOS 应用的开发工具，完全免费，但体积较大。

1. 在 Mac 上通过 **App Store** 搜索并获取 **Xcode**。
2. 安装完成后，点击**「打开」**首次启动 Xcode。
3. Xcode 会提示「安装额外必需组件」。点击**「安装」**，并根据提示输入 Mac 登录密码，等待安装完成。

## 第 3 步：下载 Twinskaraoke 项目

1. 前往 [Twinskaraoke GitHub 仓库](https://github.com/Evil-Project/Twinskaraoke)。
2. 点击绿色的 **`<> Code`** 按钮。
3. 点击 **Download ZIP**。
4. 下载完成后，找到文件（一般在「下载」文件夹），双击 `.zip` 文件解压。

::: info
当然，你也可以通过自己喜欢的任意方式克隆仓库。
:::

## 第 4 步：将 Apple ID 添加到 Xcode

Xcode 需要你的 Apple ID 来创建免费临时签名证书，这样你的 iPhone 才会接受该应用。

1. 打开 **Xcode**。
2. 在顶部菜单栏点击 **Xcode** → **Settings...**（或 Preferences）。
3. 点击设置窗口顶部的 **Accounts** 标签。
4. 点击左下角的 **`+`** 按钮，选择 **Apple ID**，然后点击 **Continue**。
5. 输入你的 Apple ID 和密码登录。
6. 你应该能在列表中看到你的名字，角色显示为「(Personal Team)」。关闭此窗口。

## 第 5 步：打开项目

1. 打开解压后的 `Twinskaraoke-main` 文件夹。
2. 找到 Xcode 项目文件（名称为 `Twinskaraoke.xcodeproj`），双击在 Xcode 中打开。
3. 如果 Mac 询问是否信任并打开从互联网下载的项目，点击**「Trust and Open」**。

## 第 6 步：修复「Team」与「Bundle Identifier」报错

### A 部分：更新主 iOS 应用

1. 在 Xcode 最左侧的文件导航栏中，点击最顶部的蓝色图标 **Twinskaraoke**。
2. 在 Xcode 中间区域，找到 **TARGETS** 列表，点击 **Twinskaraoke**（第一个）。
3. 点击中间区域顶部的 **Signing & Capabilities** 标签。
4. 勾选 **Automatically manage signing**（通常已默认勾选）。
5. 在 **Team** 下拉菜单中，将红色「Unknown Name」改为 **你的名字 (Personal Team)**。
6. **关键步骤：** 你必须将 **Bundle Identifier** 改为全局唯一的名称。
   - 当前显示为：`org.evilneuro.Twinskaraoke`
   - 将 `evilneuro` 替换为你的名字（不含空格）。例如：`com.zhangsan.Twinskaraoke`
   - 输入后按 `Enter`。Xcode 短暂加载后，红色报错应消失。

### B 部分：更新 Watch 应用目标

由于本项目包含 Apple Watch 组件，你**必须**同步更新其标识符，否则编译会失败。

1. 在中间面板左侧的 **TARGETS** 列表中，点击 **Twinskaraoke Watch App**。
2. 切换到 **Signing & Capabilities** 标签。
3. 将 **Team** 下拉菜单改为**你的名字 (Personal Team)**。
4. 将 **Bundle Identifier** 改为与 A 部分完全一致，但保留末尾的 `.watchkitapp`。
   - 示例：`com.zhangsan.Twinskaraoke.watchkitapp`
   - 按 `Enter` 确认。

### C 部分：更新 Watch 应用的 Info 设置

此步骤将 Watch 应用关联到手机应用。

1. 保持选中 **Twinskaraoke Watch App** 目标，点击顶部的 **Info** 标签（位于 Resource Tags / Build Settings 旁边）。
2. 在键值列表中找到 **`WKCompanionAppBundleIdentifier`**。
3. 在「Value」列中双击编辑。
4. 将其改为 A 部分中主应用的**完整 Bundle Identifier**。

::: danger 注意
**不要**在此值末尾添加 `.watchkitapp`！
- **正确：** `com.zhangsan.Twinskaraoke`
- **错误：** `com.zhangsan.Twinskaraoke.watchkitapp`
:::

5. 按 `Enter` 确认。

## 第 7 步：准备你的 iPhone

1. 用 USB 数据线将 iPhone 连接到 Mac。
2. 如果 iPhone 上弹出提示，点击**「信任此电脑」**并输入锁屏密码。
3. **如果你使用 iOS 16 或更高版本，必须开启开发者模式：**
   - 在 iPhone 上打开**「设置」**应用。
   - 进入**「隐私与安全性」**。
   - 滑到底部，点击**「开发者模式」**。
   - 将其**开启**。iPhone 会要求重启。
   - 重启后，解锁手机，在弹出的提示中点击**「打开」**。

## 第 8 步：构建并安装

1. 在 Xcode 窗口顶部中间，点击设备选择器。
2. 下拉菜单底部有「Manage Run Destinations」选项。
3. 在打开的菜单中，找到「iOS Devices」下的**你的 iPhone** 或**你的 iPad**，选中它。
4. 点击 Xcode 左上角的大号**运行（▶）按钮**来构建并运行应用。
5. Xcode 开始编译，可能需要几分钟。
   - 如果弹出权限请求询问是否访问「钥匙串」，输入**你的 Mac 登录密码**并点击「始终允许」（可能需要多点几次）。
6. 完成后 Xcode 显示「Build Succeeded」，应用将被推送到你的手机。

## 第 9 步：在 iPhone 上信任应用

Twinskaraoke 应用图标会出现在 iPhone 主屏幕上，但点击时会提示「未受信任的开发者」。

1. 在 iPhone 上打开**「设置」**。
2. 进入**「通用」** → **「VPN 与设备管理」**。
3. 在「开发者应用」栏目下，点击你的 Apple ID 邮箱。
4. 点击**信任「[你的邮箱]」**并确认。

## 常见问题

### `Invalid value of WKCompanionAppBundleIdentifier`

如果构建时出现此错误，说明你在第 6 步 C 部分错误地粘贴了 Watch 应用的 ID。请回到 `Twinskaraoke Watch App` 目标 → `Info` 标签，找到 `WKCompanionAppBundleIdentifier`，确保其值**不以** `.watchkitapp` 结尾。它必须与主 iOS 应用标识符完全一致。

### 免费开发者账号过期

由于你是使用免费个人 Apple ID 安装，应用证书将在 **7 天**后过期。过期后，打开应用会立即闪退。**你不需要删除应用。** 只需将手机重新连接到 Mac，打开此 Xcode 项目，再次点击运行（▶）按钮即可刷新 7 天有效期。应用内的所有数据将完好保留。
