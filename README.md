# Omacrazy

A personal macOS theme switcher. It applies theme settings for the apps and system preferences that have an adapter, and reports targets as applied, skipped, or failed.

## Run

From the project root, run:

```sh
swift run omacrazy theme aetheria
```

Themes are stored in `themes/<name>/`. A target is skipped when its theme-specific file is missing. Each adapter runs independently, so one failure does not prevent the other targets from being attempted.

## Current adapters

### Ghostty

When `ghostty.conf` is present, Omacrazy copies it into Ghostty's macOS config folder and adds a managed `config-file` include to Ghostty's active config (`config` if present, otherwise `config.ghostty`). It backs up the existing config once beside the original with the suffix `.omacrazy-backup`. Ghostty reloads its configuration with **Cmd+Shift+Comma**.

Set `OMACRAZY_GHOSTTY_CONFIG_DIR` to use a different Ghostty config folder.

### JankyBorders

When `hyprland.conf` contains `col.active_border`, Omacrazy maps the first and last colors to JankyBorders' diagonal active-color gradient. It updates a running JankyBorders process through the `borders` command. It also saves the setting in `~/.config/borders/bordersrc` for future launches, backing up an existing file once as `bordersrc.omacrazy-backup`. The inactive JankyBorders color is left unchanged.

Set `OMACRAZY_BORDERS_CONFIG` to use a different bordersrc path.

### Zed

When a theme includes JSON under `zed/themes/` (or a root `zed.json`), Omacrazy copies the theme file into `~/.config/zed/themes/` and selects its dark theme name in `~/.config/zed/settings.json`. It backs up changed settings once as `settings.json.omacrazy-backup`, and changes only the root `theme` value, preserving other settings and JSONC comments. A replaced local theme file is backed up beside it with the suffix `.omacrazy-backup`.

Zed may need to reload its theme list before a newly installed local theme appears.

### Wallpaper

When a theme has supported images (`jpg`, `jpeg`, `png`, `heic`, or `webp`) in `backgrounds/`, Omacrazy randomly chooses one each time the theme is applied and sets it on every connected display using macOS AppKit. It preserves each display's current scaling options. The selected image is copied to `~/Library/Application Support/Omacrazy/themes/<name>/backgrounds/` so the wallpaper does not depend on the source checkout remaining in place.

## Aetheria

The first imported theme is [JJDizz1L/aetheria](https://github.com/JJDizz1L/aetheria). Its files and MIT license are kept in `themes/aetheria/`. The project copy of its Zed theme is at `themes/aetheria/zed/themes/Aetheria.json`; its background surfaces currently use 95% alpha, though the translucent effect has not yet been confirmed in Zed.

## Requirements

- macOS 13 or later and a Swift toolchain supported by the installed macOS SDK.
- Ghostty and Zed settings can be prepared while those apps are closed. JankyBorders is updated live only when its process is running; otherwise the color is saved for its next launch.
- JankyBorders itself requires macOS 14 or later.
