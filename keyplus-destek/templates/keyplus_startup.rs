// DSK2697047: a downloaded client continues through the existing installation.
use hbb_common::{bail, log, ResultType};
use std::path::Path;

const UPDATE_AND_RUN: &str = "--keyplus-update-and-run";

fn is_startup_request(args: &[String], process_arg_count: usize) -> bool {
    (args.is_empty() && process_arg_count == 1)
        || (args.len() == 1 && args[0] == UPDATE_AND_RUN)
}

fn continue_installed(installed: &str, updater: bool) -> ResultType<()> {
    use crate::platform::windows;
    let update_available = match crate::keyplus_health::inspect() {
        Ok(status) => status["canUpdate"] == true,
        Err(error) => {
            log::warn!("Keyplus startup could not verify an update; opening installed client: {error:#}");
            false
        }
    };
    if update_available {
        if !windows::is_elevated(None)? && !windows::is_root() {
            if windows::elevate(UPDATE_AND_RUN)? {
                return Ok(());
            }
            log::info!("Keyplus startup update consent cancelled; opening installed client.");
        } else if !updater {
            // The native updater terminates ordinary GUI processes by arguments.
            // Run with an explicit role so it cannot terminate its own controller.
            let current = std::env::current_exe()?;
            let current = current.to_str().ok_or_else(|| hbb_common::anyhow::anyhow!("Executable path is not valid UTF-8"))?;
            windows::run_exe_direct(current, vec![UPDATE_AND_RUN], false)?;
            return Ok(());
        } else {
            if !windows::prepare_custom_client_update()? {
                bail!("The native updater refused the client configuration");
            }
            windows::update_me(false)?;
            if !crate::keyplus_window::same_payload_files(&std::env::current_exe()?, Path::new(installed))? {
                bail!("Installed application files did not match after the update");
            }
        }
    }
    windows::run_exe_in_cur_session(installed, vec![], true)?;
    Ok(())
}

pub(crate) fn handle_startup(args: &[String]) -> bool {
    if !is_startup_request(args, std::env::args_os().len()) {
        return false;
    }
    let (_, _, _, installed) = crate::platform::windows::get_install_info();
    if !Path::new(&installed).is_file() || crate::platform::windows::is_cur_exe_the_installed() {
        return false;
    }
    let updater = args.first().map(String::as_str) == Some(UPDATE_AND_RUN);
    if let Err(error) = continue_installed(&installed, updater) {
        log::error!("Keyplus installed startup failed: {error:#}");
        crate::platform::message_box(
            "Kurulu Keyplus Destek uygulaması açılamadı veya güncellenemedi. Mevcut ayarlar korunur. Yönetici iznini ve kurulu uygulamayı kontrol edip yeniden deneyin.",
        );
    }
    true
}

#[cfg(test)]
mod keyplus_startup_tests {
    use super::is_startup_request;

    #[test]
    fn only_an_ordinary_launch_or_the_explicit_updater_uses_installed_handoff() {
        assert!(is_startup_request(&[], 1));
        assert!(is_startup_request(&["--keyplus-update-and-run".into()], 2));
        assert!(!is_startup_request(&[], 2));
        for command in ["--service", "--server", "--tray", "--version", "--build-date", "--keyplus-service-status", "--password", "--get-id", "--noinstall", "--connect", "--update", "--uninstall", "--silent-install"] {
            assert!(!is_startup_request(&[command.into()], 2));
        }
        assert!(!is_startup_request(&["--keyplus-update-and-run".into(), "extra".into()], 3));
    }
}
