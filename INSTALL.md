# Install Kavii on macOS

Kavii is a small menu-bar app for macOS 13 Ventura and newer. It supports both Apple Silicon Macs (`arm64`) and Intel Macs (`x86_64`).

## Download and install

1. Open the [latest Lil Butterfly release](https://github.com/gajeradhrumil38/lil-butterfly-mac/releases/latest).
2. Download the ZIP matching your Mac:
   - `arm64` for Apple Silicon (M1, M2, M3, M4, and newer)
   - `x86_64` for Intel
3. Double-click the ZIP to unzip it.
4. Drag `LilButterfly.app` into your `/Applications` folder.
5. Open it. Kavii runs quietly in the menu bar; click the butterfly icon to choose **Show a butterfly now** or change its behavior.

Kavii does not need an installer, account, background service, or Terminal command.

## If macOS blocks the first launch

The downloadable build is currently not notarized with an Apple Developer ID. If macOS shows “LilButterfly cannot be opened”, Control-click the app in Applications, choose **Open**, then confirm **Open** once. If that option is not shown, open **System Settings → Privacy & Security**, scroll down, and choose **Open Anyway** for LilButterfly.

Only use releases from this repository. The source and release history are public so the app can be inspected before installation.

## Updates

Kavii checks the repository’s public GitHub Releases endpoint when it launches. It sends no analytics, account information, or personal data. If a newer version exists:

- the menu-bar icon changes to `🦋↑`;
- the menu shows **Update available**;
- selecting it opens the official release page.

Kavii never silently replaces the app. Download the new ZIP, quit the old app, replace `LilButterfly.app` in Applications, and launch it again. Your settings stay in `~/Library/Application Support/LilButterfly/config.json`.

You can also choose **Check for Updates…** from the menu at any time.

## Start automatically

After moving the app to Applications, open **System Settings → General → Login Items** and add `LilButterfly.app` under **Open at Login**.

## Troubleshooting

- If no butterfly appears, click the menu-bar icon and choose **Show a butterfly now**. Make sure the app is not paused.
- If the menu-bar icon is hidden, expand the menu-bar controls or use Control Center; macOS may place extra menu-bar items there on smaller screens.
- For Google Meet in a Chrome or Safari tab, use **Pause** during the meeting. Browser-tab detection needs extra Accessibility permission and is intentionally not enabled.
- To reset settings, quit the app and remove `~/Library/Application Support/LilButterfly/config.json`, then launch it again.

## Build from source

Requirements: macOS 13+ and Xcode 15+ (or Swift through Xcode Command Line Tools).

```bash
git clone https://github.com/gajeradhrumil38/lil-butterfly-mac.git
cd lil-butterfly-mac
swift run
```

To create a local app bundle:

```bash
APP_VERSION=1.0.0 ./scripts/make_app_bundle.sh
```

## Publish a release (maintainer guide)

The release workflow builds separate Apple Silicon and Intel ZIPs and attaches them to a GitHub Release. To publish a version:

```bash
git add .
git commit -m "Prepare Lil Butterfly 1.0.1"
git tag v1.0.1
git push origin main --follow-tags
```

Pushing a tag matching `v*.*.*` starts the workflow in `.github/workflows/release.yml`. It builds both architectures, creates the release, and generates release notes automatically. The in-app updater will then discover it.

## Enable this page on GitHub

In the repository, open **Settings → Pages**, choose **Deploy from a branch**, select `main` and the `/docs` folder, then save. The public page will be:

`https://gajeradhrumil38.github.io/lil-butterfly-mac/`
