//! What the program keeps: its certificate and key, and the phones paired with it (spec-protocol.md 4.4, 5.6).
//! One private folder, `~/.config/amethystora/connect` (0700), with files of 0600; every write goes to a
//! temporary file first and is renamed over the old one, so a crash leaves one or the other whole.

use std::collections::BTreeMap;
use std::io::{ErrorKind, Write};
use std::net::IpAddr;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde::{Deserialize, Serialize};

use crate::identity::valid_device_id;
use crate::x509;

const CERTIFICATE: &str = "certificate.pem";
const KEY: &str = "private-key.pem";
const DEVICES: &str = "devices.json";

/// A private folder: created 0700, and made 0700 if it was not
pub fn private_dir(dir: &Path) -> std::io::Result<()> {
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
}

/// A file only its owner reads, written whole or not at all. The temporary file is made new, with no link
/// followed and no mode but 0600, so that nothing left lying there can decide who reads what is put in it.
pub fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(".new");
    let temporary = PathBuf::from(temporary);
    let result = (|| {
        match std::fs::remove_file(&temporary) {
            Err(e) if e.kind() != ErrorKind::NotFound => return Err(e),
            _ => {}
        }
        let mut file = std::fs::OpenOptions::new().write(true).create_new(true).custom_flags(libc::O_NOFOLLOW).mode(0o600).open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        std::fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result
}

/// This computer's certificate and key, and the device id the certificate names
pub struct Material {
    pub device_id: String,
    pub der: Vec<u8>,
    /// The public key as the verification key hashes it
    pub spki: Vec<u8>,
    pub tls: gio::TlsCertificate,
}

/// Loads the certificate and key, or makes new ones. Ones that are missing, do not name a valid device id, or
/// are not a certificate and the key it holds are replaced together with the id, and every pairing made with
/// the old one is void: a phone pins the certificate it paired with and would refuse another. The list of the
/// paired phones is kept beside the new identity as `devices.json.bak`, not deleted. A file that cannot be
/// *read* (a failing disk, a permission) is not a reason to start over: the program does not start.
/// Returns whether new ones were made.
pub fn load_material(dir: &Path, now: i64) -> Result<(Material, bool), String> {
    private_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let read = |name: &str| -> Result<Option<String>, String> {
        match std::fs::read_to_string(dir.join(name)) {
            Ok(text) => Ok(Some(text)),
            Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
            // Not UTF-8 is a file that is not a PEM: the same as a damaged one
            Err(e) if e.kind() == ErrorKind::InvalidData => Ok(Some(String::new())),
            Err(e) => Err(format!("{}: {e}", dir.join(name).display())),
        }
    };
    let (certificate_pem, key_pem) = (read(CERTIFICATE)?, read(KEY)?);
    if let (Some(certificate), Some(key)) = (&certificate_pem, &key_pem) {
        if let Some(material) = material_from(dir, certificate, key)? {
            return Ok((material, false));
        }
    }
    match std::fs::rename(dir.join(DEVICES), dir.join("devices.json.bak")) {
        Err(e) if e.kind() != ErrorKind::NotFound => return Err(format!("cannot set the old pairings aside: {e}")),
        _ => {}
    }
    let device_id = new_device_id()?;
    let made = x509::generate(&device_id, now)?;
    write_private(&dir.join(KEY), made.key_pem.as_bytes()).map_err(|e| format!("cannot keep the key: {e}"))?;
    write_private(&dir.join(CERTIFICATE), made.certificate_pem.as_bytes()).map_err(|e| format!("cannot keep the certificate: {e}"))?;
    let (certificate_pem, key_pem) = (read(CERTIFICATE)?.unwrap_or_default(), read(KEY)?.unwrap_or_default());
    let material = material_from(dir, &certificate_pem, &key_pem)?.ok_or("the certificate just made cannot be read back")?;
    Ok((material, true))
}

/// The certificate and key as a identity, if they are one: `Ok(None)` for files that are not (damaged, another
/// certificate's key, an id that is no id), and an error when they are what they should be and the TLS library
/// still cannot take them. That is the library's trouble, not the files', and nothing is made over because of it.
fn material_from(dir: &Path, certificate_pem: &str, key_pem: &str) -> Result<Option<Material>, String> {
    let Some(der) = x509::pem_to_der(certificate_pem) else { return Ok(None) };
    let Some(parts) = x509::parts(&der) else { return Ok(None) };
    let Some(device_id) = parts.common_name.filter(|id| valid_device_id(id)) else { return Ok(None) };
    if !x509::key_matches(key_pem, &parts.spki) {
        return Ok(None);
    }
    let _ = std::fs::set_permissions(dir.join(KEY), std::fs::Permissions::from_mode(0o600));
    let tls = gio::TlsCertificate::from_pem(&format!("{certificate_pem}{key_pem}")).map_err(|e| {
        format!("the TLS library cannot read this computer's certificate in {} ({}); nothing was changed, and the program does not start", dir.display(), e.message())
    })?;
    Ok(Some(Material { device_id, der, spki: parts.spki, tls }))
}

/// A random UUID (version 4) without its hyphens: 32 lowercase hexadecimal characters
fn new_device_id() -> Result<String, String> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).map_err(|e| format!("no random numbers: {e}"))?;
    bytes[6] = bytes[6] & 0x0f | 0x40;
    bytes[8] = bytes[8] & 0x3f | 0x80;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// A paired device, as it is kept
