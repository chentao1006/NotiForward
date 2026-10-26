# 知会 NotiForward

[English](README.md) · [官网](https://notiforward.ct106.com) · [隐私政策](https://notiforward.ct106.com/privacy.html)

知会是一款 macOS 菜单栏应用，通过 [Bark](https://bark.day.app) 把你选定的 Mac 通知转发到 iPhone。不需要配套的 iOS App，也没有自建服务器：在 iPhone 上装好 Bark，把设备 Token 粘贴进知会，再选好要转发的 App 即可。

## 安装

- **直接下载**：从 [Releases](https://github.com/chentao1006/NotiForward/releases/latest) 下载已公证的 DMG，或用 Homebrew：
  ```sh
  brew install --cask chentao1006/tap/notiforward
  ```
- **Mac App Store**：同一款应用，包含全部功能。

需要 macOS 15 或更高版本。

## 使用

1. 在 iPhone 上安装 Bark。
2. 打开知会。配置好 Bark 之前，设置窗口会打开在「客户端」页。
3. 在第一个输入框中粘贴以下任意一种：
   - Bark 的**设备 Token**：知会会向服务器注册并保存返回的密钥；
   - Bark 服务器列表中的**密钥**；
   - 完整地址，如 `https://api.day.app/yourkey/`，会自动拆分出服务器和密钥。
4. 在「通用 → 状态」中点击「授权访问…」并确认。面板会直接打开通知中心文件夹，这是知会唯一读取的文件夹。授权后几秒内即开始转发。
5. 在「转发规则」中选择要转发的 App，再点「发送测试通知」确认能收到。

如使用自建的 [bark-server](https://github.com/Finb/bark-server)，可在「客户端 → 高级 → 服务器」中填写。

## 工作方式

1. **读取**：通过内核文件事件监听通知中心数据库（`~/Library/Group Containers/group.com.apple.usernoted`），只在数据库变化时读取新记录，没有新通知时完全休眠；另有 60 秒一次的兜底检查，防止漏掉事件。读取权限来自用户在系统面板中授权的这一个文件夹（安全范围书签），不需要「完全磁盘访问权限」。
2. **规则**：应用和关键词规则在本机执行，不符合规则的通知不会离开 Mac。
3. **发送**：通过规则的通知先进入本地 SQLite 队列，再发送到 `POST {server}/push`。每条推送包含：
   - 标题「应用 · 标题」，并按应用分组；
   - 通过 Bundle ID 在 App Store 找到的应用图标；
   - 由 Mac 应用的 URL Scheme 生成的点击链接（如 Telegram 的 `tg://`），在 iPhone 上点开即跳转到同一个 App。
4. **重试**：发送失败的通知会留在队列中，按指数退避重试，间隔最长 1 分钟。超过 6 小时的通知直接丢弃，不补发；暂停期间到达的通知会被跳过。

通知中心本身会在显示通知几秒后才把它写入数据库，所以推送通常比 Mac 上显示晚约 3–5 秒。

## 开发

```sh
./test.sh               # 本地化检查、单元测试、App Store 版编译检查，然后 Release 构建，安装到 /Applications 并启动
./test.sh --no-install  # 只做检查和测试
```

每条通知的规则判定、每次发送和读取事件都会写入系统日志。zsh 中 `log` 是内置命令，需写全路径：

```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.ct106.notiforward"'
```

界面支持英语、简体中文、繁體中文、日本語、한국어、Deutsch、Français、Español、Italiano、Português (Brasil)，在设置中切换语言后立即生效。新增界面文字请用 `L("…")`；`scripts/localization.py check` 会检查每种语言是否都已翻译。

## 发布

```sh
./release.sh 1.1.0                  # 直接下载版：发布到 GitHub 和 Homebrew
./release.sh 1.1.0 --app-store      # 同时把 App Store 版上传到 App Store Connect
./release.sh 1.1.0 --no-publish     # 只构建并公证 DMG
```

直接下载版的发布流程：

1. 修改 `project.yml` 中的版本号并跑测试。
2. 归档，用 Developer ID 导出，公证 App。
3. 打包 DMG，公证并装订，再用 `stapler` 和 Gatekeeper 校验。
4. 提交代码、打 tag、创建 GitHub Release，并通过 `release-to-brew.sh` 更新 `chentao1006/tap` 中的 cask。

几点说明：

- 公证需要设置 `APPLE_ID` 和 `APPLE_PASSWORD`（App 专用密码）。上传失败会自动重试；公证结果不是 `Accepted` 时会中止发布。
- 未公证的 DMG 不会被发布，设置 `ALLOW_UNNOTARIZED=1` 可强制发布。
- 设置 `SKIP_HOMEBREW_RELEASE=1` 可跳过 cask 更新。
- `--app-store` 使用 Xcode 中登录的 Apple ID 上传，上传后需在 App Store Connect 中提交审核。

首次提交 App Store 前，需在 App Store Connect 中完成以下设置（审核备注见英文 README）：

- 将隐私政策网址设为 `https://notiforward.ct106.com/privacy.html`；
- 填写 App 隐私：「其他用户内容」用于「App 功能」，「产品交互」用于「分析」；两者均不关联用户、不用于追踪。这与 App 及 Aptabase 的隐私清单一致。

## 隐私

- 没有账号、广告或跨 App 追踪。Aptabase 会接收匿名产品交互事件及标准技术信息，但绝不包含通知内容、Bark 凭据、App Bundle ID 或规则关键词。
- 规则在本机执行，只有通过规则的通知会被发送。
- 转发的内容会经过所配置的 Bark 服务器和 Apple 推送服务到达 iPhone。不希望经过 `api.day.app` 的话，请使用自建服务器。
- 应用图标通过 Bundle ID 在 Apple 的 App Store 查询服务中查找，不会发送任何通知内容。
- 设置、Bark 密钥和待发送队列保存在应用的沙盒容器中。

完整内容见[隐私政策](https://notiforward.ct106.com/privacy.html)。
