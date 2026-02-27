# Map trolley target to Zig target triple
# Linux needs explicit -gnu suffix; without it Zig defaults to musl.
_zig-target target:
    #!/usr/bin/env bash
    case "{{ target }}" in
        x86_64-linux)    echo "x86_64-linux-gnu" ;;
        aarch64-linux)   echo "aarch64-linux-gnu" ;;
        *)               echo "{{ target }}" ;;
    esac

# Map trolley target to Rust CLI target triple.
# Linux uses musl for a fully static, portable binary.
_cli-target target:
    #!/usr/bin/env bash
    case "{{ target }}" in
        x86_64-linux)    echo "x86_64-unknown-linux-musl" ;;
        aarch64-linux)   echo "aarch64-unknown-linux-musl" ;;
        x86_64-macos)    echo "x86_64-apple-darwin" ;;
        aarch64-macos)   echo "aarch64-apple-darwin" ;;
        x86_64-windows)  echo "x86_64-pc-windows-gnu" ;;
        aarch64-windows) echo "aarch64-pc-windows-gnu" ;;
        *)               echo "Unknown target: {{ target }}" >&2; exit 1 ;;
    esac

# Map trolley target to Rust runtime target triple.
# Linux uses glibc because the config staticlib is linked into the Zig
# runtime, which needs glibc for dlopen (X11/Wayland/GL).
_runtime-target target:
    #!/usr/bin/env bash
    case "{{ target }}" in
        x86_64-linux)    echo "x86_64-unknown-linux-gnu" ;;
        aarch64-linux)   echo "aarch64-unknown-linux-gnu" ;;
        x86_64-macos)    echo "x86_64-apple-darwin" ;;
        aarch64-macos)   echo "aarch64-apple-darwin" ;;
        x86_64-windows)  echo "x86_64-pc-windows-gnu" ;;
        aarch64-windows) echo "aarch64-pc-windows-gnu" ;;
        *)               echo "Unknown target: {{ target }}" >&2; exit 1 ;;
    esac

# Build the trolley CLI

# Flags: [--release] [--target <triple>]
build-cli *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo_args=""
    target=""
    release=""
    next_is_target=""
    for flag in {{ flags }}; do
        if [ -n "$next_is_target" ]; then
            target="$flag"
            next_is_target=""
            continue
        fi
        case "$flag" in
            --target)  next_is_target=1 ;;
            --release) release=1 ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done
    if [ -n "$release" ]; then
        cargo_args="$cargo_args --release"
    fi
    if [ -n "$target" ]; then
        rust_target=$(just _cli-target "$target")
        cargo_args="$cargo_args --target $rust_target"
    fi
    cargo build -p trolley --quiet $cargo_args

# Build the config staticlib (manifest parsing, linked into the runtime)

# Flags: [--release] [--target <triple>]
build-config *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo_args=""
    target=""
    release=""
    next_is_target=""
    for flag in {{ flags }}; do
        if [ -n "$next_is_target" ]; then
            target="$flag"
            next_is_target=""
            continue
        fi
        case "$flag" in
            --target)  next_is_target=1 ;;
            --release) release=1 ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done
    if [ -n "$release" ]; then
        cargo_args="$cargo_args --release"
    fi
    if [ -n "$target" ]; then
        rust_target=$(just _runtime-target "$target")
        cargo_args="$cargo_args --target $rust_target"
    fi
    cargo build -p trolley-config --quiet $cargo_args

