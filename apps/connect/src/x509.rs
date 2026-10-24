//! This computer's certificate, and what the program reads out of a peer's.
//!
//! The certificate is self-signed X.509 version 3 on an ECDSA P-256 key, valid for ten years, with the device
//! id as its common name (spec-protocol.md 4.4). It is a few dozen lines of DER written here rather than a
//! certificate library: nothing about it but the signature needs a library. What is read from a peer's
//! certificate is only its public key (as the DER structure the verification key hashes) and its common name,
//! which is logged and never trusted.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use p256::ecdsa::signature::Signer;
use p256::ecdsa::{Signature, SigningKey};
use p256::pkcs8::{DecodePrivateKey, EncodePrivateKey, LineEnding};

pub struct Made {
    pub certificate_pem: String,
    pub key_pem: String,
}

/// What of a certificate the protocol uses
#[derive(Debug, PartialEq, Eq)]
pub struct Parts {
    /// The SubjectPublicKeyInfo structure, DER, as it stands in the certificate
    pub spki: Vec<u8>,
    pub common_name: Option<String>,
}

// --- Writing ----------------------------------------------------------------------------------------------

fn tlv(tag: u8, content: &[u8]) -> Vec<u8> {
    let mut out = vec![tag];
    match content.len() {
        n if n < 0x80 => out.push(n as u8),
        n if n <= 0xff => out.extend([0x81, n as u8]),
        n => out.extend([0x82, (n >> 8) as u8, n as u8]),
    }
    out.extend_from_slice(content);
    out
}

fn sequence(parts: &[&[u8]]) -> Vec<u8> {
    tlv(0x30, &parts.concat())
}

/// One attribute of a name: SET { SEQUENCE { OID, UTF8String } }
fn attribute(oid: &[u8], value: &str) -> Vec<u8> {
    tlv(0x31, &sequence(&[&tlv(0x06, oid), &tlv(0x0c, value.as_bytes())]))
}

const OID_CN: &[u8] = &[0x55, 0x04, 0x03];
const OID_O: &[u8] = &[0x55, 0x04, 0x0a];
const OID_OU: &[u8] = &[0x55, 0x04, 0x0b];
/// ecdsa-with-SHA256
const ALGORITHM: &[u8] = &[0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02];
/// id-ecPublicKey with prime256v1, then the BIT STRING header of an uncompressed point
const SPKI_HEADER: &[u8] = &[
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42,
    0x00,
];

