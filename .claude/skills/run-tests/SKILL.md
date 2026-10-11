---
name: run-tests
description: Build Amethystora from the last commit, boot it in the VM lab and run the test suites, fixing what fails. Use only when the user explicitly asks to run the tests ("run the tests", "build and test").
---

# Running the tests

A run builds the whole image and boots it, which takes an hour or more: start one only when the user asks.
The maintainer's choices for it (2026-10-11): a run builds **committed HEAD**; build failures and test
failures are **fixed, committed and run again**; when a local build cannot run, **GitHub** builds instead.

## 1. Commit first

A run tests what is committed. Commit your own finished work before starting, staging your files by name:
other sessions work in this tree, and their uncommitted files are theirs (`git status` lists them). Never
commit someone else's change to make a run pass.

## 2. Run

```bash
bash tests/vm/run.sh            # all: build, disk, test (an hour or more)
bash tests/vm/run.sh test       # the suites again, on the disk the last run made
bash tests/vm/run.sh test --keep  # and leave the VM ("test") running, for a look over MCP
```

Run it in the background (`run_in_background: true`) and wait for the notification; it starts the lab
container when it is stopped. It prints a summary at the end. Everything else is in the lab:

```bash
docker exec amevm cat /vm/runs/last/summary.md
docker exec amevm ls /vm/runs/last          # run.log, build.log, disk.log, NN-suite.sh.log and .png, journal.log
docker cp amevm:/vm/runs/last/20-apps.sh.png <scratchpad>/   # then Read it
```

On Windows put Docker Desktop's `resources/bin` on PATH and set `MSYS_NO_PATHCONV=1` for `docker exec`
commands that name a path inside the lab.

## 3. When the build fails

The summary ends with the last 80 lines of `build.log`; search the rest for the first error
(`docker exec amevm grep -n -E "::error|error:|FAIL|Error" /vm/runs/last/build.log | head`). `20-tests.sh` runs
inside the build, so a failed check there is a build failure too. Fix the cause, commit (`fix(scope): ...`
with the `Assisted-by` footer), and run again. The build is one long step, so each attempt is a full build.
After three attempts at the same error, stop and report.

A failure of the environment rather than the code (out of disk: `docker system df`; out of memory; a
registry or network that does not answer) goes to GitHub instead (section 6).

## 4. When a test fails

Read the suite's log, its screenshot and the guest's `journal.log`. To look closer, `run.sh test --keep`
and the `amethystora-vm` MCP tools (`vm_exec`, `vm_screenshot`, `vm_serial` on VM `test`). Fix the cause in
the image, commit, and run again: `run.sh` when the image changed, `run.sh test` when only a suite did. At
most three rounds, then report what is left.

Never weaken, skip or delete a check to make a run pass. A check that is itself wrong is fixed, and the
commit says why. A failure that needs the user (a design choice, a secret, a decision between two
behaviours, a bug upstream) is reported with its evidence, not worked around.

## 5. Report

The summary table, the commits the run made, how long each stage took, and what is left with why.
Measurements a suite prints (lines starting with `#`, such as Falco's memory) go in the report too.

## 6. GitHub instead of a local build

Only when the build cannot run here. Never push to `main`.

```bash
sha=$(git rev-parse --short HEAD)
git push origin "HEAD:refs/heads/test/${sha}"
gh workflow run "Latest Images" --repo iarsslen/amethystora --ref "test/${sha}"
gh run list --repo iarsslen/amethystora --workflow "Latest Images" --branch "test/${sha}" --limit 1
gh run watch RUN_ID --repo iarsslen/amethystora --exit-status
gh run view RUN_ID --repo iarsslen/amethystora --log-failed | tail -n 200
git push origin --delete "test/${sha}"   # when done
```

A branch build publishes nothing (`PUBLISH` in `reusable-build.yml`), so it checks the build and
`20-tests.sh` only. The VM suites then need a local build, or the image `main` publishes once the user has
pushed (`run.sh disk` and `test` on it: tag it `localhost/amethystora:latest` in the lab first).

## Adding to the suites

A new feature gets its check in `tests/vm/suites` with it: a new `NN-name.sh` or a line in a suite that
fits, as `tests/vm/README.md` describes. A bug a run found gets the check that would have caught it.
