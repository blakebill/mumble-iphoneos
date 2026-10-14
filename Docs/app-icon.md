# Liquid Glass App 图标

主图标使用 `Resources/AppIcon.icon`，通过 Xcode 的 Icon Composer 图标编译流程打包。前景是可缩放的白色 Mumble 耳机标志，明确启用玻璃材质；背景使用深色自动渐变。原生材质负责光照、高光和浅色、深色、透明及着色外观。

耳机轮廓来自 Mumble 官方 `icons/mumble_small.svg`，作者 Martin Skilnand（2009），使用其 BSD 许可。去掉原图的预绘光影和背景，保留矢量几何，让系统生成效果。许可与出处随 `Legal.html` 打包。

标志经过尺寸与中心调整，可见宽度约占画布 70%、高度约占 75%，比上一版略缩小。顶部 M 形采用平滑转角，耳罩合为圆润轮廓，去掉旧图形内部细缝，麦克风为圆角胶囊。前景使用同向子路径组成的单一轮廓，让相接部分连贯地接受玻璃光照。这些比例是针对该标志的视觉选择，不是 Apple 的硬性百分比要求。主体与圆角边缘保持距离，画布仍为未经预裁圆角的 1024×1024 方形。

`ASSETCATALOG_COMPILER_APPICON_NAME` 指向 `AppIcon`；移除旧的手写图标列表及 `UIPrerenderedIcon`，由 Xcode 写入实际主图标信息。最低 iOS 版本仍为 18.0，编译器同时生成旧系统的静态回退图标。原始 PNG 留在仓库中。

## 验证

- Apple `ictool` 成功导出默认、深色和透明外观，已查看实际导出结果。
- iPhone Release、模拟器 Debug 构建通过，无 App 构建警告。
- 真机安装包的主图标名为 `AppIcon`；`Assets.car` 包含原生 `IconGroup`、`IconImageStack` 与矢量前景，而不仅是扁平 PNG。
- 最新版本已安装到 iPhone。导出预览和构建产物位于临时目录。
