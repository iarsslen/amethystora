//! The `state` tool: the machine's state on one topic, in few words, problems first. Each topic is a
//! projection of a helper that already answers it (the rule the apps follow): nothing here works out state of
//! its own. What a helper prints that somebody else wrote (an app's name, a unit's description) is cleaned.

use std::time::Duration;

use serde_json::Value;

use crate::history::ago;
use crate::policy::Policy;
use crate::run::{self, Cache};
use crate::text;

pub const TOPICS: [&str; 13] = [
    "overview", "health", "settings", "security", "security-settings", "app-permissions", "software", "updates", "backups", "disks",
    "setup-diff", "units", "crashes",
];

const LONG: Duration = Duration::from_secs(120);
const SHORT: Duration = Duration::from_secs(20);

fn json(cache: &Cache, argv: &[&str], timeout: Duration) -> Result<Value, String> {
    let output = cache.run(argv, timeout);
    serde_json::from_str(&output.stdout).map_err(|_| {
        let said = text::field(output.stderr.trim(), 300);
        if said.is_empty() { format!("{} said nothing it could read", argv[0]) } else { format!("{}: {said}", argv[0]) }
    })
}

fn s(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}

pub fn topic(cache: &Cache, topic: &str, filter: &str) -> Result<String, String> {
    match topic {
        "overview" => Ok(overview(cache)),
        "health" => health(cache, filter),
        "settings" => settings(cache, filter),
        "security" => security(cache, filter),
        "security-settings" => security_settings(cache, filter),
        "app-permissions" => app_permissions(cache, filter),
        "software" => Ok(software(cache)),
        "updates" => Ok(updates(cache)),
        "backups" => backups(cache),
        "disks" => disks(cache),
        "setup-diff" => setup_diff(cache),
        "units" => Ok(units(cache, filter)),
        "crashes" => Ok(crashes(cache)),
        _ => Err(format!("no such topic: {topic}. Topics: {}", TOPICS.join(", "))),
    }
}

// --- overview ---------------------------------------------------------------------------------------------

fn failed_units(cache: &Cache, user: bool) -> Vec<String> {
    let mut argv = vec!["systemctl", "--failed", "--plain", "--no-legend", "--no-pager"];
    if user {
        argv.insert(1, "--user");
    }
    cache.run(&argv, SHORT).stdout.lines().filter_map(|line| line.split_whitespace().next()).map(|unit| text::field(unit, 120)).collect()
}

fn deployments(cache: &Cache) -> Vec<String> {
    let Ok(status) = json(cache, &["/usr/libexec/amethystora-deployments"], SHORT) else {
        return vec!["Deployments: could not be read".into()];
    };
    let mut lines = Vec::new();
    let mut layered: Vec<String> = Vec::new();
    for (n, deployment) in status["deployments"].as_array().into_iter().flatten().enumerate() {
        let role = if deployment["staged"] == true {
            "staged"
        } else if deployment["booted"] == true {
            "booted"
        } else if n == 0 {
            "default"
        } else {
            "rollback"
        };
        let when = deployment["timestamp"].as_u64().map(|t| format!(", built {} ago", ago(t))).unwrap_or_default();
        lines.push(format!("{role} {}{when}", s(&deployment["version"])));
        if deployment["booted"] == true {
            for key in ["requested-packages", "requested-local-packages"] {
                layered.extend(deployment[key].as_array().into_iter().flatten().filter_map(Value::as_str).map(str::to_string));
            }
        }
    }
    let mut out = vec![format!("Deployments: {}", lines.join("; "))];
    // The default is the first one that is not staged; started from another, the machine runs an older one
    let list = status["deployments"].as_array().cloned().unwrap_or_default();
    if list.iter().any(|d| d["booted"] == true) && list.iter().find(|d| d["staged"] != true).is_some_and(|d| d["booted"] != true) {
        out.push("Problem: started from an older deployment than the default (keep it with `sudo bootc rollback`)".into());
    }
    out.push(if layered.is_empty() {
        "Layered packages: none".into()
    } else {
        format!("Layered packages: {} (updates go through rpm-ostree, slower, and kargs.d changes do not reach this machine)", layered.join(", "))
    });
    out
}

