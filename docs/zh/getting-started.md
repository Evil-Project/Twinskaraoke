---
outline: deep
---

# 快速上手

Twinskaraoke 是 [twinskaraoke.com](https://neurokaraoke.com) 的卡拉 OK 播放器，支持 iPhone、iPad、Apple TV 与 Apple Watch。

网站归功于创始人 "Soul"。本应用是网站的配套客户端，提供额外功能。

由 [@ytsodacan](https://github.com/ytsodacan)（SillyProotSoda）与 [@XiaoYuan151](https://github.com/XiaoYuan151)（XiaoYuan151）开发。

::: warning
目前安装方式需要每 7 天重新侧载一次。
:::

## 通过侧载安装

使用 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/) 等侧载工具安装。你需要一个免费的 Apple ID。

### 第一步：下载应用

前往 **[Releases](https://github.com/Evil-Project/Twinskaraoke/releases/latest)** 页面，下载最新的 `.ipa` 文件：

- **`Twinskaraoke-iPhone-Sideload.ipa`**（推荐 iPhone 与 iPad 使用）

### 第二步：侧载

1. 在 PC/Mac 上打开你常用的侧载工具。
2. 将下载好的 `.ipa` 文件拖入工具中。
3. 按提示输入你的 Apple ID 以签名应用。
4. 点击安装！

::: tip
Sideloadly 用户：我们的 IPA 已为你预优化，**无需**在高级选项中勾选「Remove Plug-ins」！
:::

## Apple Watch

如果你想使用 Apple Watch 配套应用，请同时下载 **`Twinskaraoke-Watch.ipa`**。

::: info
免费 Apple 账号每 7 天最多创建 **10 个 App ID**。由于 Watch 应用会一次性占用多个 App ID，如果你已达到 Apple 的服务器限制，Watch 版本可能侧载失败。如遇此情况，请仅使用 iPhone 版。
:::

## Apple TV

Apple TV 应用尚未上架 TestFlight，Nightly Releases 中也没有对应的 `.ipa` —— 需要从源码构建，并用 Xcode 安装到你的 Apple TV 上。功能介绍、扫码登录方式与安装步骤请见 [Apple TV 页面](/zh/apple-tv)。

## 功能特色

<details>
<summary>截图展示</summary>
<div style="display:flex;gap:2%;justify-content:center;margin-top:16px;">
  <img src="../../readmeimages/homescreen.png" style="width:48%" title="主屏幕">
  <img src="../../readmeimages/playingscreen.png" style="width:48%" title="正在播放">
</div>
<div style="display:flex;gap:2%;justify-content:center;margin-top:8px;">
  <img src="../../readmeimages/lyrics.png" style="width:48%" title="歌词视图">
  <img src="../../readmeimages/accountpage.png" style="width:48%" title="账号与设置">
</div>
<div style="display:flex;gap:2%;justify-content:center;margin-top:8px;">
  <img src="../../readmeimages/playingnext.png" style="width:48%" title="播放队列">
  <img src="../../readmeimages/new.png" style="width:48%" title="最新内容">
</div>
<div style="display:flex;flex-direction:column;align-items:center;margin-top:8px;">
  <img src="../../readmeimages/homescreenipad.png" style="width:80%" title="横屏模式">
  <em>iPad 与 iPhone 均支持完整横屏布局</em>
</div>
<div style="display:flex;flex-direction:column;align-items:center;margin-top:8px;margin-bottom:16px;">
  <img src="../../readmeimages/backgroundplaydemo.webp" style="width:48%" title="后台播放演示">
  <em>完整后台播放与系统控制中心集成</em>
</div>
</details>

## 开源协议

本项目基于 [Apache-2.0 License](https://github.com/Evil-Project/Twinskaraoke/blob/main/LICENSE) 开源。
