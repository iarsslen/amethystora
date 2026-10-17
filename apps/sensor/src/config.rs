//! Reading the one security config through its only reader, amethystora-security-config, so the sensor sees
//! a switch exactly as every other part of the image does.

use std::process::Command;

const CONFIG: &str = "/usr/libexec/amethystora-security-config";

/// Whether KEY is set to VALUE (its --is, which an ExecCondition= uses). A stand-in reader for the tests is
/// taken from AMETHYSTORA_SECURITY_CONFIG.
pub fn is(key: &str, value: &str) -> bool {
    Command::new(reader())
        .args(["--is", key, value])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn reader() -> String {
    std::env::var("AMETHYSTORA_SECURITY_CONFIG").unwrap_or_else(|_| CONFIG.to_string())
}