fn memory() -> String {
    let info = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let field = |name: &str| {
        info.lines().find_map(|line| line.strip_prefix(name)?.trim().strip_suffix(" kB")?.trim().parse::<u64>().ok()).unwrap_or(0)
    };
    let gib = |kib: u64| format!("{:.1}G", kib as f64 / 1048576.0);
    format!(
        "Memory: {} of {} available; swap {} of {} used",
        gib(field("MemAvailable:")),
        gib(field("MemTotal:")),
        gib(field("SwapTotal:").saturating_sub(field("SwapFree:"))),
        gib(field("SwapTotal:"))
    )
}

fn secure_boot() -> String {
    let path = "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c";
    match std::fs::read(path) {
        Ok(bytes) if bytes.get(4) == Some(&1) => "Secure Boot: on".into(),
        Ok(_) => "Secure Boot: off".into(),
        Err(_) if std::path::Path::new("/sys/firmware/efi").exists() => "Secure Boot: unknown".into(),
        Err(_) => "Secure Boot: no UEFI (legacy boot)".into(),
    }
}

fn gpus() -> String {
    let mut found = Vec::new();
    let Ok(entries) = std::fs::read_dir("/sys/class/drm") else { return "GPU: none found".into() };
    let mut names: Vec<String> = entries.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    names.sort();
    for name in names.iter().filter(|name| name.starts_with("card") && !name.contains('-')) {
        let device = format!("/sys/class/drm/{name}/device");
        let vendor = std::fs::read_to_string(format!("{device}/vendor")).unwrap_or_default();
        let maker = match vendor.trim() {
            "0x10de" => "NVIDIA",
            "0x8086" => "Intel",
            "0x1002" => "AMD",
            "0x1af4" | "0x1234" | "0x15ad" | "0x80ee" => "virtual",
            other => other,
        };
        let driver = std::fs::read_link(format!("{device}/driver"))
            .ok()
            .and_then(|path| path.file_name().map(|name| name.to_string_lossy().into_owned()))
            .unwrap_or_else(|| "no driver".into());
        found.push(format!("{maker} ({driver})"));
    }
    if found.is_empty() { "GPU: none found".into() } else { format!("GPU: {}", found.join(", ")) }
}

fn df(cache: &Cache, paths: &[&str]) -> Vec<String> {
    let mut argv = vec!["df", "-h", "--output=target,size,used,avail,pcent"];
    argv.extend(paths);
    let mut seen = Vec::new();
    cache
        .run(&argv, SHORT)
        .stdout
        .lines()
        .skip(1)
        .filter_map(|line| {
            let f: Vec<&str> = line.split_whitespace().collect();
            if f.len() < 5 || seen.contains(&f[0].to_string()) {
                return None;
            }
            seen.push(f[0].to_string());
            Some(format!("{} {} used of {} ({} free)", f[0], f[4], f[1], f[3]))
        })
        .collect()
}

