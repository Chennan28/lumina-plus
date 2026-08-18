# EReader

<p align="center">
  <img src="assets/icons/icon.svg" width="128px" />
</p>

一个基于 Flutter 开发的轻量级 EPUB 电子书阅读器，支持 Android 和 iOS 双平台。

[![Flutter](https://img.shields.io/badge/Flutter-blue.svg)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey.svg)]()

[CHANGELOG](./CHANGELOG.md)

## ✨ 核心功能

- 📚 **EPUB 阅读** - 支持 EPUB 2.0/3.0 格式，流畅翻页，自动保存阅读进度，基于 WebView 的完整 EPUB 渲染
- 🗂️ **书架管理** - 自定义分类、多维度排序、批量操作
- 🔗 **系列合并** - 将同一系列的多本书合并为书架上的一个位置，封面带数量角标、可自行切换；点击进入该系列的子书架
- ✋ **手动排序** - 长按封面拖动即可调整书籍、系列以及系列内书籍的顺序（顺序持久化保存）
- 🕘 **最近阅读分类** - 书架顶部固定的"最近阅读"分类（不可删除），进入 App 默认打开；以单本大封面轮播展示最近阅读的 5 本书，底部带缩略图快速切换
- 🖼️ **图片下载** - 阅读时长按图片可查看大图，并一键将原始格式图片保存到手机相册
- 📏 **行距调节** - 阅读设置中可自由增加/减少行距
- 📦 **备份与恢复** - 书架支持整体备份/恢复为文件夹；原 Lumina 阅读器导出的备份书库也可以直接导入
- 🎨 **优雅界面** - 亮暗主题切换，舒适阅读体验

## 🚀 快速开始

### 下载安装

前往 [Releases](https://github.com/Chennan28/lumina-plus/releases) 页面下载最新 APK，直接安装到 Android 手机即可。

### 从源码构建

环境要求：Flutter SDK ≥ 3.38、Dart SDK ≥ 3.10、Rust 工具链 + cargo-ndk（EPUB 解析引擎）、Android SDK 36 + NDK（构建安卓包时）。

```bash
git clone https://github.com/Chennan28/lumina-plus.git
cd lumina-plus

flutter pub get

# 构建 Android APK（按 CPU 架构分包）
flutter build apk --release --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-<abi>-release.apk
```

## 📄 开源许可

[MIT](./LICENSE)
