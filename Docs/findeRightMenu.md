# Finder Right Menu Wiki

## 当前方案

AirSentry 的 Finder 右键“新建文件”采用主 App 写入、FinderSync 扩展只负责菜单和转发的方案。

- FinderSync 扩展：`AirGuardFinderExtension/FinderSync.swift`
- 宿主 App 接收入口：`AirGuard/AirGuardApp.swift`
- 文件夹授权和实际写入：`AirGuard/Core/FinderNewFileAuthorizationStore.swift`

流程：

1. Finder 右键菜单由 `FIFinderSync` 扩展生成。
2. 用户点击“新建文件”子项后，扩展解析目标目录和文件模板。
3. 扩展优先通过 `DistributedNotificationCenter` 发送 `AirSentry.Finder.NewFileRequest` 给宿主 App。
4. 如果宿主 App 未运行，扩展使用 `airsentry://finder/new-file` URL scheme 唤起宿主 App 兜底。
5. 宿主 App 根据用户授权过的 security-scoped bookmark 判断目标目录是否允许写入。
6. 通过授权后，宿主 App 创建文件，并处理重名文件后缀。
7. 如果目录未授权或写入失败，宿主 App 弹出可操作提示，引导用户打开“工具箱 > 超级右键 > 文件夹授权”添加目录。

这个设计参考了 RClick 的瘦扩展模式：扩展不直接承担复杂文件写入、模板处理和权限判断，真正创建文件放在主 App 中完成。

## 关键结论

FinderSync 扩展必须保持很薄。不要在扩展里直接写目标目录，也不要假设扩展能稳定持有所有点击上下文。

几个踩坑结论：

- Finder 扩展必须 sandbox，否则系统会忽略扩展。
- Finder 扩展里不要用 `NSWorkspace.open(..., withApplicationAt:)` 指定宿主 App 路径打开 URL，这会触发 AppleEvents/TCC 限制。
- 右键“新建文件”的实际写入应该由宿主 App 完成，并经过文件夹授权。
- 不要只蜂鸣失败。没有写入权限时要给出明确提示，并提供入口打开授权设置页。
- FinderSync 的菜单生成阶段和点击阶段不是完全稳定的同一个上下文。
- `NSMenuItem.representedObject` 在 Finder/AppKit 回调里可能变成 `nil`，不能作为唯一状态来源。
- `.app` 等 package 虽然底层是目录，但 Finder 语义上应按文件处理，创建文件时目标目录应取它的父目录，不能写进 App 包内部。

## 本次蜂鸣问题总结

现象：

在 Finder 里右键选择“新建文件”后，只听到系统提示音“滴”，没有文件生成。

第一阶段日志显示：

```text
AirSentry Finder extension menu target directory /Users/zwj/Downloads
AirSentry Finder extension could not resolve target directory
```

说明菜单生成时能识别目标目录，但点击子菜单时扩展没有拿到目标目录。

第二阶段加细日志后看到：

```text
AirSentry Finder extension attached new file request template=新建文本.txt, directory=/Applications/Qianwen.app
AirSentry Finder extension could not read new file menu request object: nil
```

这说明生成菜单时确实把模板和目录放进了 `representedObject`，但点击时 Finder/AppKit 传回来的 `sender.representedObject` 已经是 `nil`。

最终修复：

- 模板优先从 `representedObject` 取。
- 如果 `representedObject` 丢失，就用菜单标题反查模板。
- 目标目录优先用点击时的 `selectedItemURLs()` / `targetedURL()`。
- 如果点击时 Finder 状态取不到，就回退到菜单生成阶段保存的 `menuTargetDirectoryURL`。
- 判断目录时加入 package 检查，`.app` 这类 package 走父目录。
- 宿主 App 将创建结果拆分为 `created`、`unauthorized`、`writeFailed`，未授权和写入失败都会弹窗引导用户打开授权设置。

当前关键代码在 `AirGuardFinderExtension/FinderSync.swift`：

```swift
let request = sender.representedObject as? NewFileMenuRequest
guard let template = request?.template ?? templates.first(where: { $0.title == sender.title }) else {
    NSSound.beep()
    return
}

guard let directoryURL = targetDirectoryURL(fallback: request?.directoryURL ?? menuTargetDirectoryURL) else {
    NSSound.beep()
    return
}
```