pub fn overview(cache: &Cache) -> String {
    let info: Value = std::fs::read(crate::IMAGE_INFO).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or(Value::Null);
    let sealed = std::path::Path::new("/usr/share/amethystora/sealed").exists();
    let mut out = vec![format!(
        "Image: {}:{} ({} flavor), Fedora {}, {}",
        s(&info["image-name"]),
        s(&info["image-tag"]),
        s(&info["image-flavor"]),
        s(&info["fedora-version"]),
        if sealed { "sealed (no rpm-ostree, kernel arguments fixed)" } else { "not sealed" }
    )];
    out.extend(deployments(cache));
    let system = failed_units(cache, false);
    let user = failed_units(cache, true);
    out.push(format!(
        "Failed units: system: {}; user: {}",
        if system.is_empty() { "none".into() } else { system.join(", ") },
        if user.is_empty() { "none".into() } else { user.join(", ") }
    ));
    out.push(format!("Disk: {}", df(cache, &["/", "/var", "/var/home"]).join("; ")));
    out.push(memory());
    out.push(secure_boot());
    out.push(gpus());
    let policy = Policy::current();
    out.push(format!(
        "Agent: level {} for {} (most allowed: {}), root commands: {}",
        policy.level().word(),
        text::field(&policy.account, 64),
        policy.ceiling().word(),
        policy.conf.root.word()
    ));
    out.join("\n")
}

// --- health -----------------------------------------------------------------------------------------------

fn health(cache: &Cache, filter: &str) -> Result<String, String> {
    let mut argv = vec![crate::DOCTOR, "--json"];
    if !filter.is_empty() {
        argv.extend(["--only", filter]);
    }
    let report = json(cache, &argv, LONG)?;
    let findings = report["findings"].as_array().cloned().unwrap_or_default();
    if findings.is_empty() {
        return Ok("Nothing wrong found.".into());
    }
    let mut lines: Vec<String> = findings
        .iter()
        .map(|f| {
            let playbook = f["playbook"].as_str().map(|p| format!(" (read playbook/{p})")).unwrap_or_default();
            format!("{} {}: {}{playbook}", s(&f["level"]), s(&f["id"]), text::field(s(&f["evidence"]), 300))
        })
        .collect();
    lines.sort_by_key(|line| !line.starts_with("problem"));
    Ok(lines.join("\n"))
}

// --- settings ---------------------------------------------------------------------------------------------

fn settings(cache: &Cache, filter: &str) -> Result<String, String> {
    let output = cache.run(&[amethystora_control_core::LIST, "--json"], LONG);
    let list = amethystora_control_core::parse_list(&output.stdout).ok_or("Control's list could not be read")?;
    let filter = filter.to_lowercase();
    let mut lines = Vec::new();
    for item in &list.items {
        if item.kind == "link" {
            continue;
        }
        let words = format!("{} {} {} {}", item.id, item.page, item.title, item.text.as_deref().unwrap_or("")).to_lowercase();
        if !filter.is_empty() && !words.contains(&filter) {
            continue;
        }
        let mut line = format!("{} [{}] {}", item.id, item.page, item.title);
        if let Some(state) = &item.state {
            line.push_str(&format!(": {}", text::field(state, 80)));
        }
        if !item.choices.is_empty() && !matches!(item.kind.as_str(), "themes" | "wallpapers") {
            let values: Vec<String> =
                item.choices.iter().map(|c| if c.terminal { format!("{}*", c.value) } else { c.value.clone() }).collect();
            line.push_str(&format!(" (values: {})", values.join("|")));
        } else if !item.choices.is_empty() {
            line.push_str(&format!(" ({} values)", item.choices.len()));
        }
        if item.kind == "range" {
            line.push_str(&format!(" (a number {}..{})", item.min.unwrap_or(0.0), item.max.unwrap_or(0.0)));
        }
        if item.kind == "action" {
            line.push_str(if item.terminal { " (an action, in a terminal)" } else { " (an action)" });
        }
        if !item.available {
            line.push_str(&format!(" — not available: {}", item.reason.as_deref().unwrap_or("")));
        }
        lines.push(line);
    }
    if lines.is_empty() {
        return Ok(format!("No setting matches \"{filter}\"."));
    }
    lines.push("A value marked * opens a terminal. Change one with change(id, value).".into());
    Ok(lines.join("\n"))
}

// --- security ---------------------------------------------------------------------------------------------

