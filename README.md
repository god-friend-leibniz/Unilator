# Offline Dictionary & Universal Converter

A lightning-fast, fully offline dictionary application built with Flutter.

Got tired of switching between Oxford Learner's Dictionary and Yandex Translator? This app contains everything you need and provides convenient interface

## ✨ Features

- **Universal Format Support:** Easily import classic StarDict (`.idx` / `.dict`), compressed DictZip (`.dict.dz`), and popular MDict (`.mdx`) databases.
- **Hybrid AI Translation:** Includes a built-in translation button. If you have an internet connection, it queries the Google Translate API for perfect translations. If offline, it seamlessly falls back to **Google ML Kit** (on-device neural network).
- **Deep Search Mode:** Looking for a phrasal verb which wasn't found? Toggle "Deep Search" to thoroughly scan the base word's entire article and extract all specific phrase examples.
- **Native Rendering:** No webviews or heavy HTML parsers. Text is rendered using native Flutter `RichText`, perfectly adapting to the system's Dark/Light theme.
- **Clean Architecture:** 100% pure Dart on the mobile side.

---

## 🛠 Prerequisites

### 1. For Dictionary Conversion (PC)

To process and clean raw dictionary databases, you need a Unix-like environment (macOS/Linux) and **Python 3.8+**:

- **PyGlossary** (for `.mdx` support):

```bash
  pip install pyglossary
```

_(Note: The script expects `ipy` to be available, so you might need to adjust the bash script to call `pyglossary` directly)._

- **DictZip utility** (optional, dramatically speeds up `.dz` extraction):

### 2. For the Mobile App

- **Flutter SDK:** version 3.16 or higher.

---

## 🗂 How to Add Dictionaries

We provide an automated bash script that handles unpacking, unzipping, extracting, converting, and cleaning your dictionary files.

**Step 1:** Download your desired dictionaries (`.tar.bz2`, `.tar.gz`, `.zip`, `.mdx`) and place them into the `assets/` folder of your project.

**Step 2:** Ensure the parser script (`parser.py`) is located next to your bash script (`converter.sh`). Open `converter.sh` and make sure the `ASSETS_DIR` variable points to your `assets` directory.

**Step 3:** Make the script executable and run it:

```bash
chmod +x converter.sh && ./converter.sh
```

**What the script does:**

1. Unpacks all archives automatically.
2. Unzips `.dict.dz` files into raw `.dict` files.
3. Converts `.mdx` databases into StarDict format using PyGlossary.
4. Feeds only the _new_ files into `parser.py`, which strips out the messy HTML and outputs highly optimized `*_clean.idx` and `*_clean.dict` files into the `assets/clean/` directory.

---

## 🚀 Building & Running

**Important Setup Note (Android):**
Because this app uses Google ML Kit for offline AI translation, you must ensure your Android `minSdkVersion` is at least **21**.
Open `android/app/build.gradle` and update the `defaultConfig`:

```gradle
defaultConfig {
    applicationId "com.your.package.name"
    minSdkVersion 21  // <-- Ensure this is 21 or higher
    targetSdkVersion flutter.targetSdkVersion
    // ...
}
```

Once dependencies and dictionaries are in place, run the app:

```bash
# Clean previous builds and fetch packages
flutter clean
flutter pub get

# Run on a connected device/emulator
flutter run

# Build release APK
flutter build apk --release
```

---

## 🧠 How the Architecture Works

Instead of forcing the mobile CPU to parse 20-year-old messy HTML with Regex at runtime, the heavy lifting is done during compilation:

1. **Python Parser:** Scans for specific tags (`<k>`, `<ex>`, `<c>`), forces string breaks, removes 100% of the markup, and packs the semantic meaning into a lightweight JSON array `[{"t": "h", "v": "carry on"}, ...]`.
2. **Dart Engine:** Loads the compact `_clean.idx` into RAM on app startup. When searching, it uses binary search to find the word, grabs the exact byte offset, and fetches the JSON string directly from the disk (zero RAM bloat).
3. **Flutter UI:** Parses the JSON instantly. When Deep Search is enabled, it filters out irrelevant blocks. It automatically assigns the correct typography and colors based on block types (Headers, Grammar, Examples) and the active system theme.
