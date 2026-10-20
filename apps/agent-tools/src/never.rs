//! What the agent may never run, whoever allows it: the tools refuse it before a terminal opens, and the root
//! helper refuses it again as root. The agent names such a command, and the user runs it.
//!
//! An argument vector is judged as it is, so a program that would run another one out of sight of this list
//! (a shell, an interpreter given code, a wrapper such as env or systemd-run) is refused too: the agent runs
//! each step as a command of its own instead.

/// Commands of `ame security` the agent may hand over: those that read, and those that turn protection on.
/// Anything that loosens it or sends something away is the user's to run.
const SECURITY_READS: &[&str] = &["status", "events", "apps", "connections", "addresses", "audit", "home-networks"];
/// Switches whose `on` tightens what the image enforces or adds a watch
const SECURITY_ON: &[&str] = &[
    "app-sandbox", "audit-locked", "block-automount", "block-bluetooth", "block-user-extensions", "block-webcam",
    "block-xwayland", "blocked-modules", "bluetooth-privacy", "brew-attestations", "browser", "failed-logins", "firewall",
    "firewall-away", "firewire", "flathub-verified", "flatpak-password", "ipv6-privacy", "locked-poweroff", "lockout", "mac",
    "network-daemons", "no-coredumps", "noexec-temp", "package-cooldown", "ransomware", "signed-updates", "ssh-settings",
    "time", "usb", "virtual-input", "vscodium-extensions",
];

/// Programs that run other code the list cannot see
const RUNNERS: &[&str] = &[
    "sh", "bash", "dash", "zsh", "fish", "ksh", "csh", "tcsh", "busybox", "env", "xargs", "nohup", "setsid", "timeout",
    "nice", "ionice", "chroot", "systemd-run", "run0", "runuser", "setpriv", "unshare", "nsenter", "flock", "stdbuf",
    "script", "sudo", "su", "pkexec", "doas", "watch", "parallel", "expect", "tmux", "screen", "eval", "exec", "strace",
    "gdb", "ltrace",
];
/// Interpreters, refused when given code on the command line rather than a file
const INTERPRETERS: &[&str] = &["python", "python3", "perl", "ruby", "node", "lua", "php", "awk", "gawk", "osascript", "gjs"];

/// Paths no command of the agent's may name: who may become root, the agent's own lock, the duress
/// feature's files, and the notes
const PATHS: &[&str] = &[
    "/etc/sudoers", "/etc/polkit-1", "/usr/share/polkit-1", "/etc/amethystora/agent.conf", "/etc/pam.d", "/etc/authselect",
    "/etc/security", "amethystora-notes", "/etc/shadow", "/etc/gshadow",
];

