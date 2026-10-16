//! Sealing, as main.js did it, byte for byte, so that a vault written by either window opens in the other.
//!
//! Encryption is AES-256-GCM under a random 256-bit key, and that key is sealed the same way under one
//! derived from the passphrase with scrypt, so a new passphrase can rewrap the key and nothing else. None of
//! it is public-key cryptography, the kind a quantum computer breaks: against AES, Grover's algorithm at
//! best halves the key length, which leaves a 256-bit key at the 128-bit level, and is why AES-256 is what
//! NIST and CNSA 2.0 keep for the post-quantum era. The passphrase is the weak point, so scrypt is set to
//! cost 128 MiB and a good part of a second for every guess.
//!
//! A sealed file is `ANv1`, a fresh 96-bit nonce, the 128-bit tag, then the ciphertext. The label, as
//! `amethystora-notes:<label>`, is authenticated with it, so a sealed file cannot be passed off as another:
//! an attachment as the notes, or one attachment as another. The labels are `key` (the data key in
//! vault.json), `data`, `resource:<id>`, `passkey:<id>` and `backup`.

use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine;
use serde_json::{json, Value};

use amethystora_ui::t;

pub const MAGIC: &[u8; 4] = b"ANv1";

/// 128 * N * r bytes of memory for every guess at the passphrase
pub const KDF_N: u64 = 1 << 17;
pub const KDF_R: u32 = 8;
pub const KDF_P: u32 = 1;

/// Random bytes from the kernel, as crypto.randomBytes
pub fn random(out: &mut [u8]) {
    getrandom::fill(out).expect("the kernel gives random bytes");
}

pub fn base64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// Buffer.from(text, 'base64'): what it can make of the text, which never fails, as Node's never did
pub fn unbase64(text: &str) -> Vec<u8> {
    let clean: String = text.chars().filter(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '/' | '-' | '_')).collect();
    let clean = clean.replace('-', "+").replace('_', "/");
    // Node stops at the first character that is not base64 and takes what it has: so does this, padding
    // the rest
    let usable = clean.len() - clean.len() % 4;
    let tail = &clean[usable..];
    let padded = match tail.len() {
        2 => format!("{}{tail}==", &clean[..usable]),
        3 => format!("{}{tail}=", &clean[..usable]),
        _ => clean[..usable].to_string(),
    };
    base64::engine::general_purpose::STANDARD.decode(padded).unwrap_or_default()
}

/// A 256-bit key, wiped when it is dropped, as main.js did `key.fill(0)`
pub struct Key([u8; 32]);

impl Key {
    pub fn new(bytes: [u8; 32]) -> Key {
        Key(bytes)
    }

    pub fn random() -> Key {
        let mut bytes = [0u8; 32];
        random(&mut bytes);
        Key(bytes)
    }

    /// A key of exactly 32 bytes
    pub fn from_slice(bytes: &[u8]) -> Option<Key> {
        let array: [u8; 32] = bytes.try_into().ok()?;
        Some(Key(array))
    }

    pub fn bytes(&self) -> &[u8; 32] {
        &self.0
    }

    pub fn copy(&self) -> Key {
        Key(self.0)
    }
}

impl Drop for Key {
    fn drop(&mut self) {
        for byte in self.0.iter_mut() {
            // SAFETY: a byte of an array this owns
            unsafe { std::ptr::write_volatile(byte, 0) };
        }
    }
}

impl std::fmt::Debug for Key {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Key(…)")
    }
}

fn aad(label: &str) -> Vec<u8> {
    format!("amethystora-notes:{label}").into_bytes()
}

/// MAGIC, a fresh 96-bit nonce, the tag, then the ciphertext
pub fn seal(secret: &Key, plain: &[u8], label: &str) -> Vec<u8> {
    let mut iv = [0u8; 12];
    random(&mut iv);
    seal_with(secret, &iv, plain, label)
}

fn seal_with(secret: &Key, iv: &[u8; 12], plain: &[u8], label: &str) -> Vec<u8> {
    let cipher = Aes256Gcm::new_from_slice(secret.bytes()).expect("a 256-bit key");
    let nonce = Nonce::try_from(&iv[..]).expect("a 96-bit nonce");
    let aad = aad(label);
    // The crate puts the tag after the ciphertext; the file has it before
    let sealed = cipher.encrypt(&nonce, Payload { msg: plain, aad: &aad }).expect("AES-GCM seals anything that fits in memory");
    let (body, tag) = sealed.split_at(sealed.len() - 16);
    let mut out = Vec::with_capacity(32 + body.len());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(iv);
    out.extend_from_slice(tag);
    out.extend_from_slice(body);
    out
}

