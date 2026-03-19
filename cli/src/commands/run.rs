use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result};
use trolley_config::Target;

use super::{common, package};
use common::ProjectContext;

pub fn run(ctx: ProjectContext, tui_binary: PathBuf, runtime: PathBuf) -> Result<()> {
    let target = Target::host();
    let manifest = common::BundleManifest::new(&ctx.config, &target);

    let bundle_dir = package::run(&ctx, target, &tui_binary, &runtime, true, None, false)?;

    let runtime_path = bundle_dir.join(&manifest.runtime_name);
    exec_runtime(&runtime_path)
}

#[cfg(unix)]
fn exec_runtime(runtime: &Path) -> Result<()> {
    use std::os::unix::process::CommandExt;

    let err = Command::new(runtime).exec();

    // exec() only returns on error
    Err(err).context("failed to exec trolley runtime")
}

#[cfg(not(unix))]
fn exec_runtime(runtime: &Path) -> Result<()> {
    let status = Command::new(runtime)
        .status()
        .context("failed to run trolley runtime")?;

    std::process::exit(status.code().unwrap_or(1));
}
