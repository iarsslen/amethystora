# CONTRIBUTING

Thanks for helping out!

This repository builds the Amethystora images. Open an issue or pull request on [iarsslen/amethystora](https://github.com/iarsslen/amethystora).

Amethystora is based on [Universal Blue](https://universal-blue.org). Its desktop layer lives in this repository, under `system_files/shared`, and is not pulled from upstream, so changes to it are made here.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).

## Translating

Amethystora's own apps, the security report and the manual are translated on Weblate. Translate there
rather than in a pull request: Weblate keeps every translation in step with the English, which is the
only text edited in this repository.

What there is to translate, and how each is set up on Weblate:

| What | Weblate file format | File mask | Base or template file |
| --- | --- | --- | --- |
| Each app: `manual`, `security`, `update`, `logs`, `notes` | JSON file (monolingual), with the flag `icu-message-format` | `system_files/shared/usr/lib/amethystora-<app>/resources/app/locale/*.json` | `.../locale/en.json` |
| The security report and the app permissions | gettext PO file, with the "Update PO files to match POT (msgmerge)" add-on | `po/*.po` | `po/amethystora.pot` |
| The manual's pages | Markdown file, one component per page, found by the "Component discovery" add-on with `system_files/shared/usr/share/amethystora/manual/(?P<language>[^/]+)/(?P<component>[^/]+)\.md` | `system_files/shared/usr/share/amethystora/manual/*/<page>.md` | `system_files/shared/usr/share/amethystora/manual/<page>.md` |
| The hotkeys page, set up by hand because its English is one folder up | Markdown file | `system_files/shared/usr/share/amethystora/manual/*/keybindings.md` | `system_files/shared/usr/share/amethystora/keybindings.md` |

A few things to keep in mind when translating:

- The apps' messages are ICU MessageFormat: keep `{name}` as it is, and give a plural every form your
  language has (`{count, plural, one {...} few {...} other {...}}`).
- The report's messages are shell text: keep `${NAME}` as it is. The states `ok`, `check` and `off` sit
  in a column seven letters wide.
- In the manual, keep commands, paths, key names and the targets of links (`updates.md#rolling-back`)
  exactly as they are: only what people read changes.

When the English changes, run `node build_files/shared/check-translations.js --write --po po
system_files/shared`, which rewrites each app's `locale/en.json` and `po/amethystora.pot` from the code,
and commit them with the change. The build runs the same check and fails on a catalog that does not
match the code.
