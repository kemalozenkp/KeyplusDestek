// DSK2697028: identify a main window by its process and payload, not its EXE name.
use hbb_common::{anyhow::Context, log, sha2::{Digest, Sha256}, ResultType};
use std::{fs, io::Read, path::Path, sync::{Mutex, OnceLock}};

// A process handle prevents a cached identity from following a reused PID.
// It neither keeps the process alive nor locks the installed application files.
struct TrustedProcess { pid: u32, handle: usize }
impl TrustedProcess {
    fn open(pid: u32) -> ResultType<Self> {
        use winapi::{shared::minwindef::FALSE, um::{processthreadsapi::OpenProcess, winnt::SYNCHRONIZE}};
        let handle = unsafe { OpenProcess(SYNCHRONIZE, FALSE, pid) };
        if handle.is_null() { return Err(std::io::Error::last_os_error().into()); }
        Ok(Self { pid, handle: handle as usize })
    }
    fn alive(&self) -> bool {
        unsafe { winapi::um::synchapi::WaitForSingleObject(self.handle as _, 0) == windows::Win32::Foundation::WAIT_TIMEOUT.0 }
    }
}
impl Drop for TrustedProcess {
    fn drop(&mut self) { unsafe { winapi::um::handleapi::CloseHandle(self.handle as _); } }
}

#[derive(Debug, PartialEq, Eq)]
struct Payload {
    executable: [u8; 32], native_library: [u8; 32],
    executable_size: u64, native_library_size: u64,
}
fn hash_file(path: &Path) -> ResultType<[u8; 32]> {
    let mut file = fs::File::open(path)?;
    let mut digest = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 { break; }
        digest.update(&buffer[..count]);
    }
    Ok(digest.finalize().into())
}
fn payload(executable: &Path) -> ResultType<Payload> {
    let library = executable.parent().context("Executable directory unavailable")?.join("librustdesk.dll");
    Ok(Payload {
        executable: hash_file(executable)?, native_library: hash_file(&library)?,
        executable_size: fs::metadata(executable)?.len(), native_library_size: fs::metadata(library)?.len(),
    })
}
fn matches_payload(peer: &Path, expected: &Payload) -> ResultType<bool> {
    let library = peer.parent().context("Peer directory unavailable")?.join("librustdesk.dll");
    if fs::metadata(peer)?.len() != expected.executable_size
        || fs::metadata(library)?.len() != expected.native_library_size { return Ok(false); }
    Ok(payload(peer)? == *expected)
}
// Read afresh for inventory: the IPC process-lifetime cache is intentionally not
// used to assert that a newly installed service has matching files.
pub(crate) fn same_payload_files(first: &Path, second: &Path) -> ResultType<bool> {
    matches_payload(second, &payload(first)?)
}
pub(crate) fn same_application(peer_pid: u32, peer: &Path) -> ResultType<bool> {
    static PEERS: Mutex<Vec<TrustedProcess>> = Mutex::new(Vec::new());
    {
        let mut peers = PEERS.lock().unwrap();
        peers.retain(TrustedProcess::alive);
        if peers.iter().any(|process| process.pid == peer_pid) { return Ok(true); }
    }
    let process = TrustedProcess::open(peer_pid)?;
    static CURRENT: OnceLock<Result<Payload, String>> = OnceLock::new();
    let expected = CURRENT.get_or_init(|| {
        let load = || -> ResultType<Payload> { payload(&std::env::current_exe()?) };
        load().map_err(|error| format!("Keyplus application identity unavailable: {error:#}"))
    });
    let expected = expected.as_ref().map_err(|error| hbb_common::anyhow::anyhow!("{error}"))?;
    if !matches_payload(peer, expected)? || !process.alive() { return Ok(false); }
    let mut peers = PEERS.lock().unwrap();
    peers.retain(TrustedProcess::alive);
    if peers.len() >= 32 { peers.remove(0); }
    peers.push(process);
    Ok(true)
}

#[cfg(feature = "flutter")]
fn window_processes() -> Vec<u32> {
    use winapi::{shared::{minwindef::{BOOL, LPARAM, TRUE, FALSE}, windef::HWND},
        um::winuser::{EnumWindows, GetClassNameW, GetWindowThreadProcessId, IsWindowVisible}};
    unsafe extern "system" fn inspect(window: HWND, parameter: LPARAM) -> BOOL {
        if IsWindowVisible(window) != FALSE {
            let mut class = [0u16; 128];
            let size = GetClassNameW(window, class.as_mut_ptr(), class.len() as i32);
            if size > 0 && String::from_utf16_lossy(&class[..size as usize]) == "FLUTTER_RUNNER_WIN32_WINDOW" {
                let mut pid = 0;
                GetWindowThreadProcessId(window, &mut pid);
                if pid != 0 { (&mut *(parameter as *mut Vec<u32>)).push(pid); }
            }
        }
        TRUE
    }
    let mut processes = Vec::new();
    if unsafe { EnumWindows(Some(inspect), &mut processes as *mut Vec<u32> as LPARAM) } == FALSE {
        hbb_common::throttled_log!(std::time::Duration::from_secs(5), warn,
            "Keyplus main-window enumeration failed: {}", std::io::Error::last_os_error());
    }
    processes.sort_unstable(); processes.dedup(); processes
}