# Build the trolley runtime
# Flags: [--release] [--target <triple>] [--system <path>]
# No target flag = host default
# Examples:
#   just build-runtime --target x86_64-linux
#   just build-runtime --target aarch64-macos --release
#   just build-runtime --release --system /nix/store/...-zig-packages
build-runtime *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    target=""
    zig_target=""
    optimize=""
    prefix="zig-out-debug"
    cargo_profile="debug"
    release=""
    system=""
    next_is_target=""
    next_is_system=""
    for flag in {{ flags }}; do
        if [ -n "$next_is_target" ]; then
            target="$flag"
            next_is_target=""
            continue
        fi
        if [ -n "$next_is_system" ]; then
            system="$flag"
            next_is_system=""
            continue
        fi
        case "$flag" in
            --target)  next_is_target=1 ;;
            --system)  next_is_system=1 ;;
            --release) release=1; optimize="-Doptimize=ReleaseSafe"; prefix="zig-out-release"; cargo_profile="release" ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done

    # Build config staticlib.
    # Zig uses LLD (GNU-style linking), so on Windows the config crate must
    # be built with the GNU ABI target even when the host default is MSVC.
    config_flags=""
    if [ -n "$release" ]; then config_flags="--release"; fi
    if [ -n "$target" ]; then
        config_flags="$config_flags --target $target"
    elif [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -o 2>/dev/null)" == "Msys" || -n "${WINDIR:-}" ]]; then
        config_flags="$config_flags --target x86_64-windows"
    fi
    just build-config $config_flags

    # Determine config lib path
    if [ -n "$target" ]; then
        rust_target=$(just _runtime-target "$target")
        config_dir="{{ justfile_directory() }}/target/$rust_target/$cargo_profile"
        zig_target="-Dtarget=$(just _zig-target "$target")"
    elif [ -n "${WINDIR:-}" ]; then
        # Host Windows build forced to GNU target above
        config_dir="{{ justfile_directory() }}/target/x86_64-pc-windows-gnu/$cargo_profile"
    else
        config_dir="{{ justfile_directory() }}/target/$cargo_profile"
    fi

    # Detect correct library filename: MSVC produces trolley_config.lib,
    # GNU produces libtrolley_config.a
    if [ -f "$config_dir/libtrolley_config.a" ]; then
        config_lib="$config_dir/libtrolley_config.a"
    elif [ -f "$config_dir/trolley_config.lib" ]; then
        config_lib="$config_dir/trolley_config.lib"
    else
        echo "Error: config lib not found in $config_dir" >&2
        echo "Expected libtrolley_config.a or trolley_config.lib" >&2
        exit 1
    fi

    # Step 1: zig build (libghostty + exe on Linux/Windows, libghostty only on macOS)
    zig_system=""
    if [ -n "$system" ]; then zig_system="--system $system"; fi
    # Build all C deps from source so the binary only needs libc at runtime.
    # (--system enables all integrations by default; explicitly disable them.)
    sys_flags="-fno-sys=freetype -fno-sys=harfbuzz -fno-sys=fontconfig -fno-sys=oniguruma -fno-sys=libpng -fno-sys=zlib"
    cd runtime && zig build $zig_target $optimize $zig_system $sys_flags -Dconfig-lib="$config_lib" --prefix "$prefix"

    # Step 2: macOS needs a separate Swift build for the executable
    is_macos=false
    if [[ "$target" == *"-macos" ]]; then
        is_macos=true
    elif [ -z "$target" ] && [[ "$(uname -s)" == "Darwin" ]]; then
        is_macos=true
        arch=$(uname -m); if [ "$arch" = "arm64" ]; then arch="aarch64"; fi
        rust_target=$(just _runtime-target "$arch-macos")
    fi
    if $is_macos; then
        swift_config="debug"
        if [ -n "$release" ]; then swift_config="release"; fi
        # When no --target was given, cargo outputs to target/$cargo_profile (no triple).
        if [ -n "$target" ]; then
            config_link_dir="../../target/$rust_target/$cargo_profile"
        else
            config_link_dir="../../target/$cargo_profile"
        fi
        cd macos && swift build -c "$swift_config" \
            -Xlinker -L../$prefix/lib \
            -Xlinker -L$config_link_dir
        mkdir -p ../$prefix/bin
        cp ".build/$swift_config/trolley" "../$prefix/bin/trolley"
    fi

# Build everything

# Flags: [--release] [--target <triple>]
build *flags: (build-cli flags) (build-runtime flags)

# Build and package the CLI for release
# Requires: --target <triple>
# Ignores: --system (accepted for compatibility with release command)
release-cli *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    target=""
    next_is_target=""
    skip_next=""
    for flag in {{ flags }}; do
        if [ -n "$skip_next" ]; then
            skip_next=""
            continue
        fi
        if [ -n "$next_is_target" ]; then
            target="$flag"
            next_is_target=""
            continue
        fi
        case "$flag" in
            --target)  next_is_target=1 ;;
            --system)  skip_next=1 ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done
    if [ -z "$target" ]; then
        echo "Error: --target is required" >&2; exit 1
    fi

    TROLLEY_RUNTIME_SOURCE="https://github.com/weedonandscott/trolley/releases/download/v{version}/trolley-runtime-{target}.tar.xz" \
        just build-cli --release --target "$target"

    rust_target=$(just _cli-target "$target")
    exe="trolley"; if [[ "$target" == *-windows ]]; then exe="trolley.exe"; fi
    mkdir -p dist
    tar cJf "dist/trolley-cli-${target}.tar.xz" \
        -C "target/$rust_target/release" "$exe"

