#!/usr/bin/python3
"""pkagent.py PID PASSWORD SECONDS: polkit's text agent (pkttyagent) for the process PID, on a terminal of its own,
as the person at the machine would answer GNOME's password dialog: every password prompt it shows in SECONDS is
answered with PASSWORD. Run as the account that owns PID. Prints how many prompts were answered, and exits when the
time is up or PID ends.
"""
import os
import pty
import re
import select
import signal
import sys
import time


def main():
    pid, password, seconds = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
    child, fd = pty.fork()
    if child == 0:
        os.execvp("pkttyagent", ["pkttyagent", "--process", str(pid)])
    answered = 0
    shown = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        ready, _, _ = select.select([fd], [], [], 0.5)
        if not ready:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        shown += data
        # One answer for each prompt shown since the last one
        while re.search(rb"[Pp]assword[^:\n]*:", shown):
            shown = re.split(rb"[Pp]assword[^:\n]*:", shown, maxsplit=1)[1]
            os.write(fd, password.encode() + b"\n")
            answered += 1
    os.kill(child, signal.SIGTERM)
    try:
        os.waitpid(child, 0)
    except ChildProcessError:
        pass
    print(answered)


main()
