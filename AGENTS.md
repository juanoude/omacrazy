# Omacrazy

## Project goal
Build a personal macOS theme picker that applies a selected theme across the apps and system settings I use, from one input. Keep the project focused on reliable personal workflows rather than broad support for every macOS app.

## Product direction
- Support a fast command-line theme switch first; a menu bar picker can be added later if useful.
- Represent each theme as a readable, editable manifest with per-app settings and asset paths.
- Make app support modular: each app or system setting should have a small adapter that applies its theme.
- Start with a small set of high-priority targets, such as wallpaper, macOS appearance, Terminal, and VS Code; add more only as needed.
- Clearly report which settings were applied, skipped, or failed. Do not silently claim a full switch when an app cannot be themed automatically.

## Implementation guidance
- Prefer native macOS mechanisms and documented app configuration formats where available.
- Keep user data and app preferences safe. Back up or preserve existing values before changing them when practical, and avoid destructive resets.
- Make theme application repeatable and safe to run more than once.
- Keep configuration and theme assets in a predictable, documented location. Do not commit personal credentials, tokens, or unrelated private configuration.
- Keep dependencies lightweight and explain any required setup.
- Match the existing language, structure, and conventions of the repository. If starting from an empty folder, choose a simple structure and document how to run the tool.

## Verification
- When changing code, verify the affected behavior with focused checks where practical.
- For app adapters, test both successful application and missing/unsupported configuration paths without altering unrelated user settings.
- Document macOS version assumptions and any app restart or manual step required for a theme to take effect.
