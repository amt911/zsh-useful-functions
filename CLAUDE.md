# zsh-useful-functions — Claude Guide

Personal zsh plugin: a grab-bag of shell functions (image batch ops, disk/dedupe and
binary-content compares, LUKS/dm-crypt and VeraCrypt volume open/close, size-based partition
mounting, `rsync` fan-out, btrfs/snapper root remount, file-hash checks, IOMMU groups, random
string/file generators). Single-user tool, sourced directly or via a zsh plugin manager.

## Start here

Run `/graphify` before each session. The persistent graph at `graphify-out/graph.json`
summarizes architecture, dependencies, and cross-cutting concepts without re-reading the
repo each time.

## ⚡ graphify — use every session

```
/graphify            # first run (builds graph from scratch)
/graphify --update   # incremental update (only re-extracts changed files)
/graphify query "<question>"    # architecture questions instead of opening multiple files
/graphify explain "<name>"      # locate a concept or symbol
/graphify path "A" "B"          # dependency path between two modules
```

Outputs in `graphify-out/`: `graph.json` (source of truth), `GRAPH_REPORT.md` (god nodes,
communities, surprising connections), `graph.html` (interactive view).

Run `/graphify --update` at end of session if you touched docs.

## ⚡ superpowers — use whenever applicable

Always prefer **superpowers** skills over ad-hoc approaches. If there's even a small
chance a skill applies to the task, invoke it via the `Skill` tool before acting
(including before clarifying questions).

- **Process skills first** — `brainstorming` before adding a new function, `systematic-debugging`
  before fixing a broken one, `test-driven-development` before writing implementation.
- **Then implementation skills** — domain-specific skills guide execution.
- **Verify before claiming done** — `verification-before-completion` / `requesting-code-review`
  before merging.

User instructions always take precedence over skills; skills override default behavior.

### Mode switch

- **"lite mode"** — fully disables superpowers: no skill is invoked, not even the
  applicability check, until **"normal mode"** is said.
- **"normal mode"** (default) — standard superpowers behavior, plus: when delegating
  coding work, dispatch at most 1 agent at a time, and never use a model above Sonnet
  (no Opus).
- **"modo desatendido"** (unattended mode) — the user is away and delegates autonomy: work
  without waiting for confirmations and make reasonable decisions yourself instead of asking.
  In this mode you MAY **`git push` the feature branches you create** and **open PRs via `gh`**
  on your own. The hard limits still hold and are NOT lifted: **never merge anything** (no
  `git merge`, no fast-forward integration, no `gh pr merge`), **never push to `main`** or any
  protected branch directly, and **never** `git push --force` / `--force-with-lease`. Deliver
  everything as pushed branches + PRs for the user to merge. Reverts to defaults on
  **"normal mode"**.

Confirm the switch briefly when it happens.

## Stack

- **zsh** — target shell; functions use zsh-specific syntax (`${var:l}`, `**` globs, `local -r`).
- **Bash-compatible core utils** — `getopts`, `read`, `printf`/`echo -e` used throughout;
  some functions are written with POSIX-ish `[ ]` tests even though the shebang is `#!/bin/zsh`.
- **External CLI dependencies (assumed installed, not vendored)**: `imagemagick`
  (`magick`, falling back to `convert` on ImageMagick 6), `pngquant`, `cryptsetup`,
  `systemd-cryptsetup`, `lspci`, `btrfs-progs`, util-linux (`lsblk`, `mount --mkdir`),
  coreutils (`dd`, `od`, `cmp`, `stat`, `numfmt`), `ntfs-3g` (NTFS mounts in
  `mount_partitions`), `rsync` (`rsync_fanout`).
- No package manager, no build step — this is a single sourced `.zsh` file.

## Commands

```bash
# "install" — no build; just source it or add as a plugin entry
source zsh-useful-functions.zsh

# test (bats-core is vendored as a git submodule under test/bats)
git submodule update --init test/bats   # first checkout only
./test/bats/bin/bats test/               # run the whole suite

# lint
shellcheck --shell=bash zsh-useful-functions.zsh   # shellcheck has no zsh dialect; bash is closest
```

There is no `build` or `dev` command — none exist. The `test` command above is real; `bats` is not on `PATH`, so invoke it via `./test/bats/bin/bats`.

## Tests and quality