fn security(cache: &Cache, filter: &str) -> Result<String, String> {
    let report = json(cache, &["/usr/libexec/amethystora-security-status", "--json"], LONG)?;
    let all = filter == "all";
    let mut lines = Vec::new();
    for check in report["checks"].as_array().into_iter().flatten() {
        let state = s(&check["state"]);
        if !all && matches!(state, "ok" | "on" | "off" | "unavailable" | "info") {
            continue;
        }
        let command = check["command"].as_str().map(|c| format!(" ({c})")).unwrap_or_default();
        lines.push(format!("{state} {}: {} — {}{command}", s(&check["id"]), s(&check["title"]), text::field(s(&check["text"]), 400)));
    }
    let settings = &report["settings"];
    let head = format!(
        "Profile {}, virus scan {}, on detection {}, real-time {}, network protection {}",
        s(&settings["profile"]),
        s(&settings["virus_scan"]),
        s(&settings["on_detection"]),
        s(&settings["realtime"]),
        s(&settings["network"])
    );
    if lines.is_empty() {
        return Ok(format!("{head}\nNothing needs attention (filter: all lists every check)."));
    }
    Ok(format!("{head}\n{}", lines.join("\n")))
}

fn security_settings(cache: &Cache, filter: &str) -> Result<String, String> {
    let config = json(cache, &["/usr/libexec/amethystora-security-config", "--list", "--json"], SHORT)?;
    let mut groups: Vec<(String, Vec<String>)> = Vec::new();
    for setting in config["settings"].as_array().into_iter().flatten() {
        let group = s(&setting["group"]).to_string();
        if !filter.is_empty() && group != filter && !s(&setting["key"]).eq_ignore_ascii_case(filter) {
            continue;
        }
        let entry = format!("{}={}", s(&setting["key"]), s(&setting["value"]));
        match groups.iter_mut().find(|(name, _)| *name == group) {
            Some((_, list)) => list.push(entry),
            None => groups.push((group, vec![entry])),
        }
    }
    let mut lines: Vec<String> = groups.into_iter().map(|(group, list)| format!("{group}: {}", list.join(" "))).collect();
    lines.insert(0, format!("Detection profile: {}", s(&config["profile"])));
    if let Ok(hardening) = json(cache, &["/usr/libexec/amethystora-hardening", "status", "--json"], SHORT) {
        let mut changed = Vec::new();
        let mut same = Vec::new();
        for switch in hardening.as_array().into_iter().flatten() {
            let name = s(&switch["name"]);
            let state = switch["level"].as_str().unwrap_or(s(&switch["state"]));
            if !filter.is_empty() && name != filter {
                continue;
            }
            if s(&switch["state"]) != s(&switch["default"]) {
                changed.push(format!("{name}={state} (image: {})", s(&switch["default"])));
            } else {
                same.push(format!("{name}={state}"));
            }
        }
        if !changed.is_empty() {
            lines.push(format!("Enforced switches changed from the image: {}", changed.join(", ")));
        }
        if !same.is_empty() {
            lines.push(format!("As the image ships them: {}", same.join(" ")));
        }
    }
    Ok(lines.join("\n"))
}

/// The reaches that leave the sandbox, see what is typed, or load code into the app
const LEAVING: [&str; 9] = ["session-bus", "system-bus", "flatpak", "systemd", "autostart", "installations", "code", "x11", "input"];

