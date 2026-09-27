# Workspace Watermark

An Omarchy shell plugin for people who keep one project per workspace. Each
workspace gets its own hue, drawn as a thin frame around the screen, and a
faint watermark in a corner names the project you work on there. When you
switch workspaces the name flashes at full strength for about a second, then
settles back to a watermark.

Project names are picked up automatically from VS Code window titles
(`file - project - Visual Studio Code`), and VSCodium and Cursor work the same
way. You can also name any workspace yourself.

The overlay stays visible over fullscreen windows and never takes clicks or
keyboard focus.

## Install

```bash
omarchy plugin add https://github.com/stefanoconiglio/omarchy-workspace-watermark.git --enable
```

Requires Omarchy Quattro (the Quickshell-based `omarchy-shell`).

### Toggle keybinding

The plugin doesn't add keybindings of its own. To hide and show the watermark
with a key, add this line to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + W", "Toggle workspace watermark", "omarchy-shell workspace-watermark toggle")
```

`SUPER + ALT + W` is unbound in a stock Omarchy setup. Run
`omarchy menu keybindings --print` to check your own.

## Screen sharing

The frame and watermark show up in screenshots, screen recordings and screen
shares. Hyprland's `no_screen_share` layer rule doesn't help here: on Hyprland
0.56 it replaces the whole full-screen layer with black, so the entire capture
comes out blank. Hide the watermark with the toggle before you share your
screen.

## Settings

Settings live on the plugin's own entry in `~/.config/omarchy/shell.json`,
under `plugins`, and apply as soon as you save. Every key is optional:

```json
{
  "id": "io.github.stefanoconiglio.workspace-watermark",
  "position": "bottom-right",
  "labels": { "1": "Web", "3": "Thesis", "10": "Chat" },
  "colors": { "3": "#e5a50a" }
}
```

| Key                 | Default          | Meaning |
|---------------------|------------------|---------|
| `labels`            | `{}`             | Name per workspace id. A name here always wins over auto-detection. |
| `colors`            | `{}`             | Hex color per workspace id. Others get a distinct hue automatically. |
| `position`          | `"bottom-right"` | Watermark corner: `top-left`, `top-right`, `bottom-left` or `bottom-right`. |
| `frameWidth`        | `3`              | Frame thickness in pixels. `0` turns the frame off. |
| `frameOpacity`      | `0.6`            | Frame strength, from `0` to `1`. |
| `labelOpacity`      | `0.14`           | Watermark strength between switches, from `0` to `1`. |
| `flashOnSwitch`     | `true`           | Show the name at full strength for a moment after switching. |
| `autoDetectProject` | `true`           | Read project names from editor window titles. |
| `visible`           | `true`           | Whether the overlay is shown. The toggle updates this for you. |

A workspace's name comes from the first of these that applies:

1. Its entry in `labels`.
2. Its Hyprland name, if you named the workspace.
3. The project most of its editor windows have open. Runs of two or more
   dashes or underscores become a space, so `my----project` reads
   `my project`.
4. Just the workspace number.

The toggle saves `visible` to this entry, keeping every other setting as it
is. The plugin writes nothing else.

`omarchy plugin disable` removes the entry from `shell.json`, so your labels
and colors go with it. Copy them somewhere first if you plan to come back.

## Commands

```bash
omarchy-shell workspace-watermark toggle
omarchy-shell workspace-watermark show
omarchy-shell workspace-watermark hide
omarchy-shell workspace-watermark state
```

## Remove

```bash
omarchy plugin remove io.github.stefanoconiglio.workspace-watermark
```

If you added the toggle keybinding, remove its line from
`~/.config/hypr/bindings.lua` too.

## How it works

The plugin is a single QML service. It opens one transparent layer-shell
surface per screen on the overlay layer, namespace `workspace-watermark`, with
an empty input region. It follows each monitor's active workspace through
Quickshell's Hyprland integration and reads its settings from `shell.json`.
It starts no processes, makes no network requests and has no dependencies
beyond Omarchy itself.

## License

MIT. See [LICENSE](LICENSE).
