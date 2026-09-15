# Publish a Butterfly update

The GitHub workflow creates one universal `Butterfly.app` download that runs on Apple Silicon and Intel Macs.

## Local development

```bash
swift run Butterfly
```

Create a local app bundle:

```bash
APP_VERSION=1.0.0 ./scripts/make_app_bundle.sh
```

## Publish

Commit the finished changes, then create and push a semantic version tag:

```bash
git tag v1.0.1
git push origin main --follow-tags
```

The workflow builds arm64 and x86_64 executables, combines them into one universal app, and publishes `Butterfly-1.0.1.zip`. Installed copies discover the release through **Check for Updates…**.

## Publish the website

In GitHub, open **Settings → Pages** and choose:

- Source: **Deploy from a branch**
- Branch: **main**
- Folder: **/docs**

The site will be available at:

`https://gajeradhrumil38.github.io/lil-butterfly-mac/`