#[cfg(feature = "flutter")]
pub(crate) fn is_open() -> bool {
    use hbb_common::sysinfo::{Pid, System};
    let candidates = window_processes();
    if candidates.is_empty() { return false; }
    let mut system = System::new(); system.refresh_processes();
    let my_uid = system.process(Pid::from_u32(std::process::id())).and_then(|process| process.user_id());
    for pid in candidates {
        let Some(process) = system.process(Pid::from_u32(pid)) else { continue; };
        if !crate::platform::is_root() && process.user_id() != my_uid { continue; }
        // Connection-manager, tray and remote-session windows are not the main UI.
        if process.cmd().get(1).is_some_and(|argument| argument.starts_with("--")) { continue; }
        match same_application(pid, process.exe()) {
            Ok(true) => return true,
            Ok(false) => {}
            Err(error) => log::trace!("Keyplus window candidate rejected (pid={pid}): {error:#}"),
        }
    }
    false
}

#[cfg(test)]
mod keyplus_window_tests {
    use super::*;
    struct Fixture(std::path::PathBuf);
    impl Fixture {
        fn new() -> Self {
            let dir = std::env::temp_dir().join(format!("keyplus-window-{}", uuid::Uuid::new_v4()));
            fs::create_dir(&dir).unwrap(); Self(dir)
        }
        fn binary(&self, directory: &str, name: &str, executable: &[u8], native: &[u8]) -> std::path::PathBuf {
            let dir = self.0.join(directory); fs::create_dir_all(&dir).unwrap();
            let path = dir.join(name); fs::write(&path, executable).unwrap();
            fs::write(dir.join("librustdesk.dll"), native).unwrap(); path
        }
    }
    impl Drop for Fixture { fn drop(&mut self) { fs::remove_dir_all(&self.0).unwrap(); } }
    #[test]
    fn file_name_and_directory_do_not_replace_application_identity() {
        let f = Fixture::new();
        let installed = f.binary("installed", "KeyplusDestek.exe", b"runner", b"native");
        let renamed = f.binary("downloads", "Support (2).exe", b"runner", b"native");
        let changed_exe = f.binary("other-exe", "KeyplusDestek.exe", b"RUNNER", b"native");
        let changed_dll = f.binary("other-dll", "KeyplusDestek.exe", b"runner", b"NATIVE");
        let expected = payload(&installed).unwrap();
        assert!(matches_payload(&renamed, &expected).unwrap());
        assert!(!matches_payload(&changed_exe, &expected).unwrap());
        assert!(!matches_payload(&changed_dll, &expected).unwrap());
        fs::remove_file(changed_dll.parent().unwrap().join("librustdesk.dll")).unwrap();
        assert!(matches_payload(&changed_dll, &expected).is_err());
    }
    #[test]
    fn identity_child_process() {
        if std::env::var_os("KEYPLUS_IDENTITY_CHILD").is_some() {
            std::thread::sleep(std::time::Duration::from_millis(800));
        }
    }
    #[test]
    fn cached_identity_expires_when_its_exact_process_exits() {
        let mut child = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "keyplus_window::keyplus_window_tests::identity_child_process"])
            .env("KEYPLUS_IDENTITY_CHILD", "1")
            .stdout(std::process::Stdio::null()).spawn().unwrap();
        let process = TrustedProcess::open(child.id()).unwrap();
        assert!(process.alive()); assert!(child.wait().unwrap().success()); assert!(!process.alive());
        assert!(TrustedProcess::open(0).is_err());
    }
    #[cfg(feature = "flutter")]
    #[test]
    fn hidden_or_closed_native_window_is_not_open_even_while_process_lives() {
        use winapi::{shared::minwindef::FALSE, um::{libloaderapi::GetModuleHandleW,
            winuser::{CreateWindowExW, DefWindowProcW, DestroyWindow, RegisterClassW,
                ShowWindow, UnregisterClassW, WNDCLASSW, WS_OVERLAPPEDWINDOW, SW_HIDE, SW_SHOWNOACTIVATE}}};
        let class: Vec<u16> = "FLUTTER_RUNNER_WIN32_WINDOW\0".encode_utf16().collect();
        let title: Vec<u16> = "Keyplus presence test\0".encode_utf16().collect();
        unsafe {
            let instance = GetModuleHandleW(std::ptr::null());
            let mut definition: WNDCLASSW = std::mem::zeroed();
            definition.lpfnWndProc = Some(DefWindowProcW); definition.hInstance = instance;
            definition.lpszClassName = class.as_ptr(); assert_ne!(RegisterClassW(&definition), 0);
            let window = CreateWindowExW(0, class.as_ptr(), title.as_ptr(), WS_OVERLAPPEDWINDOW,
                0, 0, 100, 100, std::ptr::null_mut(), std::ptr::null_mut(), instance, std::ptr::null_mut());
            assert!(!window.is_null()); assert!(!window_processes().contains(&std::process::id()));
            ShowWindow(window, SW_SHOWNOACTIVATE); assert!(window_processes().contains(&std::process::id()));
            ShowWindow(window, SW_HIDE); assert!(!window_processes().contains(&std::process::id()));
            assert_ne!(DestroyWindow(window), FALSE); assert!(!window_processes().contains(&std::process::id()));
            assert_ne!(UnregisterClassW(class.as_ptr(), instance), FALSE);
        }
    }
}