#[derive(Debug, Clone, PartialEq)]
pub struct Paired {
    pub name: String,
    pub kind: String,
    pub protocol: u32,
    pub incoming: Vec<String>,
    pub outgoing: Vec<String>,
    /// The device's certificate, DER: what every connection of it must present
    pub pin: Vec<u8>,
    /// Where it was last reached, to try again with
    pub address: Option<(IpAddr, u16)>,
    pub paired_at: i64,
}

#[derive(Serialize, Deserialize)]
struct File {
    version: u32,
    devices: BTreeMap<String, Entry>,
}

#[derive(Serialize, Deserialize)]
struct Entry {
    name: String,
    #[serde(rename = "type")]
    kind: String,
    protocol: u32,
    incoming: Vec<String>,
    outgoing: Vec<String>,
    pin: String,
    address: Option<String>,
    port: Option<u16>,
    paired_at: i64,
}

/// The paired devices
pub struct Devices {
    path: PathBuf,
    pub paired: BTreeMap<String, Paired>,
}

impl Devices {
    /// The paired phones. A list that is not there is none; one that cannot be read stops the program (a failing
    /// disk is no reason to forget every pairing); one that is not a list is set aside as `devices.json.bak`.
    pub fn load(dir: &Path) -> Result<Devices, String> {
        let path = dir.join(DEVICES);
        let mut paired = BTreeMap::new();
        let text = match std::fs::read_to_string(&path) {
            Ok(text) => Some(text),
            Err(e) if e.kind() == ErrorKind::NotFound => None,
            Err(e) if e.kind() == ErrorKind::InvalidData => Some(String::new()),
            Err(e) => return Err(format!("{}: {e}", path.display())),
        };
        let parsed = text.as_deref().map(serde_json::from_str::<File>);
        if let Some(Err(_)) = parsed {
            eprintln!("amethystora-connect: the list of paired phones is damaged; it is kept as devices.json.bak");
            std::fs::rename(&path, dir.join("devices.json.bak")).map_err(|e| format!("cannot set the damaged list aside: {e}"))?;
        }
        if let Some(Ok(file)) = parsed {
            for (id, e) in file.devices {
                let Ok(pin) = STANDARD.decode(&e.pin) else { continue };
                // Only a certificate this program can read is a pin; an entry that is not one is not paired
                if !valid_device_id(&id) || x509::parts(&pin).is_none() {
                    continue;
                }
                let address = e.address.and_then(|a| a.parse().ok()).map(|ip| (ip, e.port.unwrap_or(crate::limits::DISCOVERY_PORT)));
                paired.insert(id, Paired { name: e.name, kind: e.kind, protocol: e.protocol, incoming: e.incoming, outgoing: e.outgoing, pin, address, paired_at: e.paired_at });
            }
        }
        Ok(Devices { path, paired })
    }

