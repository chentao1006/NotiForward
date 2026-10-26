# App Store Connect metadata

Screenshots: `AppStore/screenshots/<zh-Hans|en>/<size>/01–05.png`. Every Mac size (2880×1800, 2560×1600, 1440×900, 1280×800) is rendered; upload one size per localization, 2880×1800 recommended. Source: `screenshots.html`, rebuilt by `render.sh`.

## App information (all localizations)

| Field | Value |
|---|---|
| Primary category | Utilities |
| Secondary category | Productivity |
| Age rating | 4+ (answer "None" to every question) |
| Copyright | © 2026 CT106 |
| Support URL | https://github.com/chentao1006/NotiForward/issues |
| Marketing URL | https://notiforward.ct106.com/ |
| Privacy policy URL | https://notiforward.ct106.com/privacy.html |
| App Privacy | Other User Content · App Functionality · not linked to the user · not used for tracking |

---

## 简体中文（zh-Hans）

**名称**（≤30）
知会 - Mac 通知转发到 iPhone

**副标题**（≤30）
选定的通知，经 Bark 推送到手机

**推广文本**（≤170，可随时修改，无需审核）
离开 Mac 也不错过重要消息。按应用和关键词筛选，把选定的通知通过 Bark 实时推送到 iPhone，点一下即可打开对应 App。

**关键词**（≤100，逗号分隔，不加空格）
通知转发,推送,Bark,手机提醒,消息同步,菜单栏,通知中心,过滤,关键词,效率,远程,提醒

**描述**
离开 Mac 的时候，重要消息不该被错过。知会是一款菜单栏应用，把你选定的 Mac 通知通过 Bark 实时推送到 iPhone。

只转发你在意的
• 选择要转发的 App，其余通知一概不发
• 用关键词进一步过滤，例如屏蔽广告和促销
• 所有规则都在 Mac 本机执行，不符合规则的通知不会离开你的电脑

推送更好用
• 推送带有来源应用的图标，并按应用分组
• 点一下推送，直接打开 iPhone 上对应的 App
• 通常在 Mac 显示通知后几秒内送达

安心、省电
• 沙盒运行，只读取你授权的通知中心文件夹
• 事件驱动：有新通知才工作，平时完全休眠
• 没有账号，开发者不收集任何数据

一分钟完成设置
1. 在 iPhone 上安装免费、开源的 Bark
2. 把 Bark 的设备 Token、密钥或推送地址粘贴到知会
3. 授权读取通知中心文件夹，选择要转发的 App

关于 Bark
知会通过 Bark 接收推送。转发的通知会经过你设置的 Bark 服务器（默认为 Bark 官方服务器），也可以改用自建的 bark-server。

支持 10 种语言：简体中文、繁體中文、English、日本語、한국어、Deutsch、Français、Español、Italiano、Português。

隐私政策：https://notiforward.ct106.com/privacy.html

**此版本的新内容**
知会首次登陆 Mac App Store。

---

## English (en)

**Name** (≤30)
NotiForward: Mac to iPhone

**Subtitle** (≤30)
Forward notifications via Bark

**Promotional text** (≤170, editable anytime without review)
Never miss what matters when you step away from your Mac. Filter by app and keyword, get those notifications on your iPhone through Bark, and tap to open the app.

**Keywords** (≤100, comma-separated, no spaces)
notification,forward,push,bark,alert,menu bar,filter,keyword,remote,relay,sync,productivity

**Description**
Don't miss what matters when you step away from your Mac. NotiForward is a menu bar app that sends the Mac notifications you choose to your iPhone in real time, through Bark.

ONLY WHAT MATTERS
• Pick the apps to forward; everything else stays put
• Narrow it down further with keywords, for example to drop promotions
• All rules run on your Mac, so notifications that don't match never leave it

BETTER PUSHES
• Each push shows the source app's icon and is grouped by app
• Tap a push to open the matching app on your iPhone
• Usually arrives within seconds of appearing on your Mac

PRIVATE AND POWER-FRIENDLY
• Sandboxed: reads only the Notification Center folder you grant
• Event-driven: wakes when a notification arrives, sleeps otherwise
• No account, and the developer collects no data

SET UP IN A MINUTE
1. Install the free, open-source Bark app on your iPhone
2. Paste Bark's device token, key or push URL into NotiForward
3. Grant access to the Notification Center folder and pick your apps

ABOUT BARK
NotiForward delivers pushes through Bark. Forwarded notifications pass through the Bark server you configure (Bark's public server by default), or your own self-hosted bark-server.

Available in 10 languages: English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, Spanish, Italian and Portuguese.

Privacy Policy: https://notiforward.ct106.com/privacy.html

**What's New**
NotiForward's first release on the Mac App Store.

---

## App Review notes

> NotiForward forwards notifications the user chooses from their Mac to their own iPhone through Bark, a free open-source push app. To read notifications, the user selects the Notification Center data folder (~/Library/Group Containers/group.com.apple.usernoted) once in a standard open panel; the app keeps a read-only security-scoped bookmark to that folder and accesses nothing else. Filtering rules run on the Mac, and only matching notifications are sent, over HTTPS, to the Bark server the user configures.
>
> To test: install Bark on an iPhone, paste its device key in Settings → Client, grant folder access in Settings → General (Grant Access…), choose an app in Forwarding Rules, and click Send Test Notification.