package 判断：

```swift
private func isFinderDirectory(_ url: URL) -> Bool {
    guard url.hasDirectoryPath else { return false }

    let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    return !isPackage
}
```

权限失败提示：

```swift
switch FinderNewFileService.createFile(at: requestedURL, contents: contents) {
case .created:
    return
case .unauthorized:
    FinderNewFilePermissionPrompter.showUnauthorizedFolderAlert(for: requestedURL)
case .writeFailed:
    FinderNewFilePermissionPrompter.showWriteFailedAlert(for: requestedURL)
}
```

提示弹窗提供“打开授权设置”按钮。点击后主 App 通过通知打开工具箱窗口，并自动切到“超级右键”页：

```text
AirSentry.OpenFinderAuthorizationSettings
AirSentry.SelectSuperRightClickToolboxSection
```

## 排查命令

确认 FinderSync 注册状态：

```text
/usr/bin/pluginkit -m -v -p com.apple.FinderSync
```

正常应看到 AirSentry 扩展为 `+`，并指向 `/Applications/AirSentry.app`：

```text
+    com.sjzm.airsentry.finderextension ... /Applications/AirSentry.app/Contents/PlugIns/AirSentryFinderExtension.appex
```

查看右键链路日志：

```text
/usr/bin/log show --info --style compact --last 5m --predicate "subsystem == 'com.sjzm.airsentry.finderextension' OR eventMessage CONTAINS 'AirSentry Finder extension' OR eventMessage CONTAINS 'AirSentry handling Finder new file request' OR eventMessage CONTAINS 'AirSentry Finder new file' OR eventMessage CONTAINS 'AirSentry failed to create Finder file' OR eventMessage CONTAINS 'AirSentry received malformed Finder new file notification'"
```

典型判断：

- 只有 `requested menu` / `menu target directory`，没有 `create requested`：点击 action 没拿到模板或目标目录。
- 有 `could not read new file menu request object: nil`：`representedObject` 在点击阶段丢失，不能依赖它作为唯一上下文。
- 有 `create requested`，没有 `AirSentry handling Finder new file request`：扩展到宿主 App 的通信失败。
- 有 `target is not authorized`：目标目录没有在工具箱里授权，主 App 应弹窗提示并提供“打开授权设置”。
- 有 `authorization matched` 但仍失败：检查目标路径是否可写、文件名是否非法或目标卷是否只读，主 App 应提示重新授权或检查目录写权限。

清理 FinderSync 注册残留：

```text
scripts/unregister-finder-extension.sh
```

只预览不修改：

```text
scripts/unregister-finder-extension.sh --dry-run --no-restart-finder
```

重新构建、安装并刷新 Finder：

```text
./build.sh --bundle-id com.sjzm.airsentry --identity "Developer ID Application: wuji zhang (T8V48KACU8)" --install
```

## 参考项目结论

### RClick

https://github.com/wflixu/RClick

RClick 的核心思路是主 App + FinderSync Extension 双进程架构：

- 主 App 管理设置、状态和文件操作。
- FinderSync Extension 只负责渲染菜单项和上报点击。
- 两个进程通过 `DistributedNotificationCenter` 通信。

AirSentry 当前采用同类思路，但没有复制 GPL 代码，只参考架构。

### Flicker

https://github.com/yananw-pub/Flicker

Flicker 的方案是：

- Finder 扩展读取共享配置生成菜单。
- 需要打开 App 或创建文件时，通过自定义 URL scheme 转给容器 App。
- 容器 App 处理 URL 后创建文件，并做重名处理。

AirSentry 当前使用 `DistributedNotificationCenter` 作为主路径，URL scheme 作为宿主 App 未运行时的兜底路径。

### RightMenu Master / Menuist

https://github.com/jaywcjlove/rightmenu-master

该仓库主要是官网和反馈页，不是源码仓库。公开文档里能确认的重点是：创建文件依赖文件夹授权，Full Disk Access 不能替代 Finder 扩展所需的用户目录授权。
