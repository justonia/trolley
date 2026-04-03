> NOTE: This software is _pre-alpha_. Functionality and design expected to be broken.

# Trolley

**Run terminal apps anywhere.**

Trolley lets you bundle any TUI executable together with a terminal emulator
runtime, allowing you to distribute TUI applications to non-technical users.

Trolley targets Linux and MacOS, and Windows.

Other targets like iOS and Android are possible. Please open an issue if 
interested.

Although mostly simple, two recent developments make it quite powerful:

1. Improvements in terminal functionality and performance 
2. Flourishing of easy to use, powerful TUI libraries

If you are building software that fits the textual interface style, you'll be able
to create performant, _cross-platform_ applications. Launching in under a second is typical.
Combined with TUI frameworks like OpenTUI, Bubbletea & Ratatui, it is extremely easy 
to create apps with a developer experience not much different than a webapp's.

## Giants and their shoulders

Trolley is built on top of [Ghostty](https://github.com/ghostty-org/ghostty/),
which powers most of everything the end user will see and do, and enables the
aforementioned functionality. Even the GUI wrappers are stripped down versions
of Ghostty's.

For packaging, [cargo-packager](https://github.com/crabnebula-dev/cargo-packager)
does most of the heavy lifting.

Trolley, then, is an ergonomic wrapper around those two.

## Install

**macOS / Linux (Homebrew):**

```
brew install weedonandscott/tap/trolley
```

**Linux (manual):**

```
curl -sL https://github.com/weedonandscott/trolley/releases/latest/download/trolley-cli-x86_64-linux.tar.xz | tar xJ
mv trolley ~/.local/bin/
```

**Nix flake (builds from source):**

```nix
{
  inputs.trolley.url = "github:weedonandscott/trolley";
}
```

Then add `inputs.trolley.packages.${system}.default` to your packages.

Binaries for all platforms are available on [GitHub Releases](https://github.com/weedonandscott/trolley/releases).

## Quickstart

```
trolley init my-app
```

This scaffolds a `trolley.toml` manifest. Point it at your TUI binary:

```toml
[app]
identifier = "com.example.my-app"
display_name = "My App"
slug = "my-app"
version = "0.1.0"
icons = ["assets/icon.png"]

[linux]
binaries = { x86_64 = "target/release/my-app" }

[gui]
initial_width = 800
initial_height = 600

[fonts]
families = [{ nerdfont = "JetBrainsMono" }]

[embeds]
theme = "themes/dracula"
shaders = ["shaders/crt.glsl", "shaders/bloom.glsl"]
data = ["assets", "config/defaults.json"]

[ghostty]
font-size = 14
```

Then run to see how it works:

```
trolley run
```

Or package to send to your end users:

```
trolley package
```

## How it works

Trolley bundles your TUI, assets, and config next to a terminal emulator runtime. It
instructs it to launch your executable.

Trolley's runtime is a thin native wrapper around
[libghostty](https://github.com/ghostty-org/ghostty), the core library of
the Ghostty terminal emulator. libghostty handles VT parsing, PTY management,
GPU rendering, font shaping, and input encoding. Trolley provides the native
window and kiosk behavior.

| Platform | Runtime language | Windowing | Renderer |
|----------|------------------|-----------|----------|
| macOS    | Swift (AppKit)   | NSWindow  | Metal    |
| Linux    | Zig (GLFW)       | GLFW      | OpenGL   |
| Windows  | Zig (Win32)      | Win32     | OpenGL   |

### Development Prerequisites

- [Nix](https://nixos.org/) with flakes enabled (provides all build tools), or:
- Rust toolchain, Zig compiler, and platform dependencies (GLFW, X11 libs on Linux)

## Manifest

The manifest file `trolley.toml` has the following sections:

### `[app]` -- required

| Field          | Description                                |
|----------------|--------------------------------------------|
| `identifier`   | Reverse-DNS identifier (e.g. `com.foo.bar`)|
| `display_name` | Human-readable application name            |
| `slug`         | Filesystem-safe name (lowercase, hyphens)  |
| `version`      | Version string                             |
| `icons`        | List of icon paths/globs ([see Icons](#icons)) |

### `[linux]`, `[macos]`, `[windows]` -- at least one required

```toml
[linux]
binaries = { x86_64 = "path/to/binary", aarch64 = "path/to/binary" }
args = ["--verbose", "--port=9000"]
screenshot_path = "/tmp/my-app-screenshot.png"
```

`binaries` maps architectures to executable paths.

`args` is optional and platform-specific. Trolley appends these entries to the
default bundled command it generates for your app.

This comes with an important caveat: arguments must not contain whitespace or
control characters. The culprit is Ghostty's current `direct:` command parser,
which splits arguments on spaces instead of accepting a structured argv array.
That means values such as `"Jane Doe"` or `"--message=hello world"` cannot be
represented safely through Trolley's default command path today.

If you need full shell quoting or arguments containing spaces, you must fall
back to `[ghostty].command` and accept shell semantics. `args` cannot be used
together with `[ghostty].command`.

On Windows, 1ms timer resolution is enabled by default instead of the usual
~15.6ms. This reduces timer jitter and can improve animation smoothness, but
might slightly increase CPU usage. Set `precise_timer = false` to opt out.

```toml
[windows]
binaries = { x86_64 = "path/to/app.exe" }
precise_timer = false
```

`screenshot_path` and `text_dump_path` (optional) specify default output paths
for screenshots and text dumps. These are used as fallbacks when the command file
(see below) doesn't specify an explicit path.

`command_file` (optional) enables the command file interface for programmatic
control of the running application. See [Command File](#command-file) below.
The environment variable `TROLLEY_COMMAND_FILE` overrides the config value on
all platforms.

### `[gui]` -- optional

`initial_width`, `initial_height`, `resizable`, `min_width`, `min_height`,
`max_width`, `max_height`.

### `[fonts]` -- optional

```toml
[fonts]
families = [
    { nerdfont = "Inconsolata" },      # auto-downloaded from Nerd Fonts
    { path = "fonts/Custom.ttf" },     # local font file
]
```

### `[environment]` -- optional

```toml
[environment]
env_file = ".env"
variables = { MY_VAR = "value" }
inject_pid_variable = "TROLLEY_PID"
pid_file = "/tmp/my-app.pid"
```

`inject_pid_variable` makes the runtime's PID available to the TUI process
under the given environment variable name. `pid_file` writes the PID to
the given path on startup and deletes it on exit. Both are useful for
signaling the runtime from the TUI or external tools (e.g. triggering
command file processing via `kill -USR1`). The environment variable
`TROLLEY_PID_FILE` overrides `pid_file`.

### `[embeds]` -- optional

Embed portable Ghostty resources into the generated bundle. Relative paths are
resolved from the directory containing `trolley.toml`.

```toml
[embeds]
theme = "themes/dracula"
shaders = ["shaders/crt.glsl", "shaders/bloom.glsl"]
data = ["assets", "config/defaults.json"]
```

`theme` inlines a local Ghostty theme file into the generated `ghostty.conf`.
This is the portable way to ship a theme with your app, because it does not
depend on Ghostty's external theme catalog being installed on the target
machine.

`shaders` bundles one or more custom shader files and wires them into Ghostty
as repeated `custom-shader` entries. Each shader path must be a clean relative
path; Trolley copies every shader into the bundle at the same relative path so
`trolley run` and packaged apps behave the same.

`data` copies files or directories into the bundle root at the same
relative paths. This is useful for application assets or default data files
that your TUI loads relative to the runtime working directory.

### `[ghostty]` -- optional

Pass-through configuration for the Ghostty terminal engine. Accepts any
Ghostty config key with a scalar value (string, integer, float, or boolean)
or an array of scalars. Arrays are expanded into repeated key lines, which is
how Ghostty handles multi-value options like `keybind`.
Note that configs meant for Ghostty's GUI will not take effect (obviously).
If you want to ship a theme file with your app, prefer `[embeds].theme` over setting
`theme = "..."` here.
If you want to bundle shaders with your app, prefer `[embeds].shaders` over setting
`custom-shader` here.
If you set `command` here, do not also set per-platform `args`; Trolley treats
`[ghostty].command` as an explicit override.

```toml
[ghostty]
font-size = 14
keybind = [
    "ctrl+==increase_font_size:1",
    "ctrl+-=decrease_font_size:1",
]
```

### Ghostty Logging

To see Ghostty log output when using `trolley run`, add this to your `variables`: 
```toml
variables = { 
  GHOSTTY_LOG = "stderr" 
}
```

### Window title

You can set a fixed window title for your application via the Ghostty `title`
config:

```toml
[ghostty]
title = "My App"
```

This sets the native window title on all platforms. When set, it overrides any
title escape sequences sent by your TUI program. If your TUI doesn't set a title
itself, the window would otherwise show a default — so it's generally a good idea
to set one.

> **Tip:** Trolley clears all default Ghostty keybindings so they don't
> interfere with your TUI. If you want to re-add some of them (e.g. zoom),
> use the `keybind` array:
>
> ```toml
> [ghostty]
> keybind = [
>     "ctrl+==increase_font_size:1",
>     "ctrl+plus=increase_font_size:1",
>     "ctrl+-=decrease_font_size:1",
>     "ctrl+0=reset_font_size",
>     "super+==increase_font_size:1",
>     "super+plus=increase_font_size:1",
>     "super+-=decrease_font_size:1",
>     "super+0=reset_font_size",
> ]
> ```
>
> See [Ghostty's keybind docs](https://ghostty.org/docs/config/keybind) for
> the full list of available actions.

## Command File

The command file interface allows external tools (scripts, AI agents, test
harnesses) to programmatically send input to the wrapped TUI application.

### Setup

Set the command file path via config or environment variable:

```toml
[linux]
command_file = "/tmp/my-app-commands.jsonl"
```

Or at runtime:

```bash
export TROLLEY_COMMAND_FILE=/tmp/my-app-commands.jsonl
```

You'll also want `inject_pid_variable` or `pid_file` so the external tool knows
which process to signal:

```toml
[environment]
pid_file = "/tmp/my-app.pid"
```

### Usage

1. Write one or more JSON commands to the command file (one per line).
2. Signal the trolley process to read it:
   - **Linux/macOS:** `kill -USR1 <pid>`
   - **Windows:** Signal the named event `Local\trolley-command-<pid>`

The file is deleted after reading, so write a fresh file before each signal.

### Command types

| Type | Description | Example |
|------|-------------|---------|
| `text` | Send text to the TUI's stdin | `{"type":"text", "data":"hello\r"}` |
| `key` | Send a named key (mapped to escape sequence) | `{"type":"key", "data":"arrow_down"}` |
| `wait` | Pause before the next command (seconds) | `{"type":"wait", "data":"1.5"}` |
| `screenshot` | Capture the terminal as PNG | `{"type":"screenshot", "data":"/tmp/shot.png"}` |
| `text_dump` | Dump terminal text content to file | `{"type":"text_dump", "data":"/tmp/dump.txt", "format":"vt"}` |

For `screenshot` and `text_dump`, omitting `data` falls back to the
`screenshot_path` / `text_dump_path` config values. The `format` field for
`text_dump` accepts `plain` (default), `vt`, or `html`.

### Available key names

**Navigation:** `enter`, `tab`, `escape`, `backspace`, `space`

**Arrows:** `arrow_up` / `up`, `arrow_down` / `down`, `arrow_left` / `left`, `arrow_right` / `right`

**Control pad:** `home`, `end`, `page_up`, `page_down`, `insert`, `delete`

**Function keys:** `f1` through `f12`

**Ctrl combinations:** `ctrl+a` through `ctrl+z`

### Example: automated interaction

```json
{"type":"text", "data":"search query\r"}
{"type":"wait", "data":"2"}
{"type":"key", "data":"arrow_down"}
{"type":"key", "data":"arrow_down"}
{"type":"key", "data":"enter"}
{"type":"wait", "data":"1"}
{"type":"screenshot", "data":"/tmp/result.png"}
```

> **Note:** Key names map to standard VT/xterm escape sequences (normal cursor
> mode). If your TUI enables application cursor mode, arrow keys may not behave
> as expected. Use `text` with raw escape sequences for full control.

## Icons

Icons are not needed for `trolley run` or `--bundle-only`, but most package
formats require them. Provide icon paths or globs in the `[app]` section:

```toml
[app]
icons = ["assets/icon.png"]
```

Different formats need different icon types:

| Format              | Icon type     | Required |
|---------------------|---------------|----------|
| AppImage            | Square `.png` | Yes      |
| .deb, .rpm, pacman  | `.png`        | No       |
| NSIS (Windows)      | `.ico`        | No       |
| .app, .dmg (macOS)  | `.icns`       | No       |
| .tar.gz             | --            | --       |

To support all platforms, provide multiple icons:

```toml
icons = ["assets/icon.png", "assets/icon.ico", "assets/icon.icns"]
```

On Windows, the first resolved `.ico` is bundled into the runtime for the app
window icon, and when packaging on Windows it is also embedded into the bundled
`*_runtime.exe`.

Glob patterns are also supported (e.g. `"assets/icon.*"`).

## Package formats

| Platform | Default formats                       |
|----------|---------------------------------------|
| Linux    | AppImage, .deb, .rpm, pacman, .tar.gz |
| macOS    | .app, .dmg, .tar.gz                   |
| Windows  | NSIS installer                        |

Select specific formats with `--formats`:

```
trolley package --formats appimage,deb
```

Use `--skip-failed-formats` to continue building remaining formats if one fails
(e.g. when icons are missing for some formats):

```
trolley package --skip-failed-formats
```

## BUNDLING != SANDBOXING

Trolley simply runs your executable inside a terminal, and in that sense, provides no
extra security or sandbox guarantees.

## License

MIT
