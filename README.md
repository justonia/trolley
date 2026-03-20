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

[shader]
path = "shaders/crt.glsl"

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
```

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
```

### `[shader]` -- optional

Bundle a single custom shader file and wire it into Ghostty as a
`custom-shader` entry. The path must be a clean relative path from the
directory containing `trolley.toml`; Trolley copies the shader into the bundle
at the same relative path so `trolley run` and packaged apps behave the same.

```toml
[shader]
path = "shaders/crt.glsl"
```

### `[ghostty]` -- optional

Pass-through configuration for the Ghostty terminal engine. Accepts any
Ghostty config key with a scalar value (string, integer, float, or boolean)
or an array of scalars. Arrays are expanded into repeated key lines, which is
how Ghostty handles multi-value options like `keybind`.
Note that configs meant for Ghostty's GUI will not take effect (obviously).
If you want to bundle a shader with your app, prefer `[shader]` over setting
`custom-shader` here.

```toml
[ghostty]
font-size = 14
theme = "dracula"
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