# Build and package the runtime for release
# Requires: --target <triple>
# Optional: --system <path> (pre-built zig deps from nix build .#deps)
release-runtime *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    target=""
    system=""
    next_is_target=""
    next_is_system=""
    for flag in {{ flags }}; do
        if [ -n "$next_is_target" ]; then
            target="$flag"
            next_is_target=""
            continue
        fi
        if [ -n "$next_is_system" ]; then
            system="$flag"
            next_is_system=""
            continue
        fi
        case "$flag" in
            --target)  next_is_target=1 ;;
            --system)  next_is_system=1 ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done
    if [ -z "$target" ]; then
        echo "Error: --target is required" >&2; exit 1
    fi

    build_flags="--release --target $target"
    if [ -n "$system" ]; then build_flags="$build_flags --system $system"; fi
    just build-runtime $build_flags

    exe="trolley"; if [[ "$target" == *-windows ]]; then exe="trolley.exe"; fi
    mkdir -p dist
    tar cJf "dist/trolley-runtime-${target}.tar.xz" \
        -C "runtime/zig-out-release/bin" "$exe"

# Build and package everything for release
# Requires: --target <triple>
release *flags: (release-cli flags) (release-runtime flags)

# Sanity-test the release artifacts: init a project, bundle-only package
# Requires: --target <triple>
sanity-test *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    target=""
    next_is_target=""
    for flag in {{ flags }}; do
        if [ -n "$next_is_target" ]; then
            target="$flag"
            next_is_target=""
            continue
        fi
        case "$flag" in
            --target)  next_is_target=1 ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done
    if [ -z "$target" ]; then
        echo "Error: --target is required" >&2; exit 1
    fi

    rust_target=$(just _cli-target "$target")
    exe="trolley"; if [[ "$target" == *-windows ]]; then exe="trolley.exe"; fi
    cli="{{ justfile_directory() }}/target/$rust_target/release/$exe"
    runtime="{{ justfile_directory() }}/runtime/zig-out-release/bin/$exe"

    test_dir="{{ justfile_directory() }}/.sanity-test"
    rm -rf "$test_dir"
    trap 'rm -rf "$test_dir"' EXIT

    echo "==> trolley --version"
    cli_version=$("$cli" --version)
    expected="trolley version $(cat VERSION | tr -d '[:space:]')"
    if [ "$cli_version" != "$expected" ]; then
        echo "Error: --version output '$cli_version' does not match expected '$expected'" >&2; exit 1
    fi

    echo "==> trolley init .sanity-test/project"
    "$cli" init "$test_dir/project"

    if [ ! -f "$test_dir/project/trolley.toml" ]; then
        echo "Error: trolley.toml was not created" >&2; exit 1
    fi

    mkdir -p "$test_dir/project/path/to"
    cp "$cli" "$test_dir/project/path/to/project"

    echo "==> trolley package --bundle-only"
    TROLLEY_RUNTIME_SOURCE="$runtime" \
        "$cli" package --bundle-only --config "$test_dir/project/trolley.toml"

    echo "==> Sanity test passed"

# Use like the real CLI: just trolley <args>

# Rebuilds automatically via cargo run
trolley *args:
    cargo run -p trolley --quiet -- {{ args }}

# Run an example by name: just example hello [--release]
example name *flags: (build-runtime flags)
    #!/usr/bin/env bash
    set -euo pipefail
    prefix="zig-out-debug"
    for flag in {{ flags }}; do
        if [ "$flag" = "--release" ]; then prefix="zig-out-release"; fi
    done
    exe_suffix=""; if [ -n "${WINDIR:-}" ]; then exe_suffix=".exe"; fi
    TROLLEY_RUNTIME_SOURCE='{{ justfile_directory() }}/runtime/'$prefix'/bin/trolley'$exe_suffix \
        cargo run -p trolley --quiet -- run --config 'examples/{{ name }}/trolley.toml'

# Bump version in all files: just bump 0.2.0
bump version:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "{{ version }}" > VERSION
    sed -i 's/^version = ".*"/version = "{{ version }}"/' cli/Cargo.toml config/Cargo.toml
    sed -i 's/\.version = ".*"/.version = "{{ version }}"/' runtime/build.zig.zon
    cargo update --workspace --quiet

# Clean font cache
clean-fonts:
    rm -rf trolley/cache/fonts

# Pre-fetch Zig dependencies for offline/cached builds.
# Copies ghostty's dep file out of the submodule (nix flakes can't see
# inside submodules), then builds the combined dep store via nix.
# Outputs the store path on stdout.
build-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    cp ghostty/build.zig.zon.nix nix/ghostty-deps.nix
    git add -f nix/ghostty-deps.nix nix/extra-zig-deps.nix
    nix build -L -v .#deps
    readlink ./result

# Clean all build artifacts
clean:
    cargo clean
    cd runtime && rm -rf zig-out-debug zig-out-release .zig-cache
    cd runtime/macos && rm -rf .build
    rm -rf trolley/build trolley/cache dist
