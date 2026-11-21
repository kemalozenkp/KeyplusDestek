// Read-only service inventory, exposed through the existing asynchronous FFI.
// This does not authorize IPC peers or change connection/access policy.
use hbb_common::{anyhow::{bail, Context}, ResultType};
use serde_json::{json, Value};
use std::{path::Path, time::UNIX_EPOCH};

fn newer_build_date(current: &str, installed: &str) -> bool {
    let parse = |value| chrono::NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M");
    match (parse(current), parse(installed)) {
        (Ok(current), Ok(installed)) => current > installed,
        _ => false,
    }
}

pub(crate) fn inspect() -> ResultType<Value> {
    use windows_service::{service::{ServiceAccess, ServiceState}, service_manager::{ServiceManager, ServiceManagerAccess}};
    use hbb_common::sysinfo::{Pid, System};
    let current = std::env::current_exe()?;
    let (_, _, _, installed) = crate::platform::windows::get_install_info();
    if !Path::new(&installed).is_file() {
        return Ok(json!({"state":"portable", "canUpdate":false}));
    }
    let matching = crate::keyplus_window::same_payload_files(&current, Path::new(&installed))?;
    let build_date = crate::platform::windows::get_reg("BuildDate");
    // A content difference is not proof of which build is newer. Never offer an
    // older or unknown GUI as an automatic replacement for the installed build.
    let can_update = !matching && newer_build_date(crate::BUILD_DATE, &build_date)
        && current.canonicalize()? != Path::new(&installed).canonicalize()?
        && !hbb_common::config::is_disable_installation();
    if !matching {
        return Ok(json!({"state":"mismatch", "canUpdate":can_update}));
    }
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;
    let service = manager.open_service(crate::get_app_name(), ServiceAccess::QUERY_STATUS)?;
    let status = service.query_status()?;
    if status.current_state != ServiceState::Running {
        return Ok(json!({"state":"stopped", "canUpdate":false}));
    }
    let pid = status.process_id.context("Service process not available")?;
    let executable = crate::platform::windows::get_process_executable_path(pid)?;
    if executable.canonicalize()? != Path::new(&installed).canonicalize()? {
        bail!("Service executable is not the registered installation");
    }
    let mut system = System::new();
    system.refresh_process(Pid::from_u32(pid));
    let process = system.process(Pid::from_u32(pid)).context("Service process no longer running")?;
    // A file replaced after process startup does not prove the loaded version.
    for path in [Path::new(&installed).to_path_buf(), Path::new(&installed).parent().context("Install directory missing")?.join("librustdesk.dll")] {
        if path.metadata()?.modified()?.duration_since(UNIX_EPOCH)?.as_secs() > process.start_time().saturating_add(1) {
            bail!("Installed files changed after service startup");
        }
    }
    Ok(json!({"state":"compatible", "canUpdate":false}))
}

pub(crate) fn status() -> String {
    match inspect() {
        Ok(value) => value.to_string(),
        Err(error) => {
            hbb_common::throttled_log!(std::time::Duration::from_secs(5), debug, "Keyplus service inventory unavailable: {error:#}");
            json!({"state":"unknown", "canUpdate":false}).to_string()
        }
    }
}

pub(crate) fn request_update() -> String {
    let allowed = inspect().map(|value| value["state"] == "mismatch" && value["canUpdate"] == true).unwrap_or(false);
    if !allowed {
        return json!({"result":"unavailable"}).to_string();
    }
    // The normal Windows consent prompt remains mandatory. Existing --update
    // preserves profile/ID/password instead of re-importing installation defaults.
    let result = match crate::platform::windows::elevate("--update") {
        Ok(true) => "launched",
        Ok(false) => "cancelled",
        Err(error) => { hbb_common::log::warn!("Keyplus update launch failed: {error:#}"); "failed" }
    };
    json!({"result":result}).to_string()
}

#[cfg(test)]
mod keyplus_health_tests {
    use super::newer_build_date;
    #[test]
    fn only_a_known_strictly_newer_build_offers_update() {
        assert!(newer_build_date("2026-11-20 12:20", "2026-11-20 06:20"));
        for installed in ["", "0", "unknown", "2026-99-20 06:20", "2026-11-20 12:20", "2026-11-20 12:21"] {
            assert!(!newer_build_date("2026-11-20 12:20", installed));
        }
        assert!(!newer_build_date("unknown", "2026-11-20 12:20"));
    }
}
