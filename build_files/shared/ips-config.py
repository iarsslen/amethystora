#!/usr/bin/env python3
"""Network protection's Suricata configuration (amethystora-ips.service), derived at build time from the
one the suricata package ships, so that it matches the Suricata this image has, 7 or 8, key for key.

    ips-config.py SOURCE DESTINATION

Suricata's own --include cannot do this: it merges a list into the one it overrides index by index,
and the outputs this replaces are a list. Values are read and written as strings (yaml.BaseLoader),
which is how Suricata reads them, so nothing in the package's file is reinterpreted on the way
through. What changes, and why:

  - It fails open. Suricata 7 made its exception policies drop in IPS mode: a memcap reached, a
    connection it picked up halfway, a packet its stream engine calls invalid. On a desktop each of
    those is a connection that stops working for no reason anyone can see, so they are all let through.
  - Encrypted traffic is inspected up to its handshake (the server name, the certificate, the TLS
    fingerprint) and then handed back to the kernel, and so is anything past the first megabyte of a
    stream. bypass-mark is how Suricata says so: amethystora-ips.nft stops queueing those connections.
  - It logs only alerts, without payloads. The package's EVE log records every DNS query, web request
    and TLS server name, which on a desktop is a browsing history nobody asked to keep.
  - HOME_NET is this machine wherever it is: the private ranges, the tailnet, and IPv6's global
    unicast, where a desktop's own addresses are and keep changing. EXTERNAL_NET is anything, so that a
    stranger on the same café Wi-Fi counts as outside; the rules anchor on the direction of the flow.
  - The low detection profile, for the memory of a desktop rather than a sensor.
"""

import sys

import yaml

# The bit amethystora-ips.nft tests (0x10000000). Suricata reads these numbers in decimal.
BYPASS_MARK = str(0x10000000)

SETTINGS = {
    'vars.address-groups.HOME_NET':
        '[10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,fc00::/7,fe80::/10,2000::/3]',
    'vars.address-groups.EXTERNAL_NET': 'any',
    'nfq.mode': 'accept',
    'nfq.fail-open': 'yes',
    'nfq.bypass-mark': BYPASS_MARK,
    'nfq.bypass-mask': BYPASS_MARK,
    'exception-policy': 'ignore',
    'stream.drop-invalid': 'no',
    'stream.midstream': 'true',
    'stream.bypass': 'yes',
    'app-layer.protocols.tls.encryption-handling': 'bypass',
    'app-layer.protocols.ssh.encryption-handling': 'bypass',
    'detect.profile': 'low',
}

OUTPUTS = [{
    'eve-log': {
        'enabled': 'yes',
        'filetype': 'regular',
        'filename': 'eve.json',
        'types': [{
            'alert': {
                'payload': 'no',
                'payload-printable': 'no',
                'packet': 'no',
                'http-body': 'no',
                'http-body-printable': 'no',
                'websocket-payload': 'no',
                'websocket-payload-printable': 'no',
                'tagged-packets': 'no',
            },
        }],
    },
}]


def put(config, path, value):
    *parents, key = path.split('.')
    node = config
    for parent in parents:
        # A section whose every line is commented out, such as nfq:, reads as an empty string
        if not isinstance(node.get(parent), dict):
            node[parent] = {}
        node = node[parent]
    node[key] = value


def main():
    source, destination = sys.argv[1:3]
    with open(source, encoding='utf-8') as handle:
        config = yaml.load(handle, Loader=yaml.BaseLoader)
    for path, value in SETTINGS.items():
        put(config, path, value)
    config['outputs'] = OUTPUTS
    # Suricata refuses a file that does not open with its YAML 1.1 directive and ---
    text = yaml.safe_dump(config, version=(1, 1), explicit_start=True, sort_keys=False,
                          default_flow_style=False, width=1000)
    directive, body = text.split('---\n', 1)
    with open(destination, 'w', encoding='utf-8') as handle:
        handle.write(f'{directive}---\n# Generated from the suricata package\'s suricata.yaml by '
                     f'build_files/shared/ips-config.py\n{body}')


if __name__ == '__main__':
    main()
