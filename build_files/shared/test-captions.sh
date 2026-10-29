#!/usr/bin/bash
# amethystora-captions (/usr/libexec/amethystora-captions, or the copy named first) without the network, for 20-tests.sh
# (plans/beyond/spec-r4-later.md, part B): a fresh account has no model and the image has the recognizer; a download
# that is not the pinned model is refused and leaves nothing behind; the unpacking refuses a member that would leave
# the model's folder, a link and anything outside the model's own folder; listening without a model says so and stops;
# anything but the four commands is refused.

set -euo pipefail

CAPTIONS="${1:-/usr/libexec/amethystora-captions}"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
export HOME="${T}/home" XDG_DATA_HOME="${T}/home/.local/share"
mkdir -p "${HOME}"
FOLDER="${XDG_DATA_HOME}/amethystora/captions"

[[ "$("${CAPTIONS}" status)" == no-model ]]

# Not the pinned model: refused, and nothing is kept
printf 'not a model' >"${T}/fake.zip"
AMETHYSTORA_CAPTIONS_URL="file://${T}/fake.zip" "${CAPTIONS}" fetch 2>/dev/null && false
[[ -z "$(ls -A "${FOLDER}")" ]]
[[ "$("${CAPTIONS}" status)" == no-model ]]

# The unpacking, called on archives made here (the pinned checksum keeps any of them from being fetched)
python3 -I - "${CAPTIONS}" "${T}" <<'EOF'
import importlib.machinery, importlib.util, os, sys, zipfile
loader = importlib.machinery.SourceFileLoader('captions', sys.argv[1])
spec = importlib.util.spec_from_loader('captions', loader)
captions = importlib.util.module_from_spec(spec)
loader.exec_module(captions)
root = sys.argv[2]
top = captions.MODEL_DIR

def archive(name, members, link=None):
    path = os.path.join(root, name)
    with zipfile.ZipFile(path, 'w') as z:
        for member in members:
            z.writestr(member, 'x')
        if link:
            info = zipfile.ZipInfo(link)
            info.external_attr = (0o120777 << 16)
            z.writestr(info, '/etc/passwd')
    return path

def refused(path):
    into = os.path.join(root, 'out-' + os.path.basename(path))
    os.makedirs(into)
    try:
        captions.unpack(path, into)
    except ValueError:
        assert not os.listdir(into), f'{path}: something was written before the refusal'
        return
    raise SystemExit(f'{path} was unpacked')

refused(archive('climbs.zip', [f'{top}/conf/model.conf', f'{top}/../../evil']))
refused(archive('absolute.zip', ['/etc/evil']))
refused(archive('other.zip', [f'{top}/conf/model.conf', 'elsewhere/file']))
refused(archive('backslash.zip', [f'{top}\\..\\evil']))
refused(archive('link.zip', [f'{top}/conf/model.conf'], link=f'{top}/am/final.mdl'))
good = os.path.join(root, 'out-good')
os.makedirs(good)
unpacked = captions.unpack(archive('good.zip', [f'{top}/conf/model.conf', f'{top}/am/final.mdl']), good)
assert os.path.isfile(os.path.join(unpacked, 'conf', 'model.conf'))
EOF

# Listening without a model says so on stdout and stops; a word it does not know is refused
[[ "$("${CAPTIONS}" listen </dev/null)" == '{"error": "model"}' ]]
"${CAPTIONS}" record 2>/dev/null && false
"${CAPTIONS}" 2>/dev/null && false
# What a fetch cut short by closing its terminal left goes with remove
mkdir -p "${FOLDER}/.unpacking" "${FOLDER}/model/conf"
touch "${FOLDER}/.download.zip" "${FOLDER}/model/conf/model.conf"
"${CAPTIONS}" remove
[[ -z "$(ls -A "${FOLDER}")" ]]
echo "test-captions: ok"
