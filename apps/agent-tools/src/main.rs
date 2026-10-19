//! amethystora-agent-tools: the AI agent's tools, as an MCP server and as a command.
//!
//!   amethystora-agent-tools mcp                      the MCP server, on stdin and stdout (the agent starts it)
//!   amethystora-agent-tools search QUERY... [-k N]   the same answers as the tools, for a person or an agent
//!   amethystora-agent-tools read ID                  without MCP (amethystora-agent search|read|state)
//!   amethystora-agent-tools state TOPIC [FILTER]
//!   amethystora-agent-tools history [ID]
//!   amethystora-agent-tools policy [--json|--level|--ceiling]
//!                                                    what this account may use, and the administrator's settings
//!   amethystora-agent-tools conf allow act|know|off|default [ACCOUNT] | conf root MODE
//!                                                    as root: the administrator's lock and root mode (ame agent lock, root)
//!   amethystora-agent-tools index --write DIR [--root ROOT] [--sources-only] [--model DIR]
//!                                                    the index, when the image is built
//!   amethystora-agent-tools eval GOLDEN [--dir DIR] [--min RECALL]
//!                                                    recall@3 of the golden questions, for each ranking

use std::io::{BufReader, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use amethystora_agent_tools::index::build::{self, Sources};
use amethystora_agent_tools::index::{self, Index, Ranking};
use amethystora_agent_tools::mcp;
use amethystora_agent_tools::policy::{self, Policy};
use amethystora_agent_tools::server::Server;
use serde_json::{Value, json};

fn usage() -> ExitCode {
    eprintln!("usage: amethystora-agent-tools mcp | search QUERY... | read ID | state TOPIC [FILTER] | history [ID] | policy [--json]");
    eprintln!("       amethystora-agent-tools index --write DIR [--root ROOT] [--sources-only] [--model DIR] | eval GOLDEN [--dir DIR] [--min R]");
    ExitCode::from(64)
}

/// The value after an option, as in --root /
fn option(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|arg| arg == name).and_then(|at| args.get(at + 1)).cloned()
}

fn say(result: Result<String, String>) -> ExitCode {
    match result {
        Ok(text) => {
            println!("{text}");
            ExitCode::SUCCESS
        }
        Err(text) => {
            eprintln!("{text}");
            ExitCode::FAILURE
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(command) = args.first() else { return usage() };
    let rest = &args[1..];
    match command.as_str() {
        "mcp" => {
            let server = Server::default();
            let stdin = std::io::stdin();
            match mcp::serve(&server, BufReader::new(stdin.lock()), std::io::stdout().lock()) {
                Ok(()) => ExitCode::SUCCESS,
                Err(_) => ExitCode::FAILURE,
            }
        }
        "search" => {
            let mut words: Vec<String> = Vec::new();
            let mut k = 4;
            let mut at = 0;
            while at < rest.len() {
                if rest[at] == "-k" {
                    k = rest.get(at + 1).and_then(|n| n.parse().ok()).unwrap_or(4);
                    at += 2;
                    continue;
                }
                words.push(rest[at].clone());
                at += 1;
            }
            say(Server::default().call("search", &json!({"query": words.join(" "), "k": k})))
        }
        "read" if rest.len() == 1 => say(Server::default().call("read", &json!({"id": rest[0]}))),
        "state" if !rest.is_empty() => {
            say(Server::default().call("state", &json!({"topic": rest[0], "filter": rest.get(1).cloned().unwrap_or_default()})))
        }
        "history" => {
            let args = rest.first().map(|id| json!({"id": id, "wait": 0})).unwrap_or(json!({}));
            say(Server::default().call("history", &args))
        }
        "conf" => match policy::change_conf(std::path::Path::new(policy::CONF), rest) {
            Ok(conf) => {
                // In the words a note takes: lower case, no spaces
                let said = format!("allow={}:root={}:accounts={}", conf.allow.word(), conf.root.word(), conf.allow_for.len());
                // Noted for the security watcher, which then says the change without alarm, as for a switch's own command
                let _ = std::process::Command::new("/usr/libexec/amethystora-security-config")
                    .args(["note", "agent-conf", &said])
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .status();
                println!("{}", conf.render().lines().filter(|line| !line.starts_with('#')).collect::<Vec<_>>().join("\n"));
                ExitCode::SUCCESS
            }
            Err(error) => {
                eprintln!("{error}");
                ExitCode::FAILURE
            }
        },
        "policy" => {
            let policy = Policy::current();
            if rest.iter().any(|arg| arg == "--json") {
                println!("{}", policy.json());
            } else if rest.iter().any(|arg| arg == "--level") {
                println!("{}", policy.level().word());
            } else if rest.iter().any(|arg| arg == "--ceiling") {
                println!("{}", policy.ceiling().word());
            } else {
                println!(
                    "Level: {} (agentic features {}, changes {}), most allowed: {}, root commands: {}",
                    policy.level().word(),
                    if policy.level1 { "on" } else { "off" },
                    if policy.level2 { "on" } else { "off" },
                    policy.ceiling().word(),
                    policy.conf.root.word()
                );
            }
            ExitCode::SUCCESS
        }
        "index" => {
            let Some(out) = option(rest, "--write").map(PathBuf::from) else { return usage() };
            let sources = Sources {
                root: option(rest, "--root").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/")),
                generated: !rest.iter().any(|arg| arg == "--sources-only"),
            };
            let model = option(rest, "--model").map(PathBuf::from).unwrap_or_else(|| out.join("model"));
            match build::write(&sources, &out, &model) {
                Ok(meta) => {
                    println!("{meta}");
                    ExitCode::SUCCESS
                }
                Err(error) => {
                    eprintln!("index: {error}");
                    ExitCode::FAILURE
                }
            }
        }
        "eval" => {
            let Some(golden) = rest.first() else { return usage() };
            let dir = option(rest, "--dir").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(index::DIR));
            let min: f32 = option(rest, "--min").and_then(|n| n.parse().ok()).unwrap_or(0.9);
            let set = match std::fs::read_to_string(golden) {
                Ok(text) => build::golden(&text),
                Err(error) => {
                    eprintln!("{golden}: {error}");
                    return ExitCode::FAILURE;
                }
            };
            let index = match Index::load(&dir) {
                Ok(index) => index,
                Err(error) => {
                    eprintln!("{error}");
                    return ExitCode::FAILURE;
                }
            };
            let (hits, asked, missed) = build::recall(&index, &set);
            let mut report = serde_json::Map::new();
            for (ranking, count) in &hits {
                let name = match ranking {
                    Ranking::Words => "words",
                    Ranking::Meaning => "meaning",
                    Ranking::Fused => "fused",
                };
                report.insert(name.into(), json!(*count as f32 / asked.max(1) as f32));
            }
            report.insert("questions".into(), json!(asked));
            report.insert("meaning_loaded".into(), json!(index.has_meaning()));
            let mut out = std::io::stdout().lock();
            let _ = writeln!(out, "{}", Value::Object(report.clone()));
            for miss in &missed {
                let _ = writeln!(out, "missed: {miss}");
            }
            let fused = report["fused"].as_f64().unwrap_or(0.0) as f32;
            if asked == 0 || fused < min { ExitCode::FAILURE } else { ExitCode::SUCCESS }
        }
        _ => usage(),
    }
}