**A bats-core suite is now set up** under `test/` (`test/*.bats`, run with
`./test/bats/bin/bats test/`). It covers argument parsing, usage errors, and the
string/path logic of most functions; interactive/hardware cores are exercised only on
their arg-parsing/usage paths (see TDD exceptions below). Coverage is not yet gated.

- **Test runner**: [bats-core](https://github.com/bats-core/bats-core), vendored as a
  submodule at `test/bats`. Specs live in `test/*.bats`, grouped by area
  (`open-partitions.bats`, `disk.bats`, `image.bats`, `misc.bats`, `smoke.bats`); shared stubs
  and the `run_op`/`run_plugin` helpers live in `test/test_helper.bash`.
- **Lint**: `shellcheck --shell=bash` is run manually against changed functions before
  committing. It has no zsh dialect, so zsh-only constructs (glob qualifiers like `(N)`,
  `zparseopts`, `$+commands`, `print -rn`) produce parse-error false positives — don't
  "fix" those into bash.
- **Coverage gate: 80%** (aspirational — no coverage tool exists for zsh function suites
  today). The working bar: every new/changed function has at least one happy-path and one
  usage-error test.

### TDD — required for new logic

For any new function, or non-trivial behavior change to an existing one:

1. **Red** — write a failing `bats` test that describes the expected behavior (arg parsing,
   usage-error output, exit codes).
2. **Green** — implement the minimum to pass.
3. **Refactor** — clean up under green tests.

Exceptions (TDD not required):
- One-line wrapper functions with no branching (e.g. trivial `alias`-style helpers).
- Interactive/destructive functions that require real hardware or volumes to exercise
  (`open_mount_veracrypt`, `open_partitions`, `btrfs_snapper_root_rw/ro`) — cover the
  argument-parsing and usage-error paths only; don't fake the destructive core logic.

Rules:
- **Don't skip tests to ship faster** — the bats suite exists; every function you touch gets a
  test in the matching `test/*.bats`, not a "later".
- **Test over mock**: for pure string/arg-parsing logic, exercise the real function; don't
  reimplement its logic in the test.

## Working rules

- **Use superpowers skills whenever they apply** — invoke via `Skill` before acting;
  process skills before implementation skills.
- **Don't add external tool dependencies without asking** — every function here assumes a
  specific CLI is present (`convert`, `cryptsetup`, `pngquant`...); adding a new one is a
  deliberate choice, not incidental.
- **TDD by default** for new or changed logic (see above) — the bats suite is in place.
- **Don't silently drop the 80% coverage aspiration** — if a function can't reasonably be
  tested (destructive, hardware-dependent), say so explicitly instead of skipping quietly.
- **Preserve the existing style**: `local -r` for constants, explicit `unset` of loop
  variables (`i`, `f`, `g`, `d`) at the end of each function, `[ ]`-style POSIX tests, usage
  banners printed on `argc == 0` or invalid input, non-zero explicit `return` codes.
- **Secrets handling**: functions that `read -rs` a password/PIM must `unset` it before
  returning (see `open_mount_veracrypt`, `open_partitions`) — keep doing this for any new
  credential-handling function.

## Git & GitHub

- **Commits and branches OK** — create commits and new branches whenever it makes sense,
  without asking first.
- **Never push** *(default)* — no `git push` under any circumstance, and absolutely never
  `git push --force` / `--force-with-lease`. Leave pushing to the user. **Exception:** when
  **"modo desatendido"** is active, you may push the feature branches you create (never
  `main`/protected branches, never force) so PRs are ready for review.
- **Never merge — no permission** — you do NOT have permission to merge anything into any
  branch, nor to merge any pull request. No `git merge`, no fast-forward integration, no
  `gh pr merge`. This holds in every mode, **including "modo desatendido"**. Leave every merge
  to the user.
- **GitHub via `gh`** — if the `gh` CLI is available, you may open pull requests, issues,
  and similar (comments, labels, etc.). These don't require pushing on your part beyond what
  `gh` itself does for an already-pushed branch.
- **Branches:** `feat/name`, `fix/description`, `chore/task`.
- **Every PR must include a manual test plan** — a **How to test manually** section: which
  functions changed, how to source and invoke them, the exact commands (and any hardware/volume
  prerequisites), plus `./test/bats/bin/bats test/` and the expected result.
