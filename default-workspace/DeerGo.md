# DeerGo

一个 macOS 全局快速启动器：按下快捷键，输入名字，回车打开。图标是鹿。

![icon](plugin-check/quickopen-icon.png)

## 用法

| 操作 | 说明 |
|---|---|
| `⌥⌘O` | 呼出搜索框（任何 App 前都能用） |
| 输入文字 | 实时列出匹配的**应用 / 文件 / 文件夹** |
| `↑` `↓` | 在结果里移动选择 |
| `回车` | 打开选中项；没有结果时用第一个匹配打开 |
| `Esc` | 关闭面板 |
| `⌘A / ⌘C / ⌘V / ⌘X / ⌘Z` | 全选 / 拷贝 / 粘贴 / 剪切 / 撤销 |

拼音输入时：**第一次回车只上屏，不搜索**；再按一次回车才打开。

## 能搜什么

- **应用**：`/Applications`（含 Adobe 这类嵌套子目录）、`~/Applications`、`/System/Applications`，以及 `Utilities`
- **文件 / 文件夹**：`~/Desktop`、`~/Documents`、`~/Downloads`，递归 6 层

匹配规则（优先级从高到低）：

1. 中文别名表（`ps → Photoshop`、`豆包 → Doubao`、`剪映 → VideoFusion`…共 100+ 条）
2. 应用名精确匹配 → 前缀匹配 → 包含匹配
3. 拼音全拼 / 首字母（`zhiyinlou → 知音楼`、`db → 豆包`）
4. 错字容错（`知音搂 → 知音楼`、`未来盾 → Yunshu`）
5. 文件名精确 → 前缀 → 包含

同名多个时取**最近修改**的那个。

## 文件结构

```
~/Applications/DeerGo.app                        装好的 App（LSUIElement，后台运行）
~/Library/LaunchAgents/com.dsh.deergo.plist      开机自启
tools/deergo.swift                               主程序源码（Swift）
tools/deergo                                     编译产物
tools/resolve_target.py                          名字解析器（Python）
tools/AppIcon.icns                               图标
tools/deer_white.png                             面板左侧的鹿
tools/deer_src2.webp                             图标原始素材
tools/quickopen_icon_1024.png                    合成后的 1024 图标
/tmp/quickopen.log                               调试日志（每次打开会记一行）
~/Library/Caches/quickopen-apps.json             应用索引缓存（24h 过期）
```

## 从源码重建

```bash
cd ~/Documents/deepseek-harness/default-workspace/tools

# 1. 编译
swiftc -O deergo.swift -o deergo

# 2. 装进 App 包
cp deergo    ~/Applications/DeerGo.app/Contents/MacOS/DeerGo
cp AppIcon.icns   ~/Applications/DeerGo.app/Contents/Resources/AppIcon.icns
cp deer_white.png ~/Applications/DeerGo.app/Contents/Resources/deer_white.png

# 3. 重新签名（必须，否则权限与图标会异常）
codesign --force --deep --sign - ~/Applications/DeerGo.app

# 4. 重启
pkill -f "MacOS/DeerGo"; open ~/Applications/DeerGo.app
```

图标改了要额外刷新缓存：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/DeerGo.app
killall Dock
```

## 改快捷键

`deergo.swift` 第 422 行：

```swift
RegisterEventHotKey(UInt32(kVK_ANSI_O), UInt32(cmdKey | optionKey), id, ...)
```

- 换成别的字母：`kVK_ANSI_K`、`kVK_ANSI_D`…（`kVK_ANSI_` + 大写字母）
- 换成空格：`kVK_Space`
- 组合键：`cmdKey | optionKey` 可换成 `controlKey | optionKey` 等

改完按上面的「从源码重建」走一遍。

## 开机自启

```bash
# 关
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.dsh.deergo.plist

# 开
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dsh.deergo.plist

# 看状态
launchctl print gui/$(id -u)/com.dsh.deergo | head
```

## 排错

| 现象 | 原因 / 处理 |
|---|---|
| 快捷键没反应 | `pgrep -fl DeerGo` 看进程在不在；不在就 `open ~/Applications/DeerGo.app` |
| 图标还是旧的 | `killall Dock`；Finder 里还是旧的就 `killall Finder` |
| 搜不到某个 App | 直接跑 `python3 tools/resolve_target.py --list 关键词` 看解析结果；名字不在索引里就清缓存 `rm ~/Library/Caches/quickopen-apps.json` 再试 |
| 打字没进输入框 | 已知偶发：面板刚弹出瞬间按太快可能丢字，点一下输入框即可 |
| 中文输入法下字母不上屏 | 已修：拼音状态回车只上屏不搜索 |

## 设计取舍

- **只扫桌面/文稿/下载**：扫「图片」「影片」会触发系统隐私授权弹窗
- **应用优先于模糊文件名**：否则搜「微信」会命中 `微信图片_xxx.jpg`
- **不做文件拼音索引**：几十万个文件建索引太重，只对应用名做拼音
- **文件名精确优先于应用名**：搜「未来课件」优先给 `未来课件.pptx`，而不是 App
