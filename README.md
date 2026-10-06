# Workspace Watermark

An Omarchy shell plugin that tells you where you are when you switch
workspaces. Each workspace gets its own hue. On every switch, big letters in
that hue show the workspace's number, the name of what you work on there, and
every window open on it, oldest first, all in one big font that grows to fill
the screen. After a couple of seconds it fades away completely.

```
                           3 · my-thesis
                        herdr  my-thesis
              Brave  Hyprland - ArchWiki
                                 Spotify
```

If you'd rather keep it, it can instead settle into a faint watermark, and a
thin frame in the workspace's hue can go around the screen (both off by
default; see Settings).

Names are picked up automatically from what's open on the workspace: the
VS Code project, else the folder a Claude Code session runs in, else a
terminal's folder, else a web app such as WhatsApp or Gmail, else the app
itself. You can also name any workspace yourself.

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

The frame, the name and the window list show up in screenshots, screen
recordings and screen shares, and the list shows window titles. Hyprland's `no_screen_share` layer rule doesn't help here: on Hyprland
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
| `windowList`        | `true`           | List the workspace's windows under its name. |
| `fontSize`          | `60`             | Largest letter size in pixels. With many windows the letters shrink so that every line fits the screen. |
| `backdropOpacity`   | `0`              | Dim the screen behind the letters while they show, from `0` (not at all) to `1`. |
| `fadeAway`          | `true`           | After a switch, fade away completely. `false` settles into a faint watermark instead. |
| `labelOpacity`      | `0.14`           | Watermark strength between switches when `fadeAway` is `false`, from `0` to `1`. |
| `flashOnSwitch`     | `true`           | Show the name and list at full strength after switching. With `fadeAway` on, `false` means nothing shows until `flash`. |
| `flashDuration`     | `2500`           | Milliseconds from the switch until faded; the last 800 are the fade. |
| `frame`             | `false`          | Draw a frame in the workspace's hue around the screen. |
| `frameWidth`        | `3`              | Frame thickness in pixels, when `frame` is on. |
| `frameOpacity`      | `0.6`            | Frame strength, from `0` to `1`. |
| `autoDetectProject` | `true`           | Name workspaces from their windows, as described below. `false` shows only `labels` and numbers. |
| `visible`           | `true`           | Whether the overlay is shown. The toggle updates this for you. |

### The window list

One line per window on the workspace, in the same big font as the name: the
app, then what the window shows, cut short with "…" where the screen ends.

- A terminal shows the program its shell runs (`herdr`, `nvim`, `btop`,
  `claude`), or `terminal` at a bare prompt. Next to it is the window's
  title without the `user@host:` prefix, or for Claude Code its folder.
- A web app shows its name and page title, such as `YouTube  Ten Percent`.
- Any other app shows its name and title, without the app's own suffix
  (`Brave  John Searle obituary…`, not `… - Brave`). VS Code shows its project.

Windows are ordered by process ID, oldest first, which tells you roughly
when each was opened. Windows of one process share an ID (every Brave and
web-app window is one Brave process), so they appear together, in the order
Hyprland lists them.

### The name

A workspace's name comes from the first of these that applies:

1. Its entry in `labels`.
2. Its Hyprland name, if you named the workspace.
3. The project open in VS Code, read from its window title
   (`file - project - Visual Studio Code`). VSCodium and Cursor work too.
4. The folder a Claude Code session runs in, for Claude Code in a terminal.
5. The folder a terminal's shell is in. Your home folder shows as `~`.
6. The name of a web app, taken from its launcher in
   `~/.local/share/applications`, such as WhatsApp, Google Gmail or ChatGPT.
7. The name of any other app, such as Brave or Spotify.
8. Just the workspace number.

When several windows on a workspace offer a name at the same level, the most
common one wins. A workspace with two ChatGPT windows and one WhatsApp window
shows ChatGPT; set a label if you'd rather it said something else. In folder
and project names, runs of two or more dashes or underscores become a space,
so `my----project` reads `my project`.

Terminal folders are found by looking at the processes under each terminal
window. That works for terminals that run one process per window, such as
`foot`, Alacritty, kitty and Ghostty or WezTerm when started one window per
process. A Claude Code session inside tmux isn't found, and neither is one
started in a terminal that runs every window from a single process; the
terminal's own folder is shown instead.

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
omarchy-shell workspace-watermark flash     # show the name and list again now
omarchy-shell workspace-watermark names     # the name each workspace would show
omarchy-shell workspace-watermark windows   # each workspace's window list
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

Every three seconds, while the watermark is shown and a terminal window is
open, it runs `terminal-cwds.sh` with the terminal windows' process IDs. The
script reads the process table with `ps` and each shell's and Claude Code
session's working directory from `/proc`, and prints them with the name of
the program each terminal's shell runs (its newest child process). It changes
nothing. The plugin makes no network requests and has no dependencies beyond
Omarchy itself.

After editing the plugin's QML, run `omarchy restart shell` to load the new
code; saving alone can leave the previous version running.

## License

MIT. See [LICENSE](LICENSE).
