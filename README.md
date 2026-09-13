# Reynard Default Browser iOS 14

Opens links destined for Safari, Chrome, Firefox or Brave in Reynard on a **rootful iOS 14 jailbreak**, including iOS 14.3.

Install Reynard, PreferenceLoader and CCSupport, then install the `.deb` and respring once. Enabled by default. Use **Settings → Reynard Default** or add **Reynard Default** in Control Centre settings to switch it on or off without respringing.

This redirects external browser links; it does not add Reynard to Apple's Default Browser menu. In-app browsers and universal links may keep their normal behaviour. Tapping another browser's app icon still opens that browser. If Reynard is missing, links keep their original destination.

Requires a Reynard version supporting `reynard://open?url=…`. Built for arm64 and arm64e, with `iphoneos-arm` rootful packaging. Device testing on iOS 14.3 is still required.

## Build

With Theos and the iOS 14.5 SDK installed: `make rootful THEOS=/path/to/theos`. GitHub Actions also builds and checks the package on each push. Download the `reynard-default-ios14-rootful` build artifact, or the `.deb` from Releases after a successful build on main.

Based on [guacforlife/ReynardDefault](https://github.com/guacforlife/ReynardDefault), upstream commit `99bd11f5d71221868f59c572ec5f8814a643c75d`. Rootful build paths, complete URL encoding, launch-options/bundle setter ordering, installation fallback and Settings icon adapted for this port. Original author: guacforlife. Licensed under GPL-3.0; see LICENSE.

## Why this differs from the upstream iOS 14 build

The original rootless implementation swaps the browser bundle ID. The later upstream iOS 14 change attempts `request.URL`, but the [iOS 14 request header](https://github.com/SparkDev97/iOS14-Runtime-Headers/blob/master/PrivateFrameworks/FrontBoard.framework/FBSystemServiceOpenApplicationRequest.h) exposes `options`, with the URL in [FBSOpenApplicationOptions.url](https://github.com/SparkDev97/iOS14-Runtime-Headers/blob/master/PrivateFrameworks/FrontBoardServices.framework/FBSOpenApplicationOptions.h).

This implementation rewrites the payload URL in a copy of the launch options, verifies that it was retained, then changes the destination. It handles either order of the bundle and options setters, preserving the other launch options. It does not hook an invented request URL property.