fn app_permissions(cache: &Cache, filter: &str) -> Result<String, String> {
    let apps = json(cache, &["/usr/libexec/amethystora-app-permissions", "--json"], LONG)?;
    let mut lines = Vec::new();
    for app in apps.as_array().into_iter().flatten() {
        let id = s(&app["app"]);
        if !filter.is_empty() && !id.to_lowercase().contains(&filter.to_lowercase()) {
            continue;
        }
        let reaches: Vec<String> = app["reaches"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|reach| !filter.is_empty() || LEAVING.contains(&s(&reach["id"])))
            .map(|reach| format!("{}{}", s(&reach["id"]), if reach["granted"] == true { " (granted by an override)" } else { "" }))
            .collect();
        if reaches.is_empty() && filter.is_empty() {
            continue;
        }
        let network = if app["network_blocked"] == true { ", network taken away" } else { "" };
        let overrides = if app["user_overrides"] == true { ", has your overrides" } else { "" };
        lines.push(format!("{id} ({}, {}{network}{overrides}): {}", text::field(s(&app["name"]), 60), s(&app["installation"]),
            if reaches.is_empty() { "nothing beyond its sandbox".into() } else { reaches.join(", ") }));
    }
    if lines.is_empty() {
        return Ok("No app reaches beyond its sandbox in a way that leaves it (filter: an app id for one app's every reach).".into());
    }
    Ok(lines.join("\n"))
}

// --- software ---------------------------------------------------------------------------------------------

fn software(cache: &Cache) -> String {
    let mut out = Vec::new();
    for (installation, flag) in [("user", "--user"), ("system", "--system")] {
        let apps: Vec<String> = cache
            .run(&["flatpak", "list", "--app", flag, "--columns=application"], SHORT)
            .stdout
            .lines()
            .map(|line| text::field(line.trim(), 120))
            .filter(|line| !line.is_empty())
            .collect();
        out.push(format!("Flatpak ({installation}): {}", if apps.is_empty() { "none".into() } else { apps.join(" ") }));
    }
    let brew = "/home/linuxbrew/.linuxbrew/bin/brew";
    if std::path::Path::new(brew).exists() {
        let leaves: Vec<String> = cache.run(&[brew, "leaves"], SHORT).stdout.lines().map(|l| text::field(l.trim(), 80)).collect();
        out.push(format!("Homebrew: {}", if leaves.is_empty() { "nothing installed".into() } else { leaves.join(" ") }));
    } else {
        out.push("Homebrew: not set up".into());
    }
    match json(cache, &["/usr/bin/amethystora-pkg", "containers", "list", "--json"], SHORT) {
        Ok(containers) => {
            let list: Vec<String> = containers
                .as_array()
                .into_iter()
                .flatten()
                .map(|c| {
                    let packages: Vec<&str> = c["packages"].as_array().into_iter().flatten().filter_map(Value::as_str).collect();
                    format!("{} ({}): {}", s(&c["name"]), s(&c["template"]), if packages.is_empty() { "-".into() } else { packages.join(" ") })
                })
                .collect();
            out.push(format!("Containers: {}", if list.is_empty() { "none".into() } else { list.join("; ") }));
        }
        Err(error) => out.push(format!("Containers: {error}")),
    }
    let layered = deployments(cache).into_iter().find(|line| line.starts_with("Layered")).unwrap_or_default();
    out.push(layered);
    out.join("\n")
}

// --- updates ----------------------------------------------------------------------------------------------

fn unit_result(cache: &Cache, unit: &str) -> String {
    let output = cache.run(&["systemctl", "show", unit, "-p", "ActiveState,Result,ExecMainExitTimestamp,ExecMainStatus"], SHORT).stdout;
    let field = |key: &str| output.lines().find_map(|line| line.strip_prefix(&format!("{key}="))).unwrap_or("").to_string();
    let when = field("ExecMainExitTimestamp");
    format!("{unit}: {} (result {}, exit {}{})", field("ActiveState"), field("Result"), field("ExecMainStatus"),
        if when.is_empty() { String::new() } else { format!(", last ended {when}") })
}

