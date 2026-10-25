# 知会 NotiForward

[English](README.md)

知会是一款 macOS 菜单栏应用，通过 [Bark](https://github.com/Finb/Bark) 把 Mac 上选定的通知转发到 iPhone。不需要配套的 iOS App，也没有自建中转服务器：在 iPhone 上装好 Bark，把设备 Token 粘贴进知会即可。

## 使用

1. 在 iPhone 上安装 Bark。
2. 打开知会。在配置好 Bark 之前，每次启动都会自动打开设置窗口。
3. 在第一个输入框中粘贴以下任意一种：
   - Bark 的**设备 Token**：知会会向服务器注册并保存返回的密钥；
   - Bark 服务器列表中的**密钥**；
   - 完整地址，如 `https://api.day.app/yourkey/`，会自动拆分出服务器和密钥。
4. 点击「打开“完全磁盘访问权限”设置」，打开知会的开关。几秒内即开始转发，无需重启。
5. 点击「发送测试通知」确认能收到。

如使用自建的 [bark-server](https://github.com/Finb/bark-server)，可在「高级 › 服务器」中填写。

## 工作方式

1. 每秒读取一次系统通知中心数据库。macOS 没有读取其他应用通知的公开接口，因此需要完全磁盘访问权限。
2. 应用和关键词规则在本机执行，被过滤的通知不会离开 Mac。
3. 通过规则的通知先进入本地 SQLite 队列，再发送到 `POST {server}/push`。标题为「应用 · 标题」，默认按应用分组。
4. 发送失败的通知会留在队列中，按指数退避重试，间隔最长 1 分钟。超过 6 小时的通知直接丢弃，不补发；暂停期间到达的通知会被跳过。

## 开发

```sh
./test.sh               # 本地化检查 + 单元测试 + Release 构建，安装到 /Applications 并启动
./test.sh --no-install  # 只做检查和测试
./release.sh 1.1.0      # 改版本号、测试、归档、Developer ID 导出、公证、打包 DMG、打 tag、发布 GitHub Release
./release.sh 1.1.0 --no-publish   # 只打包 DMG
```

每条通知的规则判定和每次发送都会写入系统日志。zsh 中 `log` 是内置命令，需写全路径：

```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.ct106.notiforward"'
```

设置了 `APPLE_ID` 和 `APPLE_PASSWORD`（App 专用密码）时，`release.sh` 会自动公证。Xcode 工程由 `project.yml` 通过 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成，两个脚本都会自动重新生成。

界面支持英语、简体中文、繁體中文、日本語、한국어、Deutsch、Français、Español、Italiano、Português (Brasil)，在设置中切换语言后立即生效。新增界面文字请用 `L("…")`；`scripts/localization.py check` 会检查每种语言是否都已翻译。

## 隐私

- 规则在本机执行，只有通过规则的通知会被发送。
- 转发的内容会经过所配置的 Bark 服务器和 Apple 推送服务到达 iPhone。不希望经过 `api.day.app` 的话，请使用自建服务器。
- 设置、Bark 密钥和待发送队列保存在 `~/Library/Application Support/NotiForward/noti-forward.sqlite`。
