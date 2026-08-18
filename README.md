# EReader

<p align="center">
  <img src="assets/icons/icon.svg" width="128px" />
</p>

A lightweight, cross-platform EPUB e-book reader built with Flutter, supporting Android and iOS.

[![Flutter](https://img.shields.io/badge/Flutter-blue.svg)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey.svg)]()

[CHANGELOG](./CHANGELOG.md)

## ✨ Features

- 📚 **EPUB Reading** - EPUB 2.0/3.0 support, smooth page turning, automatic reading progress, WebView-based full EPUB rendering
- 🗂️ **Bookshelf Management** - custom categories, multi-dimensional sorting, batch operations
- 🔗 **Series Merging** - merge multiple books of the same series into one shelf slot, with a count badge and a switchable cover; tap to open the series sub-shelf
- ✋ **Manual Sorting** - long-press and drag to arrange books, series, and books inside a series (order is persisted)
- 🕘 **Recent Reads Category** - a pinned "Recent Reads" tab (cannot be deleted) that opens by default, showing the 5 most recently read books in a large single-cover carousel with a thumbnail strip
- 🖼️ **Image Download** - long-press an image in the reader and save the original format directly to your photo album
- 📏 **Line Spacing Control** - adjust line spacing in the reader settings
- 📦 **Backup & Restore** - export/import your library as a folder; backups created by the original Lumina app can also be imported
- 🎨 **Elegant Interface** - light/dark theme switching

## 🚀 Getting Started

### Download

Grab the latest APK from the [Releases](https://github.com/Chennan28/lumina-plus/releases) page and install it directly on your Android device.

### Build from Source

Requirements: Flutter SDK ≥ 3.38, Dart SDK ≥ 3.10, Rust toolchain + cargo-ndk (for the EPUB parser), Android SDK 36 + NDK (for Android builds).

```bash
git clone https://github.com/Chennan28/lumina-plus.git
cd lumina-plus

flutter pub get

# Android APK (split by CPU architecture)
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-<abi>-release.apk
```

## 📄 License

[MIT](./LICENSE)
