use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use trolley_config::{Format, Target};

use super::common;
use common::ProjectContext;

/// Assemble a bundle directory and optionally build packages.
///
/// Returns the bundle directory path (for `trolley run` to exec from).
pub fn run(
    ctx: &ProjectContext,
    target: Target,
    tui_binary: &Path,
    runtime: &Path,
    bundle_only: bool,
    formats: Option<Vec<Format>>,
    skip_failed_formats: bool,
) -> Result<PathBuf> {
    let formats = match formats {
        Some(formats) => formats,
        None => {
            if target.is_linux() {
                Format::LINUX_DEFAULT.to_vec()
            } else if target.is_macos() {
                Format::macos_default(cfg!(target_os = "macos"))
            } else if target.is_windows() {
                Format::WINDOWS_DEFAULT.to_vec()
            } else {
                vec![]
            }
        }
    };

    // Validate: each format must be valid for the target
    let invalid: Vec<_> = formats.iter().filter(|f| !f.valid_for(&target)).collect();
    if !invalid.is_empty() {
        bail!(
            "formats {} are not valid for target {}",
            invalid
                .iter()
                .map(|f| f.as_str())
                .collect::<Vec<_>>()
                .join(", "),
            target
        );
    }

    let mut manifest = common::BundleManifest::new(&ctx.config, &target);

    let base_output_dir = common::build_output_dir(&ctx.output_dir, &ctx.config, &target);

    let bundle_dir = base_output_dir.join("bundle");
    let dist_dir = base_output_dir.join("dist");

    // Clean and recreate the output directory
    if base_output_dir.exists() {
        fs::remove_dir_all(&base_output_dir)
            .with_context(|| format!("cleaning output directory {}", base_output_dir.display()))?;
    }
    fs::create_dir_all(&bundle_dir)
        .with_context(|| format!("creating bundle directory {}", bundle_dir.display()))?;
    fs::create_dir_all(&dist_dir)
        .with_context(|| format!("creating dist directory {}", dist_dir.display()))?;

    // Resolve and copy fonts
    let font_files = common::resolve_fonts(&ctx.project_dir, &ctx.output_dir, &ctx.config)?;
    common::copy_fonts_to_bundle(&font_files, &bundle_dir)?;

    if !font_files.is_empty() {
        for font in &font_files {
            if let Some(name) = font.file_name() {
                manifest.resources.push(PathBuf::from("fonts").join(name));
            }
        }
        manifest
            .resources
            .push(PathBuf::from(common::FONTS_CONFIG_FILENAME));
    }

    // Read font family names for config assembly
    let font_family_names = common::read_font_family_names(&font_files)?;

    // Assemble ghostty.conf — command references the renamed TUI binary
    let config_bytes = common::assemble_config(
        &ctx.project_dir,
        &ctx.config,
        &manifest.core_name,
        &font_family_names,
    )?;

    // Copy runtime and TUI binary into bundle with renamed filenames
    fs::copy(&runtime, bundle_dir.join(&manifest.runtime_name))
        .with_context(|| format!("copying runtime to {}", bundle_dir.display()))?;
    fs::copy(&tui_binary, bundle_dir.join(&manifest.core_name))
        .with_context(|| format!("copying TUI binary to {}", bundle_dir.display()))?;
    fs::write(
        bundle_dir.join(common::GHOSTTY_CONFIG_FILENAME),
        &config_bytes,
    )
    .with_context(|| format!("writing config to {}", bundle_dir.display()))?;

    let env_bytes = common::assemble_environment(&ctx.project_dir, &ctx.config)?;
    fs::write(bundle_dir.join(common::ENVIRONMENT_FILENAME), &env_bytes)
        .with_context(|| format!("writing environment to {}", bundle_dir.display()))?;

    // Copy manifest into bundle (runtime needs it for [gui] config)
    fs::copy(&ctx.config_path, bundle_dir.join(common::CONFIG_FILENAME))
        .with_context(|| format!("copying manifest to {}", bundle_dir.display()))?;

    // Generate wrapper script for Linux
    if let common::BundleVariant::Linux {
        ref wrapper_name,
        ref install_prefix,
    } = manifest.variant
    {
        let wrapper_content = format!(
            "#!/usr/bin/env sh\nexec {install_prefix}/{} \"$@\"\n",
            manifest.runtime_name
        );
        let wrapper_path = bundle_dir.join(wrapper_name);
        fs::write(&wrapper_path, &wrapper_content)
            .with_context(|| format!("writing wrapper script to {}", wrapper_path.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&wrapper_path, fs::Permissions::from_mode(0o755))?;
        }
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::Permissions::from_mode(0o755);
        fs::set_permissions(bundle_dir.join(&manifest.runtime_name), mode.clone())?;
        fs::set_permissions(bundle_dir.join(&manifest.core_name), mode)?;
    }

    println!("Bundle written to {}", bundle_dir.display());
    println!("  {}  (runtime)", manifest.runtime_name);
    println!("  {}  (TUI binary)", manifest.core_name);
    println!("  ghostty.conf  (terminal config)");
    println!("  environment  (environment variables)");
    println!("  trolley.toml  (manifest)");
    if let common::BundleVariant::Linux {
        ref wrapper_name, ..
    } = manifest.variant
    {
        println!("  {wrapper_name}  (wrapper script)");
    }
    if !font_files.is_empty() {
        println!("  fonts/  ({} font files)", font_files.len());
    }

    // Build packages unless bundle-only
    if !bundle_only && !formats.is_empty() {
        println!();
        super::formats::build_formats(&formats, &bundle_dir, &dist_dir, &ctx.config, &manifest, skip_failed_formats)?;
    }

    Ok(bundle_dir)
}
