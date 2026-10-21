# PixOS ⇄ 

> **Bypass iCloud Storage Fees Forever.** The native macOS app and CLI utility that extracts full-resolution photos, 4K videos, and Live Photos from your iPhone and syncs them to Google Pixel via ADB for lifetime free unlimited original-quality Google Photos cloud backups.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B%20(Sonoma%20%7C%20Sequoia)-black?logo=apple)](https://apple.com)
[![Swift 6](https://img.shields.io/badge/Swift-6.0%20%7C%205.9-orange?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Universal-purple)]()
[![Google Photos Unlimited](https://img.shields.io/badge/Google%20Photos-Unlimited%20Original%20Backup-green?logo=google-photos)]()

---

## 🌟 Why PixOS?

The **original 2016 Google Pixel (OG Pixel / sailfish / marlin)** comes with a unique lifetime perk: **free, unlimited original-quality photo and video backup to Google Photos forever**.

If you own an iPhone and are tired of paying Apple $36 to $360 every year for expanding iCloud storage tiers (50GB, 200GB, 2TB), PixOS gives you a seamless bridge:
1. Connect your iPhone to your Mac over USB cable.
2. Connect your Google Pixel to your Mac (via USB cable or **Wireless Wi-Fi ADB**).
3. **PixOS** extracts full-resolution original media losslessly, automatically merges iPhone Live Photos into **Google Motion Photos** with official XMP metadata, stages and pushes them via ADB to `/sdcard/DCIM/iPhone/`, triggers Android media scanning, and cleans up your Mac cache.
4. Google Photos on your Pixel immediately uploads them to the cloud at **100% original quality** without consuming a single byte of your Google account storage.
5. **Reclaim iPhone space**: Once verified, PixOS offers an optional prompt to delete the backed-up photos from your iPhone.

---

## 📸 Key Features

- **Liquid Glass macOS Desktop App**: Designed with Apple Retina Liquid Glass vibrancy, live device status pulses (iPhone USB & Pixel ADB), interactive storage gauges, and real-time speed & progress monitors.
- **Apple Live Photos → Google Motion Photos**: Injects standardized Google Camera XMP container metadata (`Camera:MotionPhoto="1"`) and multiplexes your 3-second companion `.MOV` video directly into the photo. Google Photos renders and animates them natively!
- **Bundled Standalone ADB**: Comes with prepackaged `adb` binary. No Android Studio, no Homebrew, and no terminal installation needed for non-technical users.
- **Native ImageCaptureCore**: Direct hardware communication over USB. Zero third-party iOS kernel drivers, zero jailbreaks, and zero pairing certificates.
- **Dual-Mode ADB (USB & Wi-Fi)**: Keep your Pixel on its charging stand across the room and connect wirelessly over local Wi-Fi via Wireless ADB.
- **Smart Batching & Storage Safeguard**: Avoids overwhelming your Pixel's 32GB/128GB disk. Transfers in configurable batches (e.g., 5GB), checks free storage before each batch, and pauses gracefully if space is low.
- **Auto-Purge Staging Cache**: Staged files on your Mac are verified on the Pixel and deleted per-batch to prevent filling up your MacBook's SSD.
- **Local SQLite Deduplication**: Tracks synced media fingerprints in `~/.pixos/sync_state.db`. Subsequent syncs automatically skip already-backed-up media.
- **Full-Featured Terminal CLI (`pixos`)**: Scriptable command-line tool with color-coded tables, dry-run flags, and batch options for advanced users and power workflows.

---

## 🚀 Quick Start (Download App)

1. Download the latest **`PixOS-1.0.0.dmg`** from [Releases](https://github.com/exactablehq/PixOS/releases).
2. Open the DMG and drag **`PixOS.app`** to your **`/Applications`** folder.
3. Launch PixOS and connect your devices:
   - **iPhone**: Plug in via Lightning / USB-C, unlock your phone, and tap **"Trust This Computer"** if prompted.
   - **Google Pixel**: Enable **Developer Options** and turn on **USB Debugging**. Plug in via USB or click **"Wireless ADB"** to pair over your home Wi-Fi.
4. Click **"Start Sync to Pixel"**.

---

## 💻 Terminal CLI Usage (`pixos`)

If you prefer using the terminal, PixOS compiles to a standalone, universal CLI binary:

```bash
# Check device connections, storage, and database statistics
pixos status

# Start interactive sync with 5GB batch limit
pixos sync --batch-size 5G

# Dry run (scan camera roll and compute pending transfers without pushing)
pixos sync --dry-run

# Connect to Google Pixel wirelessly over Wi-Fi
pixos connect-wireless 192.168.1.150

# View backup history and stats
pixos history
```

### CLI Flags:
| Option | Description | Default |
|---|---|---|
| `--batch-size <GB>` | Maximum size per batch before pausing | `5G` |
| `--no-motion-photos` | Push Live Photo companion MOV separately | `false` |
| `--exclude-screenshots`| Skip screenshots and screen recordings | `false` |
| `--exclude-videos` | Skip standalone video files | `false` |
| `--pixel-path <path>` | Remote destination folder on Pixel | `/sdcard/DCIM/iPhone` |
| `--delete-after` | Prompt to safely delete backed-up items from iPhone | `false` |
| `--dry-run` | Preview pending media without transferring | `false` |

---

## 🏗️ Architecture & Pipeline

```mermaid
graph TD
    subgraph iPhone [iPhone via USB]
        iOSMedia[Original Photos, 4K/HDR Videos, Live Photos]
    end

    subgraph PixOSMac [PixOS Native macOS Engine]
        IC[ImageCaptureCore Native Manager]
        Stage[Mac Staging Cache]
        XMP[Live Photo -> Google Motion Photo Synthesizer]
        SQLite[(SQLite Deduplication State)]
        Batch[Smart Storage Batcher & Safeguard]
        BundledADB[Bundled Standalone ADB Binary]
        SwiftUIApp[Retina Liquid Glass App]
        CLITool[pixos Terminal CLI]
    end

    subgraph Android [Google Pixel 2016]
        PixelDisk[Pixel Internal Storage /sdcard/DCIM/iPhone/]
        MediaScan[Android MediaScanner]
        GPhotos[Google Photos: Unlimited Free Original Backup]
    end

    iPhone -->|USB Camera API| IC
    IC --> Stage
    Stage --> XMP
    XMP --> SQLite
    SQLite --> Batch
    Batch --> BundledADB
    BundledADB -->|ADB USB or Wireless| PixelDisk
    BundledADB -->|Trigger MediaStore| MediaScan
    MediaScan --> GPhotos
    GPhotos -.->|Optional Safe Prompt| Del[Safe Delete from iPhone]
```

---

## 🛠️ Building From Source

### Prerequisites:
- macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9 or Swift 6.0+

### Steps:
```bash
# 1. Clone repository
git clone https://github.com/exactablehq/PixOS.git
cd PixOS

# 2. Run test suite
swift run --build-system native test-runner

# 3. Build CLI binary
swift build -c release --build-system native --product pixos

# 4. Build native macOS .app and distributable .dmg
bash scripts/package_dmg.sh
```
The packaged DMG is saved to `dist/PixOS-1.0.0.dmg`.

---

## ❓ Frequently Asked Questions

<details>
<summary><strong>Why does the original 2016 Google Pixel have unlimited storage?</strong></summary>
When Google launched the original Pixel in 2016, they included a lifetime contractual pledge of free unlimited original quality Google Photos uploads for any media uploaded through the device. This policy has never been revoked and applies to all photos and videos pushed to the device.
</details>

<details>
<summary><strong>Will my photos or 4K videos be compressed?</strong></summary>
No. PixOS extracts the pristine original files from your iPhone without transcoding. Photos (HEIC/JPEG), ProRAW DNGs, and 4K HDR videos are uploaded in 100% untouched original quality.
</details>

<details>
<summary><strong>How does PixOS handle Apple Live Photos?</strong></summary>
iPhones record Live Photos as a paired still image and a 3-second MOV video. PixOS synthesizes a standard Google Camera Motion Photo by injecting XMP metadata (`Camera:MotionPhoto="1"`) and concatenating the video stream. Google Photos recognizes and plays them as native motion photos.
</details>

<details>
<summary><strong>Is it safe to delete backed-up photos from my iPhone?</strong></summary>
PixOS is strictly read-only by default. After a batch is transferred and verified on the Pixel, PixOS displays an optional prompt to delete backed-up media from the iPhone. It will never delete any file without your explicit confirmation.
</details>

---

## 🤝 Contributing

Contributions are warmly welcomed! Please read our [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md).

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.

Copyright © 2026 **Exactable** ([exactablehq](https://github.com/exactablehq)).