pub fn is_sealed(bytes: &[u8]) -> bool {
    bytes.len() >= 32 && &bytes[..4] == MAGIC
}

/// Fails on a wrong key and on anything changed since it was sealed
pub fn unseal(secret: &Key, bytes: &[u8], label: &str) -> Result<Vec<u8>, ()> {
    if !is_sealed(bytes) {
        return Err(());
    }
    let cipher = Aes256Gcm::new_from_slice(secret.bytes()).map_err(|_| ())?;
    let nonce = Nonce::try_from(&bytes[4..16]).map_err(|_| ())?;
    let mut joined = Vec::with_capacity(bytes.len() - 16);
    joined.extend_from_slice(&bytes[32..]);
    joined.extend_from_slice(&bytes[16..32]);
    let aad = aad(label);
    cipher.decrypt(&nonce, Payload { msg: &joined, aad: &aad }).map_err(|_| ())
}

/// The key settings of a vault.json, bounded, so that a damaged one cannot ask for all the memory there is
#[derive(Debug, Clone, PartialEq)]
pub struct Kdf {
    pub log_n: u8,
    pub r: u32,
    pub p: u32,
    pub salt: Vec<u8>,
}

impl Kdf {
    pub fn read(kdf: Option<&Value>) -> Result<Kdf, String> {
        let damaged = || t!("The key settings in vault.json are damaged.");
        let kdf = kdf.ok_or_else(damaged)?;
        let number = |name: &str| kdf.get(name).and_then(Value::as_f64);
        let (Some(n), Some(r), Some(p)) = (number("N"), number("r"), number("p")) else { return Err(damaged()) };
        let log = n.log2();
        let salt = kdf.get("salt").and_then(Value::as_str);
        if kdf.get("name").and_then(Value::as_str) != Some("scrypt")
            || log.fract() != 0.0
            || !(14.0..=20.0).contains(&log)
            || !(1.0..=16.0).contains(&r)
            || !(1.0..=4.0).contains(&p)
            || r.fract() != 0.0
            || p.fract() != 0.0
            || salt.is_none()
        {
            return Err(damaged());
        }
        Ok(Kdf { log_n: log as u8, r: r as u32, p: p as u32, salt: unbase64(salt.unwrap_or("")) })
    }

    /// The settings a new vault.json gets, with a fresh salt
    pub fn fresh() -> Kdf {
        let mut salt = [0u8; 16];
        random(&mut salt);
        Kdf { log_n: 17, r: KDF_R, p: KDF_P, salt: salt.to_vec() }
    }

    pub fn to_value(&self) -> Value {
        json!({ "name": "scrypt", "N": 1u64 << self.log_n, "r": self.r, "p": self.p, "salt": base64(&self.salt) })
    }
}

/// The key the passphrase gives under these settings: scrypt of its NFC form, 32 bytes. Slow on purpose:
/// call it away from the window's thread.
pub fn derive(passphrase: &str, kdf: &Kdf) -> Key {
    let normal = amethystora_ui::glib::normalize(passphrase, amethystora_ui::glib::NormalizeMode::DefaultCompose);
    let params = scrypt::Params::new(kdf.log_n, kdf.r, kdf.p).expect("bounded settings");
    let mut out = [0u8; 32];
    scrypt::scrypt(normal.as_bytes(), &kdf.salt, &params, &mut out).expect("32 bytes is a valid length");
    let key = Key(out);
    out.fill(0);
    key
}

/// A vault.json for this key under this passphrase
pub fn wrap(passphrase: &str, secret: &Key) -> Value {
    let kdf = Kdf::fresh();
    let kek = derive(passphrase, &kdf);
    json!({
        "format": 1,
        "encrypted": true,
        "cipher": "aes-256-gcm",
        "kdf": kdf.to_value(),
        "key": base64(&seal(&kek, secret.bytes(), "key")),
    })
}

/// The data key, or None for a wrong passphrase; an error for settings that are damaged
pub fn unwrap(passphrase: &str, vault: &Value) -> Result<Option<Key>, String> {
    let kdf = Kdf::read(vault.get("kdf"))?;
    let kek = derive(passphrase, &kdf);
    let sealed = unbase64(vault.get("key").and_then(Value::as_str).unwrap_or(""));
    Ok(unseal(&kek, &sealed, "key").ok().and_then(|bytes| Key::from_slice(&bytes)))
}

// --- Files -------------------------------------------------------------------------------------------------

