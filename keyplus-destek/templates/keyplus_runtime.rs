use hbb_common::{
    anyhow::{bail, Context},
    config, log, ResultType,
};
use serde_derive::Deserialize;
use std::{fs, net::Ipv4Addr, sync::OnceLock};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ServerConfig {
    environment: String,
    #[serde(rename = "serverHost")]
    host: String,
    #[serde(rename = "publicKey")]
    key: String,
    #[serde(rename = "accessMode", default = "default_access_mode")]
    access_mode: String,
}

fn default_access_mode() -> String {
    "quick-support".into()
}

fn parse_config(text: &str) -> ResultType<ServerConfig> {
    let config: ServerConfig = serde_json::from_str(text)?;
    if !matches!(config.environment.as_str(), "local" | "pilot") {
        bail!("Geçersiz bağlantı ortamı");
    }
    let valid_dns = config.host.len() <= 253
        && config.host.contains('.')
        && config.host.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
        });
    let ip = config.host.parse::<Ipv4Addr>();
    if config.host.is_empty() || (ip.is_err() && !valid_dns) {
        bail!("Geçersiz bağlantı sunucusu");
    }
    if config.environment == "local" && config.host != "127.0.0.1" {
        bail!("Yerel bağlantı adresi 127.0.0.1 olmalıdır");
    }
    if config.environment == "pilot" {
        let host = config.host.to_ascii_lowercase();
        if ip.as_ref().map_or(false, |ip| ip.is_loopback() || ip.is_unspecified() || ip.is_broadcast())
            || [".localhost", ".invalid", ".test", ".example", ".example.com", ".example.net", ".example.org"]
                .iter().any(|suffix| host.ends_with(suffix))
            || ["example.com", "example.net", "example.org"].contains(&host.as_str())
        {
            bail!("Pilot için gerçek bağlantı sunucusu gereklidir");
        }
    }
    if crate::get_rs_pk(&config.key).is_none() {
        bail!("Sunucunun açık anahtarı geçersiz");
    }
    if !matches!(config.access_mode.as_str(), "quick-support" | "unattended") {
        bail!("Geçersiz erişim modu");
    }
    Ok(config)
}

fn configure() -> ResultType<()> {
    let executable = std::env::current_exe()?;
    let directory = executable.parent().context("Uygulama klasörü bulunamadı")?;
    let file = directory.join("data").join("keyplus-server.json");
    if fs::metadata(&file)?.len() > 16384 {
        bail!("Bağlantı yapılandırması beklenenden büyük");
    }
    let selected = parse_config(&fs::read_to_string(file)?)?;
    let unattended = selected.access_mode == "unattended";
    let mut settings = config::OVERWRITE_SETTINGS.write().unwrap();
    for (key, value) in [
        ("custom-rendezvous-server", format!("{}:21116", selected.host)),
        ("relay-server", format!("{}:21117", selected.host)),
        ("key", selected.key),
        ("api-server", String::new()),
        ("enable-check-update", "N".into()),
        ("allow-auto-update", "N".into()),
        ("enable-terminal", "N".into()),
        ("enable-tunnel", "N".into()),
    ] {
        settings.insert(key.into(), value);
    }
    drop(settings);
    let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
    for (key, value) in [
        ("approve-mode", if unattended { "password" } else { "click" }),
        ("verification-method", if unattended { "use-permanent-password" } else { "use-temporary-password" }),
        ("allow-only-conn-window-open", if unattended { "N" } else { "Y" }),
    ] {
        defaults.insert(key.into(), value.into());
    }
    drop(defaults);
    config::DEFAULT_LOCAL_SETTINGS.write().unwrap().insert("lang".into(), "tr".into());
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    for (key, value) in [("disable-account", "Y"), ("disable-ab", "Y"), ("disable-installation", "N")] {
        hard.insert(key.into(), value.into());
    }
    Ok(())
}

pub fn init() -> bool {
    static RESULT: OnceLock<bool> = OnceLock::new();
    *RESULT.get_or_init(|| match configure() {
        Ok(()) => true,
        Err(error) => {
            log::error!("Keyplus bağlantı yapılandırması yüklenemedi: {error:#}");
            eprintln!("Keyplus bağlantı yapılandırması yüklenemedi: {error:#}");
            crate::platform::message_box("Keyplus Destek bağlantı yapılandırması eksik veya geçersiz. Kurulum paketini yeniden indirin.");
            false
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(mode: &str) -> String {
        serde_json::json!({ "environment": "local", "serverHost": "127.0.0.1", "publicKey": hbb_common::base64::encode([7u8; 32]), "accessMode": mode }).to_string()
    }

    #[test]
    fn both_modes_use_the_same_native_configuration_format() {
        assert_eq!(parse_config(&input("quick-support")).unwrap().access_mode, "quick-support");
        assert_eq!(parse_config(&input("unattended")).unwrap().access_mode, "unattended");
    }

    #[test]
    fn corrected_identifier_keeps_the_existing_device_profile() {
        assert_eq!(crate::get_app_name(), "KeyplusDestek");
        let file = config::Config::file();
        assert_eq!(file.file_name().unwrap(), "Keyplus Destek.toml");
        assert_eq!(file.parent().unwrap().parent().unwrap().file_name().unwrap(), "Keyplus Destek");
    }

    #[test]
    fn missing_server_key_and_unknown_password_fields_are_rejected() {
        assert!(parse_config("{}").is_err());
        let mut data: serde_json::Value = serde_json::from_str(&input("unattended")).unwrap();
        data["publicKey"] = "".into();
        assert!(parse_config(&data.to_string()).is_err());
        data = serde_json::from_str(&input("unattended")).unwrap();
        data["permanentPassword"] = "not-a-distribution-setting".into();
        assert!(parse_config(&data.to_string()).is_err());
    }
}
