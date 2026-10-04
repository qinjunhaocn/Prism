package com.voxyn.prism

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Prism 的 Android 宿主 Activity。
 *
 * 通过 [MethodChannel] 向 Dart 侧暴露少量必须依赖系统 API 的能力：
 * 存储卷枚举、刷新率查询与切换、系统打开/分享、MIME 推断、媒体扫描。
 *
 * 所有方法都做了异常兜底，失败时返回 null/false，绝不向上抛出未捕获异常，
 * 以免影响 Flutter 侧的稳定性。
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.voxyn.prism/native"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listStorageVolumes" -> result.success(listStorageVolumes())
                    "getRefreshRate" -> result.success(refreshRateInfo())
                    "setMaxRefreshRate" -> result.success(setMaxRefreshRate())
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mimeType")
                        result.success(path != null && openFile(path, mime))
                    }
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mimeType")
                        result.success(path != null && shareFile(path, mime))
                    }
                    "getMimeType" -> {
                        val path = call.argument<String>("path")
                        result.success(path?.let { guessMimeType(it) })
                    }
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) scanFile(path)
                        result.success(null)
                    }
                    "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "trimMemory" -> {
                        // 尽力提示系统回收，失败无副作用。
                        onTrimMemory(TRIM_MEMORY_UI_HIDDEN)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------- 存储卷

    /**
     * 枚举可用的存储卷。
     *
     * 使用 [StorageManager.getStorageVolumes]（API 24+）拿到真实容量；
     * 失败时退回主共享存储与根目录。
     *
     * 注意：这里只能使用 `StorageVolume.getDirectory()`，不能使用
     * `getPath()` —— 后者已在 API 36 的公开存根中被移除，用它会导致
     * Kotlin 编译期报 `Unresolved reference`（与运行时版本无关，
     * 因此用 SDK_INT 分支也无法规避）。
     */
    private fun listStorageVolumes(): List<Map<String, Any?>> {
        val volumes = mutableListOf<Map<String, Any?>>()

        try {
            val storageManager = getSystemService(StorageManager::class.java)
            if (storageManager != null) {
                for (volume in storageManager.storageVolumes) {
                    // getDirectory() 自 API 24 起即可用，无需版本判断。
                    val directory = volume.directory ?: continue
                    if (!directory.canRead()) continue
                    val path = directory.absolutePath

                    var total = 0L
                    var free = 0L
                    try {
                        total = directory.totalSpace
                        free = directory.usableSpace
                    } catch (_: Exception) {
                        // 某些卷不支持查询容量，保持 0。
                    }

                    volumes.add(
                        mapOf(
                            "path" to path,
                            "label" to volume.getDescription(this),
                            "totalBytes" to total,
                            "freeBytes" to free,
                            "isPrimary" to volume.isPrimary,
                            "isRemovable" to volume.isRemovable,
                        )
                    )
                }
            }
        } catch (_: Exception) {
            // 落到下面的兜底逻辑。
        }

        if (volumes.isEmpty()) {
            val primary = Environment.getExternalStorageDirectory()
            if (primary != null && primary.exists()) {
                volumes.add(
                    mapOf(
                        "path" to primary.absolutePath,
                        "label" to "内部存储",
                        "totalBytes" to primary.totalSpace,
                        "freeBytes" to primary.usableSpace,
                        "isPrimary" to true,
                        "isRemovable" to false,
                    )
                )
            }
            volumes.add(
                mapOf(
                    "path" to "/",
                    "label" to "根目录",
                    "totalBytes" to 0L,
                    "freeBytes" to 0L,
                    "isPrimary" to false,
                    "isRemovable" to false,
                )
            )
        }

        return volumes
    }

    // ---------------------------------------------------------------- 刷新率

    /** 读取当前与最高刷新率，以及设备支持的全部候选值。 */
    private fun refreshRateInfo(): Map<String, Any?> {
        val display = currentDisplay() ?: return emptyMap<String, Any?>()

        val supported = mutableSetOf<Float>()
        try {
            for (mode in display.supportedModes) {
                supported.add(mode.refreshRate)
            }
        } catch (_: Exception) {
            // 忽略：supported 可能为空。
        }
        supported.add(display.refreshRate)

        return mapOf(
            "current" to display.refreshRate.toDouble(),
            "max" to (supported.maxOrNull() ?: display.refreshRate).toDouble(),
            "supported" to supported.sorted().map { it.toDouble() },
        )
    }

    /**
     * 请求把窗口切换到设备支持的最高刷新率。
     *
     * 原理：把 `preferredDisplayModeId` 设为刷新率最高的显示模式。
     * 在分辨率不低于当前模式的前提下选取，避免切换后画面变糊。
     *
     * 返回切换后的实际刷新率；无法切换时返回 null。
     */
    private fun setMaxRefreshRate(): Double? {
        val window = window ?: return null
        val display = currentDisplay() ?: return null

        return try {
            val modes = display.supportedModes
            if (modes.isEmpty()) {
                return null
            }

            val currentMode = display.mode
            val currentWidth = currentMode?.physicalWidth ?: 0
            val currentHeight = currentMode?.physicalHeight ?: 0
            val candidates = modes.filter { mode ->
                currentWidth == 0 ||
                    (mode.physicalWidth >= currentWidth && mode.physicalHeight >= currentHeight)
            }
            val best = (if (candidates.isNotEmpty()) candidates else modes.toList())
                .maxByOrNull { it.refreshRate }

            if (best != null) {
                val attributes = window.attributes
                if (attributes.preferredDisplayModeId != best.modeId) {
                    attributes.preferredDisplayModeId = best.modeId
                    window.attributes = attributes
                }
            }
            display.refreshRate.toDouble()
        } catch (_: Exception) {
            null
        }
    }

    /** 取当前显示对象，兼容新旧 API。 */
    private fun currentDisplay(): android.view.Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager?.defaultDisplay
        }
    }

    // ------------------------------------------------------------ 打开/分享

    /** 用系统默认应用打开文件；没有可用应用时返回 false。 */
    private fun openFile(path: String, mimeType: String?): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uriFor(file), mimeType ?: guessMimeType(path))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    /** 调起系统分享面板。 */
    private fun shareFile(path: String, mimeType: String?): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType ?: guessMimeType(path)
                putExtra(Intent.EXTRA_STREAM, uriFor(file))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(intent, "分享文件").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 为文件生成可跨进程访问的 content:// URI。
     *
     * 共享存储之外的路径无法被其它应用直接读取，必须通过 [FileProvider]
     * 授权；该 Provider 已在 AndroidManifest 中声明。
     */
    private fun uriFor(file: File): Uri {
        return try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (_: Exception) {
            // FileProvider 未覆盖该路径时退回 file://（仅同进程可用）。
            Uri.fromFile(file)
        }
    }

    /** 用系统 MimeTypeMap 推断 MIME，未知则返回通配类型。 */
    private fun guessMimeType(path: String): String {
        val extension = path.substringAfterLast('.', "").lowercase()
        if (extension.isEmpty()) return "*/*"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
    }

    /** 触发媒体扫描，让新写入的媒体文件出现在系统媒体库中。 */
    private fun scanFile(path: String) {
        try {
            val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                data = Uri.fromFile(File(path))
            }
            sendBroadcast(intent)
        } catch (_: Exception) {
            // 忽略：扫描失败不影响文件本身。
        }
    }
}