    pub fn save(&self) -> std::io::Result<()> {
        let devices = self
            .paired
            .iter()
            .map(|(id, p)| {
                let entry = Entry {
                    name: p.name.clone(),
                    kind: p.kind.clone(),
                    protocol: p.protocol,
                    incoming: p.incoming.clone(),
                    outgoing: p.outgoing.clone(),
                    pin: STANDARD.encode(&p.pin),
                    address: p.address.map(|(ip, _)| ip.to_string()),
                    port: p.address.map(|(_, port)| port),
                    paired_at: p.paired_at,
                };
                (id.clone(), entry)
            })
            .collect();
        let text = serde_json::to_string_pretty(&File { version: 1, devices }).map_err(std::io::Error::other)?;
        write_private(&self.path, text.as_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("amethystora-connect-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn an_identity_is_made_once_and_kept() {
        let dir = folder("identity");
        let (first, created) = load_material(&dir, 1_792_741_234).unwrap();
        assert!(created);
        assert!(valid_device_id(&first.device_id));
        assert_eq!(first.device_id.len(), 32);
        assert!(first.device_id.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
        let (second, created) = load_material(&dir, 1_792_741_999).unwrap();
        assert!(!created, "the same certificate is loaded");
        assert_eq!(first.device_id, second.device_id);
        assert_eq!(first.der, second.der);
        assert_eq!(std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777, 0o700);
        assert_eq!(std::fs::metadata(dir.join(KEY)).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(std::fs::metadata(dir.join(CERTIFICATE)).unwrap().permissions().mode() & 0o777, 0o600);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_damaged_identity_is_replaced_and_voids_the_pairings() {
        let dir = folder("damaged");
        let (first, _) = load_material(&dir, 1_792_741_234).unwrap();
        let mut devices = Devices::load(&dir).unwrap();
        devices.paired.insert("4a8f2c7e_91d3_4b5a_8e6f_0c1d2e3f4a5b".into(), Paired { name: "Sam phone".into(), kind: "phone".into(), protocol: 8, incoming: vec![], outgoing: vec![], pin: first.der.clone(), address: None, paired_at: 1 });
        devices.save().unwrap();
        assert_eq!(Devices::load(&dir).unwrap().paired.len(), 1);

        // The key of another certificate: the pair does not match
        let other = x509::generate(&first.device_id, 1_792_741_234).unwrap();
        std::fs::write(dir.join(KEY), other.key_pem).unwrap();
        let (second, created) = load_material(&dir, 1_792_741_234).unwrap();
        assert!(created);
        assert_ne!(first.device_id, second.device_id);
        assert!(Devices::load(&dir).unwrap().paired.is_empty(), "a new identity starts with no pairings");
        assert!(dir.join("devices.json.bak").exists(), "the old list is kept, not deleted");

        // A certificate cut short
        let certificate = std::fs::read_to_string(dir.join(CERTIFICATE)).unwrap();
        std::fs::write(dir.join(CERTIFICATE), &certificate[..certificate.len() / 2]).unwrap();
        let (third, created) = load_material(&dir, 1_792_741_234).unwrap();
        assert!(created);
        assert_ne!(second.device_id, third.device_id);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn paired_devices_round_trip() {
        let dir = folder("devices");
        let (me, _) = load_material(&dir, 1_792_741_234).unwrap();
        let mut devices = Devices::load(&dir).unwrap();
        let paired = Paired {
            name: "Sam phone".into(),
            kind: "phone".into(),
            protocol: 8,
            incoming: vec!["kdeconnect.ping".into()],
            outgoing: vec!["kdeconnect.battery".into()],
            pin: me.der.clone(),
            address: Some(("192.168.1.37".parse().unwrap(), 1716)),
            paired_at: 1_792_741_251,
        };
        devices.paired.insert("4a8f2c7e_91d3_4b5a_8e6f_0c1d2e3f4a5b".into(), paired.clone());
        devices.save().unwrap();
        let back = Devices::load(&dir).unwrap();
        assert_eq!(back.paired.get("4a8f2c7e_91d3_4b5a_8e6f_0c1d2e3f4a5b"), Some(&paired));
        assert_eq!(std::fs::metadata(dir.join(DEVICES)).unwrap().permissions().mode() & 0o777, 0o600);
        // An entry with an id that is no id, or a pin that is no certificate, is not read
        let mut file: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(dir.join(DEVICES)).unwrap()).unwrap();
        let entry = file["devices"]["4a8f2c7e_91d3_4b5a_8e6f_0c1d2e3f4a5b"].clone();
        file["devices"]["short"] = entry.clone();
        let mut bad_pin = entry;
        bad_pin["pin"] = "AAAA".into();
        file["devices"]["4a8f2c7e_91d3_4b5a_8e6f_0c1d2e3f4a5c"] = bad_pin;
        std::fs::write(dir.join(DEVICES), file.to_string()).unwrap();
        assert_eq!(Devices::load(&dir).unwrap().paired.len(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_failure_to_read_never_wipes_the_pairings() {
        let dir = folder("unreadable");
        let (_, _) = load_material(&dir, 1_792_741_234).unwrap();
        let mut devices = Devices::load(&dir).unwrap();
        devices.paired.insert("4a8f2c7e_91d3_4b5a_8e6f_0c1d2e3f4a5b".into(), Paired { name: "Sam phone".into(), kind: "phone".into(), protocol: 8, incoming: vec![], outgoing: vec![], pin: std::fs::read(dir.join(CERTIFICATE)).map(|p| x509::pem_to_der(&String::from_utf8_lossy(&p)).unwrap()).unwrap(), address: None, paired_at: 1 });
        devices.save().unwrap();

        // A certificate that is a folder cannot be read: not the same as one that is damaged
        std::fs::remove_file(dir.join(CERTIFICATE)).unwrap();
        std::fs::create_dir(dir.join(CERTIFICATE)).unwrap();
        assert!(load_material(&dir, 1_792_741_234).is_err(), "the program does not start over");
        assert!(dir.join(DEVICES).exists(), "the pairings are where they were");
        std::fs::remove_dir(dir.join(CERTIFICATE)).unwrap();

        // The list of phones as a folder: the same
        std::fs::rename(dir.join(DEVICES), dir.join("saved.json")).unwrap();
        std::fs::create_dir(dir.join(DEVICES)).unwrap();
        assert!(Devices::load(&dir).is_err());
        std::fs::remove_dir(dir.join(DEVICES)).unwrap();

        // A list that is no list is set aside, and the program goes on with none
        std::fs::write(dir.join(DEVICES), "{ not json").unwrap();
        assert!(Devices::load(&dir).unwrap().paired.is_empty());
        assert_eq!(std::fs::read_to_string(dir.join("devices.json.bak")).unwrap(), "{ not json");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_leftover_temporary_file_decides_nothing() {
        let dir = folder("leftover");
        private_dir(&dir).unwrap();
        // A file of the same name as the temporary one, readable by everyone, and a link in its place
        let temporary = dir.join("secret.pem.new");
        std::fs::write(&temporary, "old").unwrap();
        std::fs::set_permissions(&temporary, std::fs::Permissions::from_mode(0o644)).unwrap();
        write_private(&dir.join("secret.pem"), b"the key").unwrap();
        assert_eq!(std::fs::metadata(dir.join("secret.pem")).unwrap().permissions().mode() & 0o777, 0o600);
        std::os::unix::fs::symlink("/tmp/amethystora-connect-elsewhere", &temporary).unwrap();
        write_private(&dir.join("secret.pem"), b"the key again").unwrap();
        assert_eq!(std::fs::read(dir.join("secret.pem")).unwrap(), b"the key again");
        assert!(!std::path::Path::new("/tmp/amethystora-connect-elsewhere").exists(), "the link was not followed");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn writes_leave_no_temporary_file_and_are_private() {
        let dir = folder("write");
        private_dir(&dir).unwrap();
        write_private(&dir.join("a"), b"one").unwrap();
        write_private(&dir.join("a"), b"two").unwrap();
        assert_eq!(std::fs::read(dir.join("a")).unwrap(), b"two");
        assert!(!dir.join("a.new").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
