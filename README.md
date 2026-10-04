# Prism

双列 **Material Design 3** 文件管理器，使用 Flutter 编写，仅面向 Android。

- **包名**：`com.voxyn.prism`
- **应用名**：Prism
- **最低版本**：Android 5.0（API 21）
- **主题**：Monet 壁纸动态取色（Android 12+），旧系统回退内置种子色
- **模式**：跟随系统 / 浅色 / 深色

## 功能一览

| 分类 | 能力 |
| --- | --- |
| 双列浏览 | 宽屏并排双列、窄屏一键切换；两列各自独立的历史、路径与选择状态 |
| 导航 | 前进/后退/上级、可点击面包屑（超长自动折叠）、存储卷与常用目录抽屉、书签 |
| 列表 | 列表/网格切换、四种排序（名称/大小/时间/类型，含自然序）、三档密度、即时过滤 |
| 选择 | 长按进入多选、全选、反选、范围选择 |
| 文件操作 | 复制、剪切、粘贴、删除、重命名、批量重命名（查找替换 / 前后缀 / 正则）、新建文件夹与文件 |
| 跨列操作 | 直接「复制到另一列」「移动到另一列」，无需经过剪贴板 |
| 查看 | 内置图片缩放查看、文本预览（大文件截断提示）、其余类型交由系统应用打开 |
| 搜索 | 当前目录递归搜索，流式出结果、支持正则、可停止、在面板中定位 |
| 其它 | 属性面板（目录占用空间实时统计）、分享、复制路径、媒体库扫描 |

## 性能设计

- 目录列举只做一次 `list`，随后以 **24 路并发** 批量 `stat`，避免逐项串行等待
- 列表使用固定 `itemExtent`，让 `ListView` 走更快的布局路径；每行包 `RepaintBoundary`
- 缩略图走 **LRU 缓存**（上限 160 张）并限制解码宽度为 256px，解码完成前回退类型图标
- 目录占用空间统计在**后台 isolate** 中执行，不阻塞 UI
- 复制/移动使用 512 KiB 缓冲区流式处理，大文件不会整份读入内存
- 请求系统最高刷新率（`preferredDisplayModeId`），并在设置页可开关
- 目录切换带**竞态保护**：快速连点只有最后一次请求的结果会生效

## 项目结构

```
lib/
├── core/                     纯逻辑，无 Flutter 依赖
│   ├── app_constants.dart    全局常量
│   ├── file_utils.dart       路径/扩展名/类别推断/MIME
│   └── formatters.dart       大小、时间、刷新率格式化
├── data/
│   ├── models/               FileEntry、StorageVolume、SortSpec
│   ├── file_repository.dart  只读访问：列举、并发 stat、搜索、文本预览
│   ├── file_operations.dart  写操作：复制/移动/删除/重命名 + isolate 扫描
│   ├── native_bridge.dart    原生通道封装（失败自动降级）
│   ├── storage_permission.dart 存储权限申请与引导
│   └── thumbnail_cache.dart  LRU 缩略图缓存
├── state/
│   ├── settings_controller.dart  持久化设置
│   ├── pane_controller.dart      单列状态：导航、排序、选择、加载
│   ├── file_clipboard.dart       文件剪贴板
│   └── app_state.dart            双列总控与跨列操作
├── theme/app_theme.dart      M3 主题与种子色
└── ui/
    ├── pages/                主界面、设置页
    ├── panes/                单列视图
    ├── widgets/              工具栏、面包屑、列表/网格项、缩略图、操作栏
    ├── dialogs/              操作面板、输入框、属性
    ├── search/               递归搜索页
    └── viewers/              图片/文本查看器
```

## 开发

```bash
flutter pub get
flutter analyze     # 零 issue
flutter test        # 29 项测试
flutter run
```

## Android 权限说明

文件管理器需要完整读写共享存储：

- Android 11+ 需要 **「所有文件访问权限」**（`MANAGE_EXTERNAL_STORAGE`）。
  该权限只能由用户在系统设置中手动授予，应用启动时会检测并引导跳转。
- Android 10 及以下使用 `READ/WRITE_EXTERNAL_STORAGE`。
- Android 13+ 读取媒体文件另有 `READ_MEDIA_IMAGES/VIDEO/AUDIO` 细分权限。

未获授权时应用仍可浏览有权限的目录，并在界面上给出明确提示。

## 已知限制

- 未获取存储权限时，部分目录会显示为不可访问
- `svg` 不做内置预览（需要额外渲染器），交由系统处理
- 压缩包仅识别类型，未实现解压（依赖 `archive` 等第三方库，可后续扩展）
