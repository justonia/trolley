use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result};
use trolley_config::Target;

use super::{common, package};
use common::ProjectContext;

pub fn run(ctx: ProjectContext, tui_binary: PathBuf, runtime: PathBuf, headless: bool) -> Result<()> {
    let target = Target::host();
    let manifest = common::BundleManifest::new(&ctx.config, &target);

    let bundle_dir = package::run(&ctx, target, &tui_binary, &runtime, true, None, false)?;

    let runtime_path = bundle_dir.join(&manifest.runtime_name);
    exec_runtime(&runtime_path, headless)
}

#[cfg(unix)]
fn exec_runtime(runtime: &Path, headless: bool) -> Result<()> {
    use std::os::unix::process::CommandExt;

    let mut cmd = Command::new(runtime);
    if headless {
        cmd.arg("--headless");
    }
    let err = cmd.exec();

    // exec() only returns on error
    Err(err).context("failed to exec trolley runtime")
}

#[cfg(not(unix))]
fn exec_runtime(runtime: &Path, headless: bool) -> Result<()> {
    let mut cmd = Command::new(runtime);
    if headless {
        cmd.arg("--headless");
    }
    let status = cmd
        .status()
        .context("failed to run trolley runtime")?;

    std::process::exit(status.code().unwrap_or(1));
}
