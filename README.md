# Twinskaraoke client for Apple Mobile Devices
![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20iPadOS%20%7C%20watchOS-black?logo=apple) [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) ![Language](https://img.shields.io/badge/Language-Swift-FA7343?logo=swift&logoColor=white)

A karaoke player for [twinskaraoke.com](https://neurokaraoke.com) — available for iPhone, iPad and Apple Watch

All credits go to the website creator "Soul". This is a companion app for the website with extra features.

**This app is created & maintained by:**
- [@XiaoYuan151](https://github.com/XiaoYuan151) (XiaoYuan151)
- [@Mag1cByt3s](https://github.com/Mag1cByt3s) (MagicBytes)
- [@ytsodacan](https://github.com/ytsodacan) (SillyProotSoda) 
- [@NELC-Official](https://github.com/NELC-Official) (NELC-Official)


> **Update : We are officially live on TestFlight, see installation info below! Stay tuned for the App Store!**
>
> Note: The watchOS app is still 100% in development please be patient with us, thank you!


## Features

*   **Native Experience:** Better than the website!

*  **Background Playback:** Full integration with the iOS Lock Screen and Control Center.
*  **Apple Watch Companion:** Control from your wrist (work in progress)

*  **Offline Play:** Listen to neuro and evil sing anywhere, even without the internet.

*  **Advanced Audio Controls:** A built-in 10-band parametric EQ

*  **Vocal & Instrumental Slider:** to separate tracks in real-time.

*  **Live Radio & Galleries:** Listen to live streaming radio episodes, and browse through thousands of fan artworks and videos.

<details>
<summary><b>Screenshots</b></summary>
<br>

<p align="center">
  <img src="readmeimages/homescreen.png" width="32%" title="Home Screen">
  <img src="readmeimages/playingscreen.png" width="32%" title="Now Playing">
  <img src="readmeimages/lyrics.png" width="32%" title="Lyrics View">
</p>

<p align="center">
  <img src="readmeimages/accountpage.png" width="32%" title="Account & Settings">
  <img src="readmeimages/playingnext.png" width="32%" title="Up Next Queue">
  <img src="readmeimages/new.png" width="32%" title="Instrumental Lyrics">
</p>

<p align="center">
  <img src="readmeimages/EQ.png" width="32%" title="EQ">
  <img src="readmeimages/downloadoption.png" width="32%" title="Download Option">
  <img src="readmeimages/downloaded.png" width="32%" title="Downloaded">
  <br>
  <em>Built In EQ &nbsp;&bull;&nbsp; Download Songs &nbsp;&bull;&nbsp; Play Offline</em>
</p>

<p align="center">
  <img src="readmeimages/artistpage.png" width="32%" title="Artist Page">
  <img src="readmeimages/art.png" width="32%" title="Art">
  <img src="readmeimages/ARTartist.png" width="32%" title="Art Artist">
  <br>
  <em>Find Artists &nbsp;&bull;&nbsp; And Art</em>
</p>

<p align="center">
  <img src="readmeimages/library.png" width="32%" title="Library">
  <img src="readmeimages/backgroundplaydemo.webp" width="32%" title="Background Play Demo">
  <img src="readmeimages/videos.png" width="32%" title="videos">
  <br>
  <em>Playlists, Upload New Songs & Watch Videos & More &nbsp;&bull;&nbsp; Full Background Play & System Controls</em>
</p>

<p align="center">
  <img src="readmeimages/homescreenipad.png" width="70%" title="Horizontal Mode">
  <br>
  <em>Full landscape support for iPad and iPhone</em>
</p>

<p align="center">
  <img src="readmeimages/lyricsipad.png" width="70%" title="Horizontal lyrics">
  <br>
  <em>See More on iPad</em>
</p>

</details>

# Twinskaraoke - iOS Installation Guide

### Follow the instructions below to install:

1. Download the TestFlight app: [https://apps.apple.com/us/app/testflight/id899247664](https://apps.apple.com/us/app/testflight/id899247664)
2. Log in to TestFlight in the app with your Apple account.
3. Click on this link on your iPhone: [https://testflight.apple.com/join/PrNm97Vr](https://testflight.apple.com/join/PrNm97Vr)
4. Click install.

> [!WARNING]
> **TestFlight builds expire after 90 days.** Each build we upload is only valid for 90 days, after which it stops working and you will need to update to a newer build from TestFlight. If we ever fail to upload a new build in time, testers will lose access to the app until a fresh build is published.

### Or scan the QR code to join the TestFlight beta if you have the TestFlight app:

<p align="center">
  <img src="readmeimages/qr.svg" width="40%" title="Scan to join the Twinskaraoke TestFlight beta">
  <br>
  <em>Scan with your camera to open the TestFlight invite</em>
</p>

---

#### You may also, optionally, Sideload or build from source. You can find the info below:

<br>
<details>
<summary><b>Sideloading </b></summary>

## Install

Install using sideloading tools like [Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/).
you will need a free Apple ID.

---

### Step 1: Download the App
As we prepare for our App Store launch, we highly recommend using our Nightly Builds to get the latest features, bug fixes, and improvements!

Go to the **[Releases](https://github.com/Evil-Project/Twinskaraoke/releases)** page on this repository and download the latest `.ipa` file:
* **`Twinskaraoke-iPhone-Sideload.ipa`** (Recommended for iPhone & iPad)

### Step 2: Sideload
1. Open your sideloading tool on your PC/Mac.
2. Drag and drop the downloaded `.ipa` into the tool.
3. Enter your standard Apple ID when prompted to sign the app.
4. Click install. 

*Sideloadly Users: Our IPA is pre-optimized for you. You do **NOT** need to click "Remove Plug-ins" in Advanced Options!*

## Apple Watch
If you wish to use the Apple Watch companion app, download the **`Twinskaraoke-Watch.ipa`** as well.

Free Apple accounts are limited to creating **10 App IDs every 7 days**. Because Watch apps use multiple App IDs at once, sideloading the Watch version may fail if you have hit Apple's server limit. If this happens, please stick to the iPhone-only IPA.

</details>

#  
<br>
<details>
<summary><b>Build from Source </b></summary>
<br>
If you are familiar with the "magic" that is swift dev you may skip to 6c

### Requirements
1. **A Mac computer** (Xcode is only available on macOS, any mac will do).
2. **An Apple ID** (A standard, free account works perfectly).
3. **Your iPhone/iPad** and a USB cable to connect it to your Mac

##### Getting Help
* If you need help during installation you can ask in the neurosama discord server (neurocord) in the *"Neuro & Evil Karaoke Web Player"* Thread but please look up the issue first

---

### Step 1: Prepare your Apple Developer Account
You **do not** need to pay for the $99/year Apple Developer program to install this app on your own device. A standard, free Apple ID will act as a free developer account for personal sideloading.
* **If you already have an Apple ID:** You can just use the same Apple ID you use on your iPhone.
* **If you don't have an Apple ID, or want to make a separate one:**
  1. Go to [appleid.apple.com](https://appleid.apple.com/).
  2. Click **Create Your Apple ID** in the top right corner.
  3. Fill out the required information and verify your email/phone number.

### Step 2: Download and Install Xcode
Xcode is Apple's official software for building iOS apps. It is completely free but quite large.
1. On your Mac, use **App Store** to get the **Xcode** app
2. Once installed, click **Open** to launch Xcode for the first time
3. Xcode will prompt you to "Install additional required components." Click **Install** and enter your Mac's login password if prompted. Wait for this process to finish

---

### Step 3: Download the Twinskaraoke Project
1. Scroll to the top of this GitHub page.
2. Click the green **`<> Code`** button.
3. Click **Download ZIP**.
4. Once downloaded, find the file (usually in your Downloads folder) and double-click the `.zip` file on your Mac to extract the folder.

> you can of course clone via your preferred method

### Step 4: Add your Apple ID to Xcode
Xcode needs your Apple ID to create a free temporary signing certificate so your iPhone will accept the app.
1. Open **Xcode**.
2. In the top Mac menu bar, click **Xcode** -> **Settings...** (or Preferences).
3. Click on the **Accounts** tab at the top of the settings window.
4. Click the **`+`** button in the bottom left corner, select **Apple ID**, and click **Continue**.
5. Log in with your Apple ID and password.
6. You should now see your name listed with a "(Personal Team)" role. Close this window.

### Step 5: Open the Project
1. Open the extracted `Twinskaraoke-main` folder.
2. Find the Xcode project file (it will be named `Twinskaraoke.xcodeproj` or `Twinskaraoke.xcworkspace`). Double-click it to open it in Xcode.
3. *If your Mac asks if you want to trust and open a project downloaded from the internet, click **Trust and Open**.*

---

### Step 6: Fix the "Team" and "Bundle Identifier" Errors

#### Part A: Update the Main iOS App
1. Look at the file navigator on the far left side of Xcode. Click on the top-most blue icon named **Twinskaraoke**.
   ![xcode1](readmeimages/xcode1.png)
   ![xcode2](readmeimages/xcode2.png)
2. In the middle section of Xcode, look at the **TARGETS** list and click on **Twinskaraoke** (the first one).
3. Click on the **Signing & Capabilities** tab at the top of this middle section.

   ![xcode3](readmeimages/xcode3.png)
4. Check the box that says **Automatically manage signing**. (should already be checked though)
   ![xcode4](readmeimages/xcode4.png)
5. In the **Team** dropdown menu, change it from the red "Unknown Name" to **Your Name (Personal Team)**.
6. **Crucial Step:** You must change the **Bundle Identifier** to something globally unique.
   * It currently says: `com.xiaoyuan151.Twinskaraoke`
   * Change `xiaoyuan151` to your own name without spaces. For example: `com.johnsmith.Twinskaraoke`
   * *Press `Enter` on your keyboard after typing it.* Xcode should spin for a second and the red errors should disappear.
   ![xcodenamechange1](readmeimages/xcodenamechange.png)

#### Part B: Update the Watch App target
Because this app includes an Apple Watch component, you **must** update its identifiers to match the one you just created, otherwise the build will fail.
1. In the **TARGETS** list on the left side of the middle pane, click on **Twinskaraoke Watch App**.
2. Go to the **Signing & Capabilities** tab.
3. Change the **Team** dropdown to **Your Name (Personal Team)**.
4. Change the **Bundle Identifier** to match exactly what you typed in Part A, but keep the `.watchkitapp` at the end.
   * Example: `com.johnsmith.Twinskaraoke.watchkitapp`
   * *Press `Enter`.*

#### Part C: Update the Watch App's "Info" settings
This step links the Watch App to the Phone App.
1. While still selecting the **Twinskaraoke Watch App** target, click the **Info** tab at the top (next to Resource Tags / Build Settings).
2. Look through the list of Keys for one named **`WKCompanionAppBundleIdentifier`**.
3. Under the "Value" column, double-click to edit it.
4. Change it to the **exact Bundle Identifier of the Main App** you created in Part A.
   * Do *NOT* include `.watchkitapp` at the end of this value!
   * **Correct Example:** `com.johnsmith.Twinskaraoke`
   * **Incorrect Example:** `com.johnsmith.Twinskaraoke.watchkitapp`
5. Press `Enter`.
   ![xcodenamechange2](readmeimages/xcodenamechange2.png)

---

### Step 7: Prepare your iPhone
*Better Guides Than This Exist - if you get stuck here just google it*
1. Plug your iPhone into your Mac using a USB cable.
2. If a prompt appears on your iPhone, tap **Trust This Computer** and enter your passcode.
3. **If you are on iOS 16 or later, you MUST enable Developer Mode:**
   * On your iPhone, open the **Settings** app.
   * Go to **Privacy & Security**.
   * Scroll down to the very bottom and tap **Developer Mode**.
   * Toggle it **ON**. Your iPhone will ask to restart.
   * After it restarts, unlock your phone and tap **Turn On** when the prompt appears.

### Step 8: Build and Install
1. At the very top middle of the Xcode window, you will see a device selector (it might say "Any iOS Device" or show an iPhone simulator model). Click it.
2. A drop down with a long list of possible destinations will appear at the bottom of this will be a option for "Manage Run Destinations"
   ![xcodebuild2](readmeimages/xcodebuild2.png)
3. On the Menu that opens, look under "iOS Devices" and select **Your actual iPhone** or **Your actual iPad**.
4. In the top left corner of Xcode, click the big **Play (▶) button** to build and run the app.
5. Xcode will begin compiling the app. This may take a few minutes.
   * *If you get a prompt asking for permission to access your "keychain", enter your **Mac login password** and click "Always Allow" (you may need to click it a few times).*
6. Once it finishes, Xcode will say "Build Succeeded" and push the app to your phone.

### Step 9: Trust the App on your iPhone
The Twinskaraoke app icon will now be on your iPhone's home screen, but if you tap it, your phone will say "Untrusted Developer".
1. On your iPhone, open **Settings**.
2. Go to **General** -> **VPN & Device Management**
3. Under the "Developer App" section, tap on your Apple ID email address.
4. Tap **Trust "[Your Email]"** and confirm.

---

#### Common Errors
* **`Invalid value of WKCompanionAppBundleIdentifier key in WatchKit 2.0 app's Info.plist`**
If the build fails with this error, it means you accidentally pasted the Watch App's ID in **Step 6, Part C**. Go back to the `Twinskaraoke Watch App` target -> `Info` tab, find `WKCompanionAppBundleIdentifier`, and make sure the value **does not** end in `.watchkitapp`. It must be identical to your Main iOS App identifier.

#### Important Note regarding Free Developer Accounts
Because you are installing this using a free, personal Apple ID, the app certificate will expire in **7 days**.
After 7 days, the app will crash immediately when you try to open it. **You do not need to delete the app.** To fix this, simply plug your phone back into your Mac, open this Xcode project, and click the Play (▶) button again to refresh the 7-day timer. All of your saved data inside the app will remain perfectly intact.

</details>

---

## License
This project is licensed under the [Apache-2.0 License](LICENSE).