/// Days since 1970-01-01 as a civil date (Howard Hinnant's algorithm)
fn civil(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

/// UTCTime, YYMMDDHHMMSSZ: good to 2049, which a ten-year certificate made before 2039 stays inside
fn utc_time(secs: i64) -> Vec<u8> {
    let (year, month, day) = civil(secs.div_euclid(86_400));
    let rest = secs.rem_euclid(86_400);
    let text = format!("{:02}{month:02}{day:02}{:02}{:02}{:02}Z", year % 100, rest / 3600, rest % 3600 / 60, rest % 60);
    tlv(0x17, text.as_bytes())
}

fn pem(label: &str, der: &[u8]) -> String {
    let body = STANDARD.encode(der);
    let mut out = format!("-----BEGIN {label}-----\n");
    for chunk in body.as_bytes().chunks(64) {
        out.push_str(std::str::from_utf8(chunk).unwrap_or(""));
        out.push('\n');
    }
    out.push_str(&format!("-----END {label}-----\n"));
    out
}

/// A key, and a certificate for it that names `device_id`, valid from a day ago for ten years
pub fn generate(device_id: &str, now: i64) -> Result<Made, String> {
    let key = loop {
        let mut secret = [0u8; 32];
        getrandom::fill(&mut secret).map_err(|e| format!("no random numbers: {e}"))?;
        // Zero, or not below the curve's order, is possible but for 1 in 2^32: try again
        if let Ok(key) = SigningKey::from_slice(&secret) {
            break key;
        }
    };
    let point = key.verifying_key().to_sec1_point(false);
    let spki = [SPKI_HEADER, point.as_bytes()].concat();

    let mut serial = [0u8; 16];
    getrandom::fill(&mut serial).map_err(|e| format!("no random numbers: {e}"))?;
    serial[0] = serial[0] & 0x7f | 0x01;

    let name = sequence(&[&attribute(OID_CN, device_id), &attribute(OID_O, "Amethystora"), &attribute(OID_OU, "Connect")]);
    let validity = sequence(&[&utc_time(now - 86_400), &utc_time(now + 3650 * 86_400)]);
    let tbs = sequence(&[
        &[0xa0, 0x03, 0x02, 0x01, 0x02], // version 3
        &tlv(0x02, &serial),
        ALGORITHM,
        &name,
        &validity,
        &name,
        &spki,
    ]);
    let signature: Signature = key.sign(&tbs);
    let signature = signature.to_der();
    let certificate = sequence(&[&tbs, ALGORITHM, &tlv(0x03, &[&[0u8][..], signature.as_bytes()].concat())]);

    let key_pem = key.to_pkcs8_pem(LineEnding::LF).map_err(|e| format!("cannot write the key: {e}"))?;
    Ok(Made { certificate_pem: pem("CERTIFICATE", &certificate), key_pem: key_pem.to_string() })
}

// --- Reading ----------------------------------------------------------------------------------------------

/// The first certificate of a PEM text, as DER
pub fn pem_to_der(text: &str) -> Option<Vec<u8>> {
    let start = text.find("-----BEGIN CERTIFICATE-----")? + "-----BEGIN CERTIFICATE-----".len();
    let end = start + text[start..].find("-----END CERTIFICATE-----")?;
    let body: String = text[start..end].chars().filter(|c| !c.is_whitespace()).collect();
    STANDARD.decode(body).ok()
}

pub fn der_to_pem(der: &[u8]) -> String {
    pem("CERTIFICATE", der)
}

/// One element of a DER string: tag, content, and the element as a whole
fn read(input: &[u8]) -> Option<(u8, &[u8], &[u8], &[u8])> {
    let (&tag, rest) = input.split_first()?;
    if tag & 0x1f == 0x1f {
        return None; // high tag numbers are not used in certificates
    }
    let (&first, rest) = rest.split_first()?;
    let (length, rest) = if first < 0x80 {
        (usize::from(first), rest)
    } else {
        let count = usize::from(first & 0x7f);
        if count == 0 || count > 3 || rest.len() < count {
            return None;
        }
        (rest[..count].iter().fold(0usize, |n, b| n << 8 | usize::from(*b)), &rest[count..])
    };
    if rest.len() < length {
        return None;
    }
    let consumed = input.len() - rest.len() + length;
    Some((tag, &rest[..length], &input[..consumed], &rest[length..]))
}

/// The public key and the common name of a DER certificate. `None` when it is not one this program can read
/// (it must be one SEQUENCE of a TBS SEQUENCE, a signature algorithm and a signature, with nothing after).
pub fn parts(der: &[u8]) -> Option<Parts> {
    let (0x30, certificate, _, trailing) = read(der)? else { return None };
    if !trailing.is_empty() {
        return None;
    }
    let (0x30, tbs, _, _) = read(certificate)? else { return None };
    let mut rest = tbs;
    let (tag, _, _, after) = read(rest)?;
    rest = if tag == 0xa0 { after } else { rest }; // the version, when there is one
    let (0x02, _, _, rest) = read(rest)? else { return None }; // serial
    let (0x30, _, _, rest) = read(rest)? else { return None }; // signature algorithm
    let (0x30, _, _, rest) = read(rest)? else { return None }; // issuer
    let (0x30, _, _, rest) = read(rest)? else { return None }; // validity
    let (0x30, subject, _, rest) = read(rest)? else { return None };
    let (0x30, _, spki, _) = read(rest)? else { return None };
    Some(Parts { spki: spki.to_vec(), common_name: common_name(subject) })
}

fn common_name(subject: &[u8]) -> Option<String> {
    let mut sets = subject;
    while !sets.is_empty() {
        let (tag, set, _, after) = read(sets)?;
        sets = after;
        if tag != 0x31 {
            continue;
        }
        let mut entries = set;
        while !entries.is_empty() {
            let (tag, entry, _, after) = read(entries)?;
            entries = after;
            if tag != 0x30 {
                continue;
            }
            let (0x06, oid, _, value) = read(entry)? else { continue };
            if oid != OID_CN {
                continue;
            }
            let (kind, text, _, _) = read(value)?;
            // UTF8String, PrintableString, T61String and IA5String are read as text; others are not names we use
            return matches!(kind, 0x0c | 0x13 | 0x14 | 0x16).then(|| String::from_utf8_lossy(text).into_owned());
        }
    }
    None
}

/// Whether a PKCS#8 private key in PEM is the private half of the public key `spki`
pub fn key_matches(key_pem: &str, spki: &[u8]) -> bool {
    let Ok(key) = SigningKey::from_pkcs8_pem(key_pem) else { return false };
    let point = key.verifying_key().to_sec1_point(false);
    [SPKI_HEADER, point.as_bytes()].concat() == spki
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "c3f1a8d27b5e4096a1d84f7e2b9c60d5";

    #[test]
    fn dates_are_civil() {
        assert_eq!(civil(0), (1970, 1, 1));
        assert_eq!(civil(19_723), (2024, 1, 1));
        assert_eq!(civil(11_016), (2000, 2, 29));
        // 2026-10-23 07:40:34 UTC
        assert_eq!(utc_time(1_792_741_234), tlv(0x17, b"261023074034Z"));
    }

    #[test]
    fn a_certificate_names_its_device_and_carries_its_key() {
        let made = generate(ID, 1_792_741_234).unwrap();
        let der = pem_to_der(&made.certificate_pem).unwrap();
        let parts = parts(&der).unwrap();
        assert_eq!(parts.common_name.as_deref(), Some(ID));
        assert_eq!(parts.spki.len(), 91);
        assert_eq!(&parts.spki[..SPKI_HEADER.len()], SPKI_HEADER);
        assert!(key_matches(&made.key_pem, &parts.spki));
        // Another key is not this certificate's
        let other = generate(ID, 1_792_741_234).unwrap();
        assert!(!key_matches(&other.key_pem, &parts.spki));
        assert!(!key_matches("not a key", &parts.spki));
        assert!(made.key_pem.starts_with("-----BEGIN PRIVATE KEY-----"));
    }

    #[test]
    fn der_round_trips_through_pem() {
        let made = generate(ID, 1_792_741_234).unwrap();
        let der = pem_to_der(&made.certificate_pem).unwrap();
        assert_eq!(der_to_pem(&der), made.certificate_pem);
    }

    #[test]
    fn what_is_not_a_certificate_is_refused() {
        assert_eq!(parts(b""), None);
        assert_eq!(parts(b"\x30\x03\x01\x01\x01"), None);
        let made = generate(ID, 1_792_741_234).unwrap();
        let der = pem_to_der(&made.certificate_pem).unwrap();
        let mut trailing = der.clone();
        trailing.push(0);
        assert_eq!(parts(&trailing), None);
        assert_eq!(parts(&der[..der.len() - 1]), None);
        assert_eq!(parts(&der[..40]), None);
        assert_eq!(pem_to_der("-----BEGIN CERTIFICATE-----\n!!!\n-----END CERTIFICATE-----\n"), None);
    }
}
