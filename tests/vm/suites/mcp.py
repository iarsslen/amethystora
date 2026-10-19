#!/usr/bin/python3
"""mcp.py [--as-agent NAME ARG...] CALL...: an MCP client for amethystora-agent-tools, as an agent is one: it starts
`/usr/libexec/amethystora-agent-tools mcp`, initializes, and makes each CALL in turn, printing one JSON line per
answer. A CALL is `list` (tools/list) or `NAME JSON` (tools/call NAME with the JSON arguments), or `pause SECONDS`.
The server then sees its input close, as when an agent ends.

--as-agent NAME ARG... runs the client under a process whose command line is NAME ARG... (until --), as an agent
started with those arguments would be, for the check of an agent whose own checks are off.

    mcp.py list 'state {"topic": "overview"}'
"""
import json
import os
import subprocess
import sys
import time

TOOLS = "/usr/libexec/amethystora-agent-tools"


def main(calls):
    server = subprocess.Popen([TOOLS, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    print(json.dumps({"server_pid": server.pid}), flush=True)
    n = 0

    def ask(method, params):
        nonlocal n
        n += 1
        server.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params}) + "\n")
        server.stdin.flush()
        return json.loads(server.stdout.readline())

    init = ask("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "vmlab", "version": "1"}})
    print(json.dumps({"initialize": init.get("result", init)}), flush=True)
    server.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    server.stdin.flush()
    for call in calls:
        if call == "list":
            answer = ask("tools/list", {})
            print(json.dumps({"list": [tool["name"] for tool in answer["result"]["tools"]],
                              "bytes": len(json.dumps(answer["result"]["tools"]))}), flush=True)
            continue
        name, _, args = call.partition(" ")
        if name == "pause":
            time.sleep(float(args))
            continue
        started = time.time()
        answer = ask("tools/call", {"name": name, "arguments": json.loads(args or "{}")})
        result = answer.get("result") or {}
        text = "".join(part.get("text", "") for part in result.get("content", []))
        print(json.dumps({"call": name, "error": result.get("isError", "error" in answer), "text": text,
                          "seconds": round(time.time() - started, 2)}), flush=True)
    server.stdin.close()
    server.wait(timeout=60)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--as-agent"]:
        # Started again as a program of the agent's name (Python, through a link of that name), with the agent's
        # arguments after the script's path, which /proc/PID/cmdline then shows as the watcher reads them
        end = args.index("--")
        agent = args[1:end]
        folder = f"/tmp/vmlab-agent-{os.getuid()}"
        os.makedirs(folder, exist_ok=True)
        link = os.path.join(folder, agent[0])
        if not os.path.islink(link):
            os.symlink(sys.executable, link)
        os.execv(link, [link, os.path.abspath(__file__)] + agent[1:] + ["--client"] + args[end + 1:])
    if "--client" in args:
        args = args[args.index("--client") + 1:]
    main(args)