fn updates(cache: &Cache) -> String {
    let mut out = vec![unit_result(cache, "uupd.service"), unit_result(cache, "uupd-manual.service")];
    let timer = cache.run(&["systemctl", "show", "uupd.timer", "-p", "ActiveState,NextElapseUSecRealtime"], SHORT).stdout;
    out.push(format!("Automatic updates: {}", timer.replace('\n', " ").trim()));
    out.extend(deployments(cache).into_iter().filter(|line| line.starts_with("Deployments") || line.starts_with("Problem")));
    let firmware = cache.run(&["fwupdmgr", "get-updates", "--json"], Duration::from_secs(30));
    match serde_json::from_str::<Value>(&firmware.stdout) {
        Ok(found) => {
            let devices: Vec<String> = found["Devices"]
                .as_array()
                .into_iter()
                .flatten()
                .filter(|d| d["Releases"].as_array().is_some_and(|r| !r.is_empty()))
                .map(|d| text::field(s(&d["Name"]), 80))
                .collect();
            out.push(format!("Firmware updates: {}", if devices.is_empty() { "none".into() } else { devices.join(", ") }));
        }
        Err(_) => out.push("Firmware updates: none waiting, or fwupd could not say".into()),
    }
    out.join("\n")
}

// --- backups, disks, setup ---------------------------------------------------------------------------------

fn backups(cache: &Cache) -> Result<String, String> {
    let status = json(cache, &["/usr/libexec/amethystora-restore", "status", "--json"], SHORT)?;
    let snapshots = &status["snapshots"];
    let backup = &status["backup"];
    let when = |value: &Value| value.as_u64().map(|t| format!("{} ago", ago(t))).unwrap_or_else(|| "never".into());
    let snap = if snapshots["on"] == true {
        format!("on, {} kept, latest {}", snapshots["count"], when(&snapshots["latest"]))
    } else if snapshots["possible"] == true {
        "off (a security switch: ame security ransomware on)".into()
    } else {
        "not possible here".into()
    };
    let back = if backup["set_up"] == true {
        format!(
            "set up ({}), daily {}, last good {}{}{}",
            text::field(s(&backup["repository"]), 120),
            if backup["daily"] == true { "on" } else { "off" },
            when(&backup["last_success"]),
            if backup["stale"] == true { ", STALE" } else { "" },
            if backup["failed"] == true { ", the last run FAILED" } else { "" }
        )
    } else {
        "not set up (ame backup setup)".into()
    };
    Ok(format!("Hourly snapshots: {snap}\nBackup: {back}"))
}

fn disks(cache: &Cache) -> Result<String, String> {
    let status = json(cache, &["/usr/libexec/amethystora-raid", "status", "--json"], SHORT)?;
    let mut out = Vec::new();
    for pool in status["pools"].as_array().into_iter().flatten() {
        let problems: Vec<&str> = pool["problems"].as_array().into_iter().flatten().filter_map(Value::as_str).collect();
        out.push(format!(
            "Pool {} at {}: {} {}, survives {} lost disk(s){}{}",
            s(&pool["name"]),
            s(&pool["mountpoint"]),
            s(&pool["state"]),
            pool["layout"].as_str().unwrap_or("?"),
            pool["survives"].as_u64().map(|n| n.to_string()).unwrap_or("?".into()),
            if pool["system"] == true { ", the system's own" } else { "" },
            if problems.is_empty() { String::new() } else { format!(", problems: {}", problems.join(" ")) }
        ));
    }
    if out.is_empty() {
        out.push("No pools of disks.".into());
    }
    let spare = status["spare"].as_array().map(Vec::len).unwrap_or(0);
    out.push(format!("Spare disks nothing uses: {spare}"));
    out.push(format!("Free space: {}", df(cache, &["/", "/var", "/var/home"]).join("; ")));
    Ok(out.join("\n"))
}

