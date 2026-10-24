//! A TLS library that cannot take this computer's certificate is not a reason to forget the phones paired with it:
//! the program says so and does not start, and the files are as they were. A process of its own, because the TLS backend is
//! chosen once, from the environment, the first time GIO is used.

use amethystora_connect::{store, x509};

#[test]
fn a_certificate_the_library_cannot_load_is_kept_and_so_are_the_pairings() {
    // SAFETY: the only test of this process, before anything has used GIO
    unsafe {
        std::env::set_var("GIO_USE_TLS", "dummy");
    }
    let dir = std::env::temp_dir().join(format!("amethystora-connect-no-tls-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    store::private_dir(&dir).unwrap();
    let made = x509::generate(&"a".repeat(32), 1_792_741_234).unwrap();
    std::fs::write(dir.join("certificate.pem"), &made.certificate_pem).unwrap();
    std::fs::write(dir.join("private-key.pem"), &made.key_pem).unwrap();
    std::fs::write(dir.join("devices.json"), "{\"version\":1,\"devices\":{}}").unwrap();

    let error = store::load_material(&dir, 1_792_741_234).err().expect("the program does not start");
    assert!(error.contains("TLS") && error.contains("nothing was changed"), "{error}");
    assert_eq!(std::fs::read_to_string(dir.join("certificate.pem")).unwrap(), made.certificate_pem, "the certificate is the same");
    assert_eq!(std::fs::read_to_string(dir.join("private-key.pem")).unwrap(), made.key_pem);
    assert!(dir.join("devices.json").exists() && !dir.join("devices.json.bak").exists(), "the pairings are where they were");
    // And again: it does not turn into a new identity at each start
    assert!(store::load_material(&dir, 1_792_741_234).is_err());
    assert_eq!(std::fs::read_to_string(dir.join("certificate.pem")).unwrap(), made.certificate_pem);
    let _ = std::fs::remove_dir_all(&dir);
}
