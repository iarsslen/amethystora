#!/usr/bin/python3
"""marionette.py PORT -- asks a running Firefox (started with --marionette --remote-allow-system-access) what its
enterprise policies and data collection preferences are, and prints one JSON object. For 99-browser-privacy.sh.
"""
import json
import socket
import sys
import time

SCRIPT = """
const pref = (name) => Services.prefs.getBoolPref(name, null);
const active = Services.policies.getActivePolicies() || {};
return {
  status: Services.policies.status,
  policies: Object.keys(active),
  upload: pref("datareporting.healthreport.uploadEnabled"),
  uploadLocked: Services.prefs.prefIsLocked("datareporting.healthreport.uploadEnabled"),
  usage: pref("datareporting.usage.uploadEnabled"),
  sponsoredTopSites: pref("browser.newtabpage.activity-stream.showSponsoredTopSites"),
  sponsoredStories: pref("browser.newtabpage.activity-stream.showSponsored"),
  sponsoredLocked: Services.prefs.prefIsLocked("browser.newtabpage.activity-stream.showSponsoredTopSites"),
  online: pref("browser.urlbar.quicksuggest.online.enabled"),
  shield: Services.policies.isAllowed("Shield"),
};
"""


class Connection:
    def __init__(self, port):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=60)
        self.buffer = b''
        self.id = 0
        self.read()  # the greeting

    def read(self):
        while b':' not in self.buffer:
            self.buffer += self.sock.recv(65536)
        size, rest = self.buffer.split(b':', 1)
        while len(rest) < int(size):
            rest += self.sock.recv(65536)
        self.buffer = rest[int(size):]
        return json.loads(rest[:int(size)])

    def call(self, name, params):
        self.id += 1
        body = json.dumps([0, self.id, name, params]).encode()
        self.sock.sendall(str(len(body)).encode() + b':' + body)
        reply = self.read()
        if reply[2]:
            raise RuntimeError(f'{name}: {reply[2]}')
        return reply[3]


def main():
    port = int(sys.argv[1])
    for _ in range(60):
        try:
            conn = Connection(port)
            break
        except OSError:
            time.sleep(2)
    else:
        sys.exit('Marionette did not answer')
    conn.call('WebDriver:NewSession', {'capabilities': {}})
    conn.call('Marionette:SetContext', {'value': 'chrome'})
    result = conn.call('WebDriver:ExecuteScript', {'script': SCRIPT, 'args': []})
    print(json.dumps(result['value'] if isinstance(result, dict) and 'value' in result else result))


main()