fn setup_diff(cache: &Cache) -> Result<String, String> {
    let output = cache.run(&["/usr/libexec/amethystora-setup", "diff", "--json"], LONG);
    let Ok(changes) = serde_json::from_str::<Value>(&output.stdout) else {
        return Ok(format!("No comparison: {}", text::field(output.stderr.trim(), 300)));
    };
    let lines: Vec<String> = changes
        .as_array()
        .into_iter()
        .flatten()
        .map(|change| {
            let what = ["app", "name", "uuid", "to", "key", "container"]
                .iter()
                .find_map(|key| match &change[*key] {
                    Value::String(text) => Some(text::field(text, 120)),
                    Value::Array(list) => Some(list.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(" ")),
                    Value::Number(n) => Some(n.to_string()),
                    _ => None,
                })
                .unwrap_or_default();
            let refused = if change["ok"] == false { format!(" (cannot: {})", text::field(s(&change["why"]), 120)) } else { String::new() };
            format!("{} {} {what}{refused}", s(&change["action"]), s(&change["area"]))
        })
        .collect();
    if lines.is_empty() {
        return Ok("This machine has everything the setup file names.".into());
    }
    Ok(format!("{}\nApply with ame setup apply, which shows this and asks first.", lines.join("\n")))
}

// --- units, crashes -----------------------------------------------------------------------------------------

/// A unit's name as systemctl takes it, and nothing that could be an option or a pattern
pub fn unit_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 200 && !name.starts_with('-') && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '@' | '.' | '_' | ':' | '-' | '\\'))
}

fn units(cache: &Cache, filter: &str) -> String {
    if filter.is_empty() || filter == "failed" {
        let system = failed_units(cache, false);
        let user = failed_units(cache, true);
        return format!(
            "Failed system units: {}\nFailed user units: {}",
            if system.is_empty() { "none".into() } else { system.join(", ") },
            if user.is_empty() { "none".into() } else { user.join(", ") }
        );
    }
    if !unit_name(filter) {
        return "That is not a unit's name.".into();
    }
    let mut out = Vec::new();
    for user in [false, true] {
        let mut argv = vec!["systemctl", "show", filter, "-p", "LoadState,ActiveState,SubState,Result,UnitFileState,ExecMainStatus,Description"];
        if user {
            argv.insert(1, "--user");
        }
        let shown = cache.run(&argv, SHORT).stdout;
        if shown.contains("LoadState=not-found") || shown.is_empty() {
            continue;
        }
        out.push(format!("{} ({}): {}", filter, if user { "user" } else { "system" }, text::field(&shown.replace('\n', " "), 600)));
        let mut journal = vec!["journalctl", "--no-pager", "-o", "cat", "-n", "12", "-b"];
        let flag = format!("{}={filter}", if user { "--user-unit" } else { "--unit" });
        journal.push(&flag);
        let lines: Vec<String> = run::run(&journal, SHORT).stdout.lines().map(str::to_string).collect();
        if !lines.is_empty() {
            out.push(text::data_block("Its last journal lines this boot", &lines));
        }
    }
    if out.is_empty() { format!("No unit {filter} here.") } else { out.join("\n") }
}

fn crashes(cache: &Cache) -> String {
    let output = cache.run(&["coredumpctl", "list", "--since=-1d", "--json=short", "--no-pager"], SHORT);
    let Ok(list) = serde_json::from_str::<Value>(&output.stdout) else {
        return "No crashes in the last day.".into();
    };
    let lines: Vec<String> = list
        .as_array()
        .into_iter()
        .flatten()
        .map(|crash| {
            let time = crash["time"].as_u64().map(|us| ago(us / 1_000_000)).unwrap_or_default();
            format!("{} ago: {} (pid {}, signal {})", time, text::field(s(&crash["exe"]), 200), crash["pid"], crash["sig"])
        })
        .collect();
    if lines.is_empty() {
        return "No crashes in the last day.".into();
    }
    text::data_block("Crashes in the last day; amethystora-agent diagnose PID looks into one", &lines)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn units_are_names_only() {
        assert!(unit_name("NetworkManager.service"));
        assert!(unit_name("user@1000.service"));
        assert!(!unit_name("--all"));
        assert!(!unit_name("*.service"));
        assert!(!unit_name("a b"));
        assert!(topic(&Cache::default(), "nothing", "").is_err());
    }
}
