# Map trolley target to Rust target triple
_rust-target target:
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
        rust_target=$(just _rust-target "$target")
        cargo_args="$cargo_args --target $rust_target"
    fi
    cd cli && cargo build --quiet $cargo_args

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
        rust_target=$(just _rust-target "$target")
        cargo_args="$cargo_args --target $rust_target"
    fi
    cd config && cargo build --quiet $cargo_args

# Build the trolley runtime
# Flags: [--release] [--target <triple>]
# No target flag = host default
# Examples:
#   just build-runtime --target x86_64-linux

# just build-runtime --target aarch64-macos --release
build-runtime *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    target=""
    zig_target=""
    optimize=""
    prefix="zig-out-debug"
    cargo_profile="debug"
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
            --release) release=1; optimize="-Doptimize=ReleaseSafe"; prefix="zig-out-release"; cargo_profile="release" ;;
            *)         echo "Unknown flag: $flag" >&2; exit 1 ;;
        esac
    done

    # Build config staticlib
    config_flags=""
    if [ -n "$release" ]; then config_flags="--release"; fi
    if [ -n "$target" ]; then config_flags="$config_flags --target $target"; fi
    just build-config $config_flags

    # Determine config lib path
    if [ -n "$target" ]; then
        rust_target=$(just _rust-target "$target")
        config_lib="{{ justfile_directory() }}/config/target/$rust_target/$cargo_profile/libtrolley_config.a"
        zig_target="-Dtarget=$target"
    else
        config_lib="{{ justfile_directory() }}/config/target/$cargo_profile/libtrolley_config.a"
    fi

    # Step 1: zig build (libghostty + exe on Linux/Windows, libghostty only on macOS)
    cd runtime && zig build $zig_target $optimize -Dconfig-lib="$config_lib" --prefix "$prefix"

    # Step 2: macOS needs a separate Swift build for the executable
    is_macos=false
    if [[ "$target" == *"-macos" ]]; then
        is_macos=true
    elif [ -z "$target" ] && [[ "$(uname -s)" == "Darwin" ]]; then
        is_macos=true
        arch=$(uname -m); if [ "$arch" = "arm64" ]; then arch="aarch64"; fi
        rust_target=$(just _rust-target "$arch-macos")
    fi
    if $is_macos; then
        swift_config="debug"
        if [ -n "$release" ]; then swift_config="release"; fi
        # When no --target was given, cargo outputs to target/$cargo_profile (no triple).
        if [ -n "$target" ]; then
            config_link_dir="../../config/target/$rust_target/$cargo_profile"
        else
            config_link_dir="../../config/target/$cargo_profile"
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

# Use like the real CLI: just trolley <args>

# Rebuilds automatically via cargo run
trolley *args:
    cargo run --quiet --manifest-path cli/Cargo.toml -- {{ args }}

# Run an example by name: just example hello [--release]
example name *flags: (build-runtime flags)
    #!/usr/bin/env bash
    set -euo pipefail
    prefix="zig-out-debug"
    for flag in {{ flags }}; do
        if [ "$flag" = "--release" ]; then prefix="zig-out-release"; fi
    done
    TROLLEY_RUNTIME_SOURCE={{ justfile_directory() }}/runtime/$prefix/bin/trolley \
        cargo run --quiet --manifest-path cli/Cargo.toml -- run --config examples/{{ name }}/trolley.toml

# Clean font cache
clean-fonts:
    rm -rf trolley/cache/fonts

# Clean all build artifacts
clean:
    cd config && cargo clean
    cd cli && cargo clean
    cd runtime && rm -rf zig-out-debug zig-out-release .zig-cache
    cd runtime/macos && rm -rf .build
    rm -rf trolley/build trolley/cache
