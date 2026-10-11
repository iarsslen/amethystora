#!/usr/bin/python3
# The test VM's helper: runs what the lab's MCP server asks, over the virtio-serial port
# org.amethystora.vmtest. It reaches the VM as a systemd credential at boot, runs from /run, and is gone at
# shutdown: nothing of it is in the image. One JSON line a request, one a reply, matched by id:
#
#   {"id": 1, "op": "exec", "command": "...", "user": "root", "session": false, "timeout": 120, "stdin": B64}
#   {"id": 2, "op": "write", "path": "/tmp/x", "data": B64, "mode": "0644", "owner": "tester"}
#   {"id": 3, "op": "read", "path": "/etc/os-release", "max": 1048576}
#   {"id": 4, "op": "ping"}
import base64
import json
import os
import pwd
import select
import subprocess
import threading
import time

PORT = "/dev/virtio-ports/org.amethystora.vmtest"
LIMIT = 4 << 20
lock = threading.Lock()


def b64(data):
    return base64.b64encode(data[:LIMIT]).decode()


def reply(fd, message):
    data = (json.dumps(message) + "\n").encode()
    deadline = time.monotonic() + 30
    with lock:
        while data and time.monotonic() < deadline:
            try:
                data = data[os.write(fd, data):]
            except (BlockingIOError, InterruptedError):
                time.sleep(0.05)
            except OSError:
                return


def run(request):
    op = request.get("op", "exec")
    if op == "ping":
        return {"rc": 0}
    if op == "read":
        most = int(request.get("max", LIMIT))
        data = b""
        # In small reads: /proc and /sys allocate what each read asks for, and refuse megabytes
        with open(request["path"], "rb") as file:
            while len(data) <= most and (chunk := file.read(1 << 16)):
                data += chunk
        return {"rc": 0, "data": b64(data[:most]), "truncated": len(data) > most}
    if op == "write":
        path = request["path"]
        with open(path, "wb") as file:
            file.write(base64.b64decode(request.get("data", "")))
        os.chmod(path, int(request.get("mode", "0644"), 8))
        if request.get("owner"):
            subprocess.run(["chown", request["owner"], path], check=True)
        return {"rc": 0}
    user = request.get("user") or "root"
    command = request["command"]
    if user == "root":
        argv = ["/usr/bin/bash", "-c", command]
    elif request.get("session"):
        # In the account's graphical session, with its environment: what a user's own terminal would see. As
        # the account on its user manager's bus: systemd-run --machine loses its connection from a service.
        uid = pwd.getpwnam(user).pw_uid
        argv = ["runuser", "-u", user, "--", "env", f"XDG_RUNTIME_DIR=/run/user/{uid}",
                f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus", "systemd-run", "--user", "--pipe",
                "--wait", "--quiet", "--collect", "--", "/usr/bin/bash", "-lc", command]
    else:
        argv = ["runuser", "-l", user, "-c", command]
    try:
        done = subprocess.run(argv, input=base64.b64decode(request.get("stdin", "")), capture_output=True,
                              timeout=float(request.get("timeout", 120)))
        return {"rc": done.returncode, "stdout": b64(done.stdout), "stderr": b64(done.stderr)}
    except subprocess.TimeoutExpired as timeout:
        return {"rc": 124, "stdout": b64(timeout.stdout or b""), "stderr": b64(timeout.stderr or b""),
                "error": "timed out"}


def handle(fd, request):
    try:
        answer = run(request)
    except Exception as error:  # noqa: BLE001 -- whatever went wrong goes back to the host
        answer = {"rc": -1, "error": f"{type(error).__name__}: {error}"}
    answer["id"] = request.get("id")
    reply(fd, answer)


def main():
    while not os.path.exists(PORT):
        time.sleep(1)
    fd = os.open(PORT, os.O_RDWR | os.O_NONBLOCK)
    poller = select.poll()
    poller.register(fd, select.POLLIN)
    pending = b""
    while True:
        for _, events in poller.poll(1000):
            if not events & select.POLLIN:
                # The host is not connected: the port says so until it is
                time.sleep(0.2)
                continue
            try:
                chunk = os.read(fd, 1 << 16)
            except (BlockingIOError, InterruptedError):
                continue
            if not chunk:
                time.sleep(0.2)
                continue
            pending += chunk
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                try:
                    request = json.loads(line)
                except ValueError:
                    continue
                threading.Thread(target=handle, args=(fd, request), daemon=True).start()


main()
