# Reynard Default Browser iOS 14

Opens links destined for Safari, Chrome, Firefox or Brave in Reynard on a **rootful iOS 14 jailbreak**, including iOS 14.3.

Install Reynard, PreferenceLoader and CCSupport, then install the `.deb` and respring once. Enabled by default. Use **Settings → Reynard Default** or add **Reynard Default** in Control Centre settings to switch it on or off without respringing.

This redirects external browser links; it does not add Reynard to Apple's Default Browser menu. In-app browsers and universal links may keep their normal behaviour. Tapping another browser's app icon still opens that browser. If Reynard is missing, links keep their original destination.

Requires a Reynard version supporting `reynard://open?url=…`. Built for arm64 and arm64e, with `iphoneos-arm` rootful packaging. Device testing on iOS 14.3 is still required.

## Build

With Theos and the iOS 14.5 SDK installed: `make rootful THEOS=/path/to/theos`. GitHub Actions also builds and checks the package on each push. Download the `reynard-default-ios14-rootful` build artifact, or the `.deb` from Releases after a successful build on main.

Based on [guacforlife/ReynardDefault](https://github.com/guacforlife/ReynardDefault), upstream commit `99bd11f5d71221868f59c572ec5f8814a643c75d`. Rootful build paths, complete URL encoding, URL/bundle setter ordering, installation fallback and Settings icon adapted for this port. Original author: guacforlife. Licensed under GPL-3.0; see LICENSE.
