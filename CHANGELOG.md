# Changelog

## 0.6.0

### Runtime

- [all] Pass key modifiers to the running TUI (#15)
- [all] Update Ghostty (#16)
- [windows] Fix runtime on windows so it launches (#16)

### CLI

- [all] Ensure Ghostty working directory is cwd (#13)
- [all] The `[ghostty]` config now expands arrays into repeated key lines. (#15)
  For example, the following:

  ```toml
  [ghostty]
  keybind = [
      "ctrl+==increase_font_size:1",
      "ctrl+-=decrease_font_size:1",
  ]
  ```

  produces:

  ```
  keybind = ctrl+==increase_font_size:1
  keybind = ctrl+-=decrease_font_size:1
  ```

## 0.5.0

### Runtime

- [all] Allow Ghostty config to override `command` (#5)

### CLI

- [macos] Fix CLI linked to nix store paths (#7)

## 0.4.2

### Runtime

_No changes_

### CLI

- [linux] Statically link CLI binary

## 0.4.1

### Runtime

- [linux] Fix build

### CLI

_No changes_

## 0.4.0

### Runtime

- [linux] Add Wayland support

### CLI

_No changes_

## 0.3.1

### Runtime

- [linux] Dependency fix

### CLI

_No changes_

## 0.3.0

### Runtime

- [linux] Statically link

### CLI

_No changes_

## 0.2.0

### Runtime

- Initial release

### CLI

- Initial release