/// Written beside the file and renamed over it, so a file is only ever the old one or the new one. With
/// keep, the old one stays as .bak.
pub fn write_atomic(file: &Path, bytes: &[u8], keep: bool) -> std::io::Result<()> {
    let mut temporary = file.as_os_str().to_owned();
    temporary.push(".tmp");
    let temporary = std::path::PathBuf::from(temporary);
    {
        let mut handle = fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&temporary)?;
        handle.write_all(bytes)?;
        handle.sync_all()?;
    }
    if keep {
        let mut backup = file.as_os_str().to_owned();
        backup.push(".bak");
        let _ = fs::rename(file, backup);
    }
    fs::rename(&temporary, file)
}

pub fn remove_quiet(files: &[&Path]) {
    for file in files {
        let _ = fs::remove_file(file);
    }
}

/// JSON.stringify(value, null, 2), as vault.json is written
pub fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seals_and_unseals() {
        let key = Key::random();
        let sealed = seal(&key, b"hello", "data");
        assert_eq!(&sealed[..4], b"ANv1");
        assert_eq!(sealed.len(), 32 + 5);
        assert_eq!(unseal(&key, &sealed, "data").unwrap(), b"hello");
        // The label is part of what is sealed
        assert!(unseal(&key, &sealed, "resource:x").is_err());
        assert!(unseal(&Key::random(), &sealed, "data").is_err());
        let mut changed = sealed.clone();
        changed[34] ^= 1;
        assert!(unseal(&key, &changed, "data").is_err());
        assert!(!is_sealed(b"{\"version\":1}"));
    }

    #[test]
    fn matches_node_for_a_known_nonce() {
        // crypto.createCipheriv('aes-256-gcm', Buffer.alloc(32, 1), Buffer.alloc(12, 2)) with the AAD
        // 'amethystora-notes:data', on 'hello', laid out as main.js's seal() did: Node printed this
        let sealed = seal_with(&Key::new([1; 32]), &[2; 12], b"hello", "data");
        assert_eq!(hex(&sealed), "414e7631020202020202020202020202c964f997bf588859d760f0689fc0ddfa6fb3a52525");
        assert_eq!(unseal(&Key::new([1; 32]), &sealed, "data").unwrap(), b"hello");
    }

    #[test]
    fn derives_as_node() {
        // crypto.scryptSync('páss'.normalize('NFC'), Buffer.alloc(16, 3), 32, { N: 2 ** 14, r: 8, p: 1 }):
        // the passphrase is composed first, so "pás" typed either way opens the same notes
        let kdf = Kdf { log_n: 14, r: 8, p: 1, salt: vec![3; 16] };
        assert_eq!(hex(derive("pa\u{301}ss", &kdf).bytes()), "f23a2d0c3d4f165a21982114b7dccaf873f4a05c149c309dbd4743994d44bec6");
        assert_eq!(hex(derive("p\u{e1}ss", &kdf).bytes()), "f23a2d0c3d4f165a21982114b7dccaf873f4a05c149c309dbd4743994d44bec6");
    }

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn reads_base64_as_node() {
        assert_eq!(unbase64("aGVsbG8="), b"hello");
        assert_eq!(unbase64("aGVsbG8"), b"hello");
        assert_eq!(unbase64("aGVs bG8=\n"), b"hello");
        assert_eq!(unbase64("aGVs!bG8="), b"hello");
        assert!(unbase64("").is_empty());
    }

    #[test]
    fn bounds_the_key_settings() {
        let good = json!({ "name": "scrypt", "N": 131072, "r": 8, "p": 1, "salt": "AAAA" });
        assert_eq!(Kdf::read(Some(&good)).unwrap().log_n, 17);
        for bad in [
            json!({ "name": "scrypt", "N": 131073, "r": 8, "p": 1, "salt": "AAAA" }),
            json!({ "name": "scrypt", "N": 1u64 << 21, "r": 8, "p": 1, "salt": "AAAA" }),
            json!({ "name": "scrypt", "N": 1u64 << 13, "r": 8, "p": 1, "salt": "AAAA" }),
            json!({ "name": "scrypt", "N": 131072, "r": 17, "p": 1, "salt": "AAAA" }),
            json!({ "name": "scrypt", "N": 131072, "r": 8, "p": 5, "salt": "AAAA" }),
            json!({ "name": "argon2", "N": 131072, "r": 8, "p": 1, "salt": "AAAA" }),
            json!({ "name": "scrypt", "N": 131072, "r": 8, "p": 1 }),
        ] {
            assert!(Kdf::read(Some(&bad)).is_err(), "{bad}");
        }
        assert!(Kdf::read(None).is_err());
    }
}
