---
outline: deep
---

# Apple TV 应用

Twinskaraoke 现已推出原生 **Apple TV** 应用：整个曲库搬上大屏幕，全程用 Siri Remote 操作，歌词大到全客厅的人都能跟着唱。

::: info 系统要求
Apple TV 应用需要 **tvOS 26 或更高版本**。目前尚未上架 TestFlight，Nightly Releases 中也没有对应的 `.ipa` —— 现阶段需要用 Xcode [从源码构建并安装](#安装到你的-apple-tv)。
:::

<p align="center">
  <img src="../../readmeimages/TVhome.png" width="90%" title="Apple TV 主界面">
  <br>
  <em>主界面 —— 热门与最新</em>
</p>

## 功能特色

### 主界面

两排海报式内容架：**Trending**（大家都在唱的）与 **New Releases**（曲库新增）。用遥控器左右滑动浏览，点选任意一张海报即开始播放，并直接跳转到「正在播放」。

### 搜索

<p align="center">
  <img src="../../readmeimages/TVsearch.png" width="90%" title="Apple TV 搜索">
  <br>
  <em>用屏幕键盘搜索歌曲与歌手</em>
</p>

用 tvOS 屏幕键盘搜索整个曲库中的歌曲与歌手。搜索结果以带封面、歌手和时长的编号列表呈现，点选即播，同时整个结果列表会成为你的播放队列。

### 音乐库

<p align="center">
  <img src="../../readmeimages/TVlibrary.png" width="49%" title="Apple TV 音乐库">
  <img src="../../readmeimages/TVplaylist.png" width="49%" title="Apple TV 歌单详情">
  <br>
  <em>海报墙式的歌单列表 &nbsp;&bull;&nbsp; 每个歌单的完整曲目</em>
</p>

所有精选歌单（包括直播卡拉 OK 的歌单）都以海报墙形式展示，并标注歌曲数量。打开任意歌单即可查看完整曲目，然后点 **Play** 播放整个歌单，或直接从某一首开始。

### 正在播放

<p align="center">
  <img src="../../readmeimages/TVlyrics.png" width="90%" title="Apple TV 正在播放与歌词">
  <br>
  <em>全屏封面与逐句同步歌词</em>
</p>

- **逐句同步歌词**，自动滚动，当前行高亮、其余行淡出。
- **播放控制**：随机播放、上一首、播放/暂停、下一首、循环模式（列表循环 / 单曲循环）。
- **Up Next 队列**，随时看到接下来要播的歌。
- 背景为模糊处理的封面，并完整接入 tvOS「正在播放」，Siri Remote 与系统控制均可正常使用。

::: tip
曲库中没有歌词的歌曲会自动切换为更宽的布局，只显示封面与播放队列，不会留下占据半个屏幕的空歌词面板。
:::

### 账号

<p align="center">
  <img src="../../readmeimages/TVaccount.png" width="90%" title="Apple TV 账号">
  <br>
  <em>个人资料、等级、上传额度与徽章</em>
</p>

个人资料、等级与经验值进度、上传与歌单额度，以及你收集到的徽章 —— 坐在沙发上也能看清。

## 无需打字的登录方式

用遥控器输入密码非常痛苦，因此 TV 应用沿用了网站的扫码登录流程：

1. 在 Apple TV 上打开 **Account** 标签页，屏幕会显示一个二维码和一段短验证码。
2. 用已登录的 **Twinskaraoke iPhone 应用** 扫描该二维码。
3. 确认手机上显示的短验证码与电视上一致后点击批准，稍等片刻电视端即完成登录。

::: info
配对码有效期很短（电视屏幕属于公共显示设备），过期后在同一界面重新生成即可。如果你不想用手机，同一界面上也提供 **「改用用户名和密码登录」** 的选项。
:::

## 安装到你的 Apple TV

TV 应用通过 Xcode 经局域网安装，没有可侧载的 `.ipa`。请先按 [从源码构建](/zh/build-from-source) 完成准备工作，然后：

1. 让你的 Mac 与 Apple TV 连接到 **同一 Wi-Fi 网络**。
2. 在 Apple TV 上进入 **设置** → **遥控器与设备** → **遥控器 App 和设备**，保持该界面等待连接。
3. 在 Xcode 中打开 **Window** → **Devices and Simulators**，找到你的 Apple TV 并完成配对（如有提示，输入电视上显示的配对码）。
4. 如果 Apple TV 提示需要开启 **开发者模式**（设置 → 隐私与安全性），请开启并让设备重启。
5. 回到 Xcode，选择 **Twinskaraoke TV App** scheme，将运行目标设为你的 Apple TV，然后点击 **运行（▶）按钮**。

::: warning 证书有效期
与 iPhone 版一样，使用免费 Apple ID 签名的构建仅有 **7 天** 有效期。到期后应用将无法启动，用 Xcode 重新运行一次即可续期，无需删除应用。
:::

::: tip 手边没有 Apple TV？
Xcode 自带的 **Apple TV 模拟器** 也能正常运行本应用，在运行目标列表中选择模拟器即可先体验一番。
:::