fn base(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

/// Why `argv` is refused, or None when it may be handed over
pub fn refusal(argv: &[String]) -> Option<String> {
    let Some(first) = argv.first() else {
        return Some("there is nothing to run".into());
    };
    let program = base(first);
    let lower: Vec<String> = argv.iter().map(|arg| arg.to_lowercase()).collect();
    if lower.iter().any(|arg| arg.contains("duress")) {
        return Some("it is about the duress feature, which is the user's alone".into());
    }
    if let Some(path) = PATHS.iter().find(|path| argv.iter().any(|arg| arg.contains(*path))) {
        return Some(format!("it names {path}, which the agent may never change"));
    }
    if program.starts_with("amethystora-agent") {
        return Some("the agent may not run its own tools or change its own lock or root mode".into());
    }
    if RUNNERS.contains(&program) {
        return Some(format!("{program} would run other commands out of sight; run each command on its own"));
    }
    let interpreter = program.trim_end_matches(|c: char| c.is_ascii_digit() || c == '.');
    if INTERPRETERS.contains(&program) || INTERPRETERS.contains(&interpreter) {
        if argv.iter().skip(1).any(|arg| matches!(arg.as_str(), "-c" | "-e" | "-E" | "--eval" | "-r" | "-p" | "--print") || arg.starts_with("-c")) {
            return Some(format!("{program} given code on its command line runs out of sight; save it as a file the user can read"));
        }
    }
    if matches!(program, "visudo" | "passwd" | "chpasswd" | "usermod" | "gpasswd" | "useradd" | "groupmod" | "authselect" | "cryptsetup") {
        return Some(format!("{program} changes who may log in or become root, or a disk's keys: the user runs it"));
    }
    if program == "restic" && argv.iter().any(|arg| matches!(arg.as_str(), "forget" | "prune" | "key" | "rewrite")) {
        return Some("it deletes from the backup, which nothing on this machine does".into());
    }
    if program == "btrfs" && argv.windows(2).any(|pair| pair[0] == "subvolume" && pair[1] == "delete") {
        return Some("it deletes a subvolume, and with it maybe a snapshot".into());
    }
    if program == "amethystora-raid" && argv.get(1).map(String::as_str) != Some("status") {
        return Some("pools of disks are made, changed and erased only by the user, in a terminal".into());
    }
    if matches!(program, "ame" | "ujust") {
        return ame_refusal(&argv[1..]);
    }
    if program.starts_with("amethystora-security") || program == "amethystora-hardening" {
        return Some("security switches are changed only through ame security, and only to turn protection on".into());
    }
    None
}

fn ame_refusal(args: &[String]) -> Option<String> {
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match args.as_slice() {
        ["agent", "lock" | "root", ..] => Some("the agent may not change its own lock or root mode".into()),
        ["agent", "tools" | "toggle", "on", ..] => Some("only the user turns the agent's levels on".into()),
        ["apps", "aur", ..] => Some("turning the AUR on is the user's choice alone".into()),
        ["system", "raid", rest @ ..] if rest.first() != Some(&"status") => {
            Some("pools of disks are made, changed and erased only by the user, in a terminal".into())
        }
        ["security", rest @ ..] => security_refusal(rest),
        _ => None,
    }
}

/// `ame security` only reads, or turns protection on
fn security_refusal(args: &[&str]) -> Option<String> {
    let allowed = match args {
        [] => true,
        [command] => SECURITY_READS.contains(command) || *command == "scan" || *command == "app-integrity",
        ["scan", "now"] | ["app-integrity", "status" | "check"] => true,
        ["kernel", "standard" | "strict"] | ["lockdown", "on" | "strict"] => true,
        [switch, "on"] => SECURITY_ON.contains(switch),
        ["profile", "light" | "balanced" | "thorough"] => true,
        ["kernel-args", argument, "on"] => argument.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '=' | '-')),
        // A resolver of the list, or resuming after a pause; custom asks its servers in a terminal
        ["dns", "quad9" | "mullvad" | "cloudflare" | "google" | "resume"] => true,
        _ => false,
    };
    if allowed {
        None
    } else {
        Some("this security command does not turn protection on: the agent names it, and the user runs it".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn argv(words: &str) -> Vec<String> {
        words.split(' ').map(str::to_string).collect()
    }

    #[test]
    fn refuses_the_never_list() {
        for words in [
            "ame security duress setup",
            "cat /etc/amethystora/duress.d/fingers",
            "tee /etc/sudoers.d/agent",
            "cp rule /etc/polkit-1/rules.d/00.rules",
            "sed -i s/act/off/ /etc/amethystora/agent.conf",
            "ame agent lock act",
            "ame agent root each",
            "ame agent tools on",
            "ame apps aur on",
            "ame security firewall off",
            "ame security settings osprey on",
            "ame security settings triage on",
            "ame security allow report",
            "ame security profile off",
            "ame security lockdown off",
            "ame security dns pause",
            "ame security dns off",
            "ame system raid create",
            "amethystora-raid create",
            "restic -r x forget --prune",
            "btrfs subvolume delete /var/home/.snapshots/x",
            "bash -c id",
            "env FOO=1 rm -rf /",
            "python3 -c print(1)",
            "systemd-run --pty bash",
            "sudo rm x",
            "rm -rf /var/home/a/.local/share/amethystora-notes",
            "/usr/libexec/amethystora-hardening off firewall",
            "amethystora-agent-root session",
            "passwd root",
        ] {
            assert!(refusal(&argv(words)).is_some(), "{words}");
        }
    }

    #[test]
    fn hands_over_the_rest() {
        for words in [
            "rpm-ostree install htop",
            "systemctl restart NetworkManager.service",
            "ame security firewall on",
            "ame security status",
            "ame security scan now",
            "ame security kernel strict",
            "ame security lockdown on",
            "ame security profile balanced",
            "ame security kernel-args init_on_free=1 on",
            "ame security dns quad9",
            "ame system raid status",
            "ame system rebase amethystora stable",
            "python3 /home/a/fix.py",
            "bootc rollback",
            "flatpak override --user --socket=x11 com.example.App",
        ] {
            assert_eq!(refusal(&argv(words)), None, "{words}");
        }
        assert!(refusal(&[]).is_some());
    }
}
