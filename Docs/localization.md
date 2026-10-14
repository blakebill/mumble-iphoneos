# 应用语言

应用内置 12 种语言：英语、简体中文、繁体中文、日语、韩语、德语、法语、西班牙语、葡萄牙语（巴西）、意大利语、俄语和丹麦语。

每种语言包含 303 条应用界面文案，以及麦克风、局域网权限说明。范围覆盖首页、服务器、消息、音频设置、首次启动向导、证书、访问令牌、连接错误和辅助功能标签。公共服务器的国家名称由 Foundation 按应用语言提供；大洲名称由应用翻译。服务器与用户提供的名称、消息和拒绝原因保留原文。法律许可保留原文。

语言资源通过 Xcode 的 `Localizable.strings` 和 `InfoPlist.strings` 变体组打包。开发语言为 `en`，`UIPrefersShowingLanguageSettings` 开启系统应用语言入口。应用使用 Foundation 的标准语言选择机制，默认跟随系统首选语言；不写入 `AppleLanguages`，不增加自定义语言覆盖。

部分共同术语参考 Mumble 上游翻译，许可证保存在 `Resources/Mumble-Translations-LICENSE.txt`，相同声明随 `Legal.html` 打包。新增 iOS 界面文案单独翻译。

## 验证

- `python3 Scripts/check-localizations.py`：使用 `genstrings` 提取源代码文案，检查所有语言的完整键集合、非空翻译、格式参数和权限说明。
- 翻译不保留桌面快捷键后缀（如 `(D)`）；检查脚本会拒绝这类残留。原文具有含义的括号说明保留。
- `python3 Scripts/check-localizations.py --app /path/to/Mumble.app`：额外验证实际构建产物中的全部语言资源与系统语言入口配置。
- iPhone Release 与隔离模拟器 Debug 构建通过，无 App 构建警告。
- `MU_UI_TEST_LANGUAGE=zh-Hans`、`ja`、`de` 分别运行 `Scripts/test-ui-interface.sh`：Foundation 实际选中对应语言；密码提示、向导、证书、设置、服务器与消息界面检查通过，包括辅助功能大字号布局。中文、日语、德语的主要页面另用运行截图核对。
- 真机版本已安装并启动。语言切换测试在独立模拟器应用中进行，不修改用户真机的语言设置或数据。
- iOS 27 系统设置实测：设置 → Apps → Mumble → Language 出现原生语言入口，列表包含上述全部 12 种语言。

测试语言启动参数仅用于隔离测试应用；测试二进制和截图保存在临时目录，不进入 Git。
