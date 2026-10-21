//! Seals and opens the clipboard history of Amethystora Clipboard, the GNOME Shell extension, which has no
//! cipher of its own: GJS has none, and the shell is the compositor, where new cryptography does not belong.
//!
//!   amethystora-clipboard-seal new-key       a new key, base64, on stdout
//!   amethystora-clipboard-seal seal LABEL    stdin: the key's line, then the data; stdout: the data sealed
//!   amethystora-clipboard-seal open LABEL    stdin: the key's line, then what seal wrote; stdout: the data
//!
//! It only filters bytes: the key and the data come on stdin, never as arguments, which any process can
//! read, and it touches no file. The extension keeps the key in the login keyring and writes the files.
//!
//! Sealing is Notes' (apps/notes/src/vault.rs): AES-256-GCM under a random 256-bit key, a fresh 96-bit nonce
//! for every seal. A sealed file is `ACv1`, the nonce, then the ciphertext with its tag. The label, `history`
//! or `image`, is authenticated with it as `amethystora-clipboard:<label>`, so that a picture's file cannot
//! be passed off as the history.
//!
//! Exits 1 when what it was given does not open (a wrong key or label, or a damaged file), and 64 when it
//! was called wrongly.

use std::io::{Read, Write};
use std::process::ExitCode;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine;

const MAGIC: &[u8; 4] = b"ACv1";
const LABELS: [&str; 2] = ["history", "image"];

/// A 256-bit key, wiped when it is dropped
struct Key([u8; 32]);

impl Key {
    fn random() -> Key {
        let mut bytes = [0u8; 32];
        getrandom::fill(&mut bytes).expect("the kernel gives random bytes");
        Key(bytes)
    }

    /// Exactly 32 bytes, in standard base64
    fn from_base64(text: &[u8]) -> Option<Key> {
        let bytes = base64::engine::general_purpose::STANDARD.decode(text.trim_ascii()).ok()?;
        Some(Key(bytes.as_slice().try_into().ok()?))
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

fn aad(label: &str) -> Vec<u8> {
    format!("amethystora-clipboard:{label}").into_bytes()
}

fn seal(key: &Key, plain: &[u8], label: &str) -> Vec<u8> {
    let mut iv = [0u8; 12];
    getrandom::fill(&mut iv).expect("the kernel gives random bytes");
    let cipher = Aes256Gcm::new_from_slice(&key.0).expect("a 256-bit key");
    let nonce = Nonce::try_from(&iv[..]).expect("a 96-bit nonce");
    let aad = aad(label);
    let sealed = cipher.encrypt(&nonce, Payload { msg: plain, aad: &aad }).expect("AES-GCM seals anything that fits in memory");
    [&MAGIC[..], &iv[..], &sealed[..]].concat()
}

/// Fails on a wrong key or label, and on anything changed since it was sealed
fn open(key: &Key, bytes: &[u8], label: &str) -> Result<Vec<u8>, ()> {
    if bytes.len() < 32 || &bytes[..4] != MAGIC {
        return Err(());
    }
    let cipher = Aes256Gcm::new_from_slice(&key.0).map_err(|_| ())?;
    let nonce = Nonce::try_from(&bytes[4..16]).map_err(|_| ())?;
    let aad = aad(label);
    cipher.decrypt(&nonce, Payload { msg: &bytes[16..], aad: &aad }).map_err(|_| ())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let mut stdout = std::io::stdout().lock();
    match args.as_slice() {
        ["new-key"] => {
            let key = Key::random();
            let text = base64::engine::general_purpose::STANDARD.encode(key.0);
            if writeln!(stdout, "{text}").is_err() {
                return ExitCode::from(1);
            }
            ExitCode::SUCCESS
        }
        [verb @ ("seal" | "open"), label] if LABELS.contains(label) => {
            let mut input = Vec::new();
            if std::io::stdin().lock().read_to_end(&mut input).is_err() {
                return ExitCode::from(1);
            }
            let split = input.iter().position(|&b| b == b'\n').unwrap_or(input.len());
            let Some(key) = Key::from_base64(&input[..split]) else {
                eprintln!("amethystora-clipboard-seal: the first line of the input is not a key");
                return ExitCode::from(64);
            };
            let data = input.get(split + 1..).unwrap_or(&[]);
            let out = if *verb == "seal" { Ok(seal(&key, data, label)) } else { open(&key, data, label) };
            // The input held the data in the clear
            input.fill(0);
            match out {
                Ok(bytes) if stdout.write_all(&bytes).and_then(|_| stdout.flush()).is_ok() => ExitCode::SUCCESS,
                _ => ExitCode::from(1),
            }
        }
        _ => {
            eprintln!("usage: amethystora-clipboard-seal new-key | seal history|image | open history|image");
            ExitCode::from(64)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seals_and_opens() {
        let key = Key::random();
        let sealed = seal(&key, b"a copied password", "history");
        assert_eq!(open(&key, &sealed, "history").unwrap(), b"a copied password");
    }

    #[test]
    fn never_holds_the_text() {
        let key = Key::random();
        let sealed = seal(&key, b"plain marker text", "history");
        assert!(!sealed.windows(5).any(|w| w == b"plain"));
        // A fresh nonce every time
        assert_ne!(sealed, seal(&key, b"plain marker text", "history"));
    }

    #[test]
    fn refuses_a_wrong_key_label_or_change() {
        let key = Key::random();
        let sealed = seal(&key, b"data", "image");
        assert!(open(&Key::random(), &sealed, "image").is_err());
        assert!(open(&key, &sealed, "history").is_err());
        let mut changed = sealed.clone();
        *changed.last_mut().unwrap() ^= 1;
        assert!(open(&key, &changed, "image").is_err());
        assert!(open(&key, &sealed[..sealed.len() - 1], "image").is_err());
        assert!(open(&key, b"", "image").is_err());
    }

    #[test]
    fn seals_nothing_and_much() {
        let key = Key::random();
        assert_eq!(open(&key, &seal(&key, b"", "history"), "history").unwrap(), b"");
        let big = vec![7u8; 50 << 20];
        assert_eq!(open(&key, &seal(&key, &big, "image"), "image").unwrap(), big);
    }

    #[test]
    fn takes_only_a_whole_key() {
        assert!(Key::from_base64(b"AAAA").is_none());
        assert!(Key::from_base64(b"not base64 at all!").is_none());
        let text = base64::engine::general_purpose::STANDARD.encode([1u8; 32]);
        assert!(Key::from_base64(format!("{text}\r").as_bytes()).is_some());
    }
}
