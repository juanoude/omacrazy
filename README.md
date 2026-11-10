# Omacrazy

A personal macOS theme switcher. It applies theme settings for the apps and system preferences that have an adapter, and reports targets as applied, skipped, or failed.

## Run

From the project root, run:

```sh
swift run omacrazy theme aetheria
```

Run `omacrazy theme` without a name to choose from the available theme folders. Use **↑/↓** to move and **Enter** to apply. **Esc**, **q**, or **Ctrl-C** cancels without applying a theme. The list scrolls for larger collections. The picker requires an interactive terminal; scripts can keep using `omacrazy theme <name>`.

To build and install the `omacrazy` command in `~/.local/bin`, run:

```sh
./install.sh
```

The install directory can be changed with `OMACRAZY_INSTALL_DIR`, for example `OMACRAZY_INSTALL_DIR="$HOME/bin" ./install.sh`. Add that directory to `PATH` if the installer reports that it is missing. To uninstall, remove the installed executable with `rm "$HOME/.local/bin/omacrazy"` (or the corresponding path if you changed the install directory).

To add a theme from a GitHub repository, run:

```sh
swift run omacrazy theme add https://github.com/bjarneo/omarchy-futurism-theme futurism
```

Omacrazy checks out the repository into a temporary directory, then copies its contents into `themes/<name>/`. Git metadata and Git-only files (`.git`, `.gitignore`, `.gitattributes`, and `.gitmodules`) are omitted. The destination name must contain only letters, numbers, hyphens, or underscores, and an existing theme is never overwritten. Git must be installed, and the command needs network access to GitHub.

When `colors.toml` is missing and `alacritty.toml` exists, applying a theme or inferring an app config creates the palette first. Existing palettes are preserved, including previously generated ones. The fallback reads Alacritty's primary colors, 16 normal/bright ANSI colors, cursor, and selection; it resolves `CellBackground`/`CellForeground` references and omits `None` values. It supports color assignments in TOML sections or dotted keys, with quoted hex values and optional inline comments. Alacritty imports and inline tables are not expanded. A valid primary background and foreground are required.

To generate only the palette:

```sh
omacrazy theme infer pink-blood colors
```

If a theme has `colors.toml` but no Ghostty config, generate a starter file with:

```sh
omacrazy theme infer futurism ghostty
```

This creates `themes/futurism/ghostty.conf` from the palette colors. When applying a theme, Omacrazy also infers Ghostty settings automatically if `ghostty.conf` is missing and `colors.toml` is available; it does not refresh an existing file. Re-running the infer command manually regenerates a file marked as infer-generated, while an unmarked file is left unchanged. The palette must contain valid `background` and `foreground` colors.

To create a Zed theme family from the same palette, run:

```sh
omacrazy theme infer futurism zed
```

This creates `themes/futurism/zed.json`, with a dark theme, editor and UI colors, 31 syntax scopes, and terminal ANSI colors. Syntax mappings include documentation comments, emphasis, links, punctuation, special strings, tags, and headings, with italic and bold styles where appropriate. Zed inference runs automatically when applying a theme if it has no Zed theme JSON and has a `colors.toml` palette. Existing Zed themes and unmarked `zed.json` files are preserved. Inferred Zed files carry a marker so running the infer command again regenerates them from the palette.

Zed inference accepts named colors or numbered `color0`–`color15` palettes. Its syntax, diagnostic/Git status colors, window chrome, and editor highlights follow Aetheria's palette-role patterns. Selections and active-line highlights use the same muted palette color, capped at 40% opacity; a lower opacity in that color is preserved. Document highlights use a separate, subtler background. Applying a theme preserves an existing Zed file; rerun `infer <name> zed` to refresh it after palette or generator changes.

To create a JankyBorders theme file, run:

```sh
omacrazy theme infer futurism jankyborders
```

Inference prefers `hyprland.conf`, converting its active border color or gradient. If that file is absent, it randomly chooses the `accent`, `foreground`, or a gradient between them from `colors.toml`. If only one valid color is available, it uses that color. It creates `themes/futurism/jankyborders.conf`. On every theme application, infer-generated JankyBorders files are regenerated from the available source before applying; a hand-authored file is preserved. If the theme has no JankyBorders file or source palette/config, JankyBorders is skipped. Theme application does not parse `hyprland.conf` itself.

Themes are stored in `themes/<name>/`. A target is skipped when its theme-specific file is missing. Each adapter runs independently, so one failure does not prevent the other targets from being attempted.

## Current adapters

### Ghostty

When `ghostty.conf` is present, Omacrazy copies it into Ghostty's macOS config folder and adds a managed `config-file` include to Ghostty's active config (`config` if present, otherwise `config.ghostty`). It backs up the existing config once beside the original with the suffix `.omacrazy-backup`. Ghostty reloads its configuration with **Cmd+Shift+Comma**.

Set `OMACRAZY_GHOSTTY_CONFIG_DIR` to use a different Ghostty config folder.

Omacrazy fixes Ghostty background opacity at **90%**, independently of the selected theme. A managed `omacrazy/overrides.conf` is included after the theme config so it overrides theme opacity settings, such as Lumon's 30%. Switching themes reapplies this override. On macOS, changing background opacity requires fully quitting and reopening Ghostty ([Ghostty configuration reference](https://ghostty.org/docs/config/reference#background-opacity)).

### JankyBorders

When `jankyborders.conf` is present, Omacrazy applies its `active_color` setting. It updates a running JankyBorders process through the `borders` command. It also saves the setting in `~/.config/borders/bordersrc` for future launches, backing up an existing file once as `bordersrc.omacrazy-backup`. The inactive JankyBorders color is left unchanged. Use `omacrazy theme infer <name> jankyborders` to create the theme file from `hyprland.conf` or `colors.toml`.

Set `OMACRAZY_BORDERS_CONFIG` to use a different bordersrc path.

### Zed

When a theme includes JSON under `zed/themes/` (or a root `zed.json`), Omacrazy copies the theme file into `~/.config/zed/themes/` and selects its dark theme name in `~/.config/zed/settings.json`. If no Zed theme JSON exists and `colors.toml` is available, Omacrazy infers a starter `zed.json` before applying. It backs up changed settings once as `settings.json.omacrazy-backup`, and changes only the root `theme` value, preserving other settings and JSONC comments. A replaced local theme file is backed up beside it with the suffix `.omacrazy-backup`.

Zed may need to reload its theme list before a newly installed local theme appears.

### Wallpaper

When a theme has supported images (`jpg`, `jpeg`, `png`, `heic`, or `webp`) in `backgrounds/`, Omacrazy randomly chooses one each time the theme is applied and sets it on every connected display using macOS AppKit. It preserves each display's current scaling options. The selected image is copied to `~/Library/Application Support/Omacrazy/themes/<name>/backgrounds/` so the wallpaper does not depend on the source checkout remaining in place.

## Aetheria

The first imported theme is [JJDizz1L/aetheria](https://github.com/JJDizz1L/aetheria). Its files and MIT license are kept in `themes/aetheria/`. The project copy of its Zed theme is at `themes/aetheria/zed/themes/Aetheria.json`; its background surfaces currently use 95% alpha, though the translucent effect has not yet been confirmed in Zed.

## Requirements

- macOS 14 or later and a Swift toolchain supported by the installed macOS SDK.
- Ghostty and Zed settings can be prepared while those apps are closed. JankyBorders is updated live only when its process is running; otherwise the color is saved for its next launch.
- JankyBorders itself requires macOS 14 or later.

## Tests

Run the test suite with:

```sh
swift test
```
