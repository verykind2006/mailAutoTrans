# MailAutoTrans

读外语邮件自动显示中文；用中文写回信，翻译、核对后一键发出。

用标准邮件协议（IMAP 收信 / SMTP 发信）直接连邮箱，不依赖 Outlook 或网页邮箱。Flutter 写的，目前做好的是 Mac 版。

## 功能（v1.0）

- **读信**：打开外语信自动翻成中文；网页格式（HTML）的信保留原来的排版、图片和按钮，只把文字换成中文；「中文 / 原文」一键切换；回信里引用的旧信不翻。
- **信件列表**：仿 Gmail 网页版布局；标题直接显示中文，前面有原文语言标签（西语、英语、意语…）；往下拉自动加载更早的信；搜索（打字筛已载入的，回车在服务器上搜整个文件夹，中文词也能搜外文信）；打开即标为已读。
- **写信 / 回复**：用中文写 → 翻译 → 左右对照核对（附「译文的中文意思」）→ 发送；回复 / 回复全部；抄送、密送；每个联系人记住上次用的语言；发出的信存进「已发送」。快捷键：⌘↩ 翻译 / 发送，Esc 回去改中文。
- **多个邮箱**：左侧栏按邮箱分组，写信时可选发件邮箱。
- **翻译引擎可选**：Claude、DeepSeek、OpenAI、其他 OpenAI 兼容服务（自己填 API key），或本机 MLX 模型（不联网、不花钱）。
- **大字、浅色**：界面字号 17–18px 起，⌘+ / ⌘- 整体放大缩小。

## 支持的邮箱

任何开放 IMAP / SMTP 的邮箱。Gmail、iCloud、QQ、163 有预设；Gmail 要用「应用专用密码」（`myaccount.google.com/apppasswords`）。

## 数据存在哪

全部在本机：`~/Library/Application Support/com.vk.autoTransMail/`（邮箱设置、翻译设置、译文缓存）。邮件内容只发给你选的翻译服务。

## 构建

需要 Flutter（3.50+）和 Xcode。

```sh
flutter build macos --release
```

本机模型用的 MLX 需要编译 Metal 着色器，所以必须走 `flutter build`（底层是 xcodebuild），不能用 `swift build`。
