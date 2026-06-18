# Starship theme support (selectable prompt: powerlevel10k | starship)

## Overview
Add [starship](https://github.com/starship/starship) as a selectable prompt theme alongside the
current powerlevel10k. Users pick the theme via a new `zsh_theme` variable; the default stays
`powerlevel10k` so existing deployments are unaffected (fully backward compatible).

Unlike powerlevel10k, starship is a standalone Rust binary — it is not an antigen bundle. It is
installed as a binary and activated in `.zshrc` with `eval "$(starship init zsh)"`. When starship
is selected, all powerlevel10k/powerlevel9k wiring is skipped and a generated
`~/.config/starship.toml` reproduces the role's current p9k-style prompt (segments + colors) so the
visual result is close to parity.

Problem it solves: lets users opt into the faster, cross-shell starship prompt without losing the
existing powerlevel10k default or the role's curated prompt layout.

## Context (from discovery)
- **Theme is currently driven by** `zsh_antigen_theme: "romkatv/powerlevel10k powerlevel10k"`
  (`defaults/main.yml:82`).
- **`templates/zshrc.j2` p10k-coupled blocks** (all currently gated on the literal string compare
  `zsh_antigen_theme == "romkatv/powerlevel10k powerlevel10k"`):
  - instant-prompt header — lines ~9-19
  - `antigen theme {{ zsh_antigen_theme }}` — line ~86
  - `POWERLEVEL9K_*` config block — lines ~134-191 (rendered unconditionally today)
  - `source ~/.p10k.zsh` — lines ~204-207
- **Install patterns to mirror** (`tasks/install.yml`): home-bin dir handling
  (`zsh_fzf_path` = `$HOME/bin`, already added to `zsh_path`/PATH via `defaults/main.yml`),
  `which <bin>` idempotence check, `get_url` + `creates:` guard, `become_user: "{{ zsh_user }}"`.
- **vars/main.yml** derives bool/url facts (e.g. `zsh_powerlevel9k_*_bool`, `zsh_fzf_url`,
  `zsh_fzf_arch`) — the place to add the normalized starship flag and the install URL/arch.
- **Task includes** live in `tasks/main.yml` (install → configure → post-install → shared).
- **Tests = molecule**: docker driver, `molecule test --all` in `.gitlab-ci.yml`. Scenarios:
  `default`, `shared`, `user`, `resources` (shared converge/prepare). **No verifier exists yet**
  (no `verify.yml`, no testinfra) — "passing" currently means converge + idempotence across
  Debian10 / Ubuntu16.04/18.04/20.04 / CentOS8.
- Relevant existing prompt vars to reuse for the toml preset: `zsh_powerlevel9k_left_prompt`,
  `zsh_powerlevel9k_right_prompt`, `zsh_powerlevel9k_dir_foreground/background`,
  `zsh_powerlevel9k_context_default_*` / `_root_*`, `zsh_powerlevel9k_vcs_*`,
  `zsh_powerlevel9k_command_execution_time_*`, `zsh_command_time_min_seconds`,
  `zsh_powerlevel9k_hide_host_on_local`, `zsh_powerlevel9k_prompt_on_newline`.

## Development Approach
- **Testing approach**: Regular (code first, then molecule scenario + verify.yml). For this role,
  "tests" = molecule converge/idempotence plus explicit `verify.yml` assertions on the rendered
  `.zshrc` / `starship.toml` and installed binary.
- Complete each task fully before moving to the next; small, focused changes.
- **Maintain backward compatibility**: `zsh_theme` defaults to `powerlevel10k`; with defaults
  unchanged the rendered `.zshrc` must be byte-equivalent to today's output (no spurious diff).
- After each task: render/converge the relevant molecule scenario (or `--syntax-check` +
  template render) and confirm no errors before proceeding.
- **Update this plan file if scope changes during implementation.**

## Testing Strategy
- **Unit-equivalent**: Jinja template correctness verified by molecule converge (template render
  fails the play on error). Where feasible, add focused assertions in `verify.yml`.
- **E2E (molecule)**: new `molecule/starship` scenario with `zsh_theme: starship`, plus a
  `verify.yml` asserting: starship binary installed & on PATH; `.zshrc` contains
  `starship init zsh`; `.zshrc` contains **no** `POWERLEVEL9K_` lines and no p10k instant-prompt
  block; `~/.config/starship.toml` exists and is non-empty. The existing `default`/`shared`/`user`
  scenarios must keep passing unchanged (powerlevel10k path).
- All scenarios run via `molecule test --all` (CI) — must pass before the plan is complete.

## Progress Tracking
- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- Keep this plan in sync with actual work.

## What Goes Where
- **Implementation Steps** (checkboxes): vars, tasks, templates, molecule scenario/verify, docs —
  all automatable in this repo.
- **Post-Completion** (no checkboxes): manual visual check of the starship prompt in a real
  terminal with a Nerd Font; macOS verification on real hardware (molecule is Linux/docker only).

## Implementation Steps

### Task 1: Add `zsh_theme` selector variable and normalized flag
- [x] add `zsh_theme: powerlevel10k` to `defaults/main.yml` near the theme settings (with a
      comment listing valid values: `powerlevel10k`, `starship`), keeping `zsh_antigen_theme`
      as-is for backward compatibility.
- [x] add starship defaults to `defaults/main.yml`: `zsh_starship_version` (pinned, e.g.
      `"1.23.0"`), `zsh_starship_path: "$HOME/bin"`, `zsh_starship_manage_config: yes`,
      `zsh_starship_config: ""` (raw verbatim override; empty = use generated preset).
- [x] add to `vars/main.yml`: `zsh_theme_is_starship: "{{ zsh_theme == 'starship' }}"`, plus
      starship download facts mirroring fzf (`zsh_starship_arch`, `zsh_starship_url` or the
      install-script invocation inputs) and `zsh_starship_path_absolute`
      (`zsh_starship_path | replace('$HOME', '~' + zsh_user)`).
- [x] confirm the home-bin dir (`$HOME/bin`) is on PATH for starship via existing `zsh_path`
      (it already includes `zsh_fzf_path`); if starship uses a different dir, add it to `zsh_path`.
      (starship uses `$HOME/bin` = `zsh_fzf_path`, already in `zsh_path` — no change needed.)
- [x] run `ansible-playbook --syntax-check playbook.yml` (or molecule `default` converge) — must
      pass before Task 2. (syntax-check via role path passes; new vars render for both theme values.)

### Task 2: Install the starship binary (`tasks/starship.yml`)
- [ ] create `tasks/starship.yml`: idempotent install of starship to `zsh_starship_path` using the
      official installer (`curl -sS https://starship.rs/install.sh | sh -s -- --yes --version
      v{{ zsh_starship_version }} --bin-dir {{ zsh_starship_path_absolute }}`), guarded by a
      `which starship` / version check so it only runs when missing or version-mismatched
      (`changed_when` accurate; `become_user: "{{ zsh_user }}"`).
- [ ] ensure the bin dir exists (reuse the `file: state=directory` pattern from `install.yml`).
- [ ] handle macOS vs Linux the same way (installer supports both); do not break the
      powerlevel10k path when starship is unselected.
- [ ] include `tasks/starship.yml` from `tasks/main.yml` with `when: zsh_theme == 'starship'`
      and appropriate tags (`zsh`, `install`).
- [ ] converge `molecule/starship` (created in Task 5; until then, a temporary local converge with
      `zsh_theme: starship`) and assert starship binary is present — must pass before Task 3.
      `[x] tests deferred to Task 5 verify.yml where starship binary presence is asserted`

### Task 3: Branch `templates/zshrc.j2` on theme
- [ ] replace the literal `zsh_antigen_theme == "romkatv/powerlevel10k powerlevel10k"` guards with
      `zsh_theme == 'powerlevel10k'` for: the instant-prompt header block, the
      `antigen theme {{ zsh_antigen_theme }}` line, the entire `POWERLEVEL9K_*` block, and the
      `source ~/.p10k.zsh` block.
- [ ] add a starship branch (`{% if zsh_theme == 'starship' %}`) that appends, near the end of the
      file (after `antigen apply` and after user-config sourcing), `eval "$(starship init zsh)"`,
      and exports `STARSHIP_CONFIG="$HOME/.config/starship.toml"` when `zsh_starship_manage_config`.
- [ ] ensure that with default vars (`zsh_theme: powerlevel10k`) the rendered `.zshrc` is
      unchanged vs current output (no behavioral diff for existing users).
- [ ] render the template for both `zsh_theme` values and eyeball the output (or assert via the
      Task 5 verify.yml): powerlevel10k output identical to baseline; starship output has init +
      no `POWERLEVEL9K_`.
- [ ] converge `molecule/default` (p10k) — must stay green before Task 4.

### Task 4: Generate `starship.toml` preset (`templates/starship.toml.j2`)
- [ ] create `templates/starship.toml.j2` reproducing the current p9k layout:
      left = `username` (context) + `hostname` + `directory` (dir);
      right (`right_format`) = `status` + `jobs` + `git_branch`/`git_status` (vcs) +
      `cmd_duration` (command_execution_time) + `time`.
- [ ] drive colors/behavior from existing role vars for parity: directory `fg/bg` from
      `zsh_powerlevel9k_dir_foreground/background`; username/context from
      `zsh_powerlevel9k_context_default_*` and `_root_*`; git from `zsh_powerlevel9k_vcs_*`;
      `cmd_duration.min_time` = `zsh_command_time_min_seconds * 1000` (ms) with style from
      `zsh_powerlevel9k_command_execution_time_*`; `hostname.ssh_only` from
      `zsh_powerlevel9k_hide_host_on_local`; `add_newline` from `zsh_powerlevel9k_prompt_on_newline`.
- [ ] add a task in `tasks/starship.yml` (or `tasks/configure.yml` gated on starship) to write
      `~/.config/starship.toml`: render `starship.toml.j2` when `zsh_starship_manage_config and not
      zsh_starship_config`; write `zsh_starship_config` verbatim (copy/content) when it is set;
      create `~/.config` dir with correct owner/group; `backup: yes`.
- [ ] skip the toml entirely when `zsh_theme != 'starship'`.
- [ ] converge `molecule/starship` and assert `~/.config/starship.toml` is rendered and non-empty
      (asserted in Task 5 verify.yml) — must pass before Task 5.

### Task 5: Add `molecule/starship` scenario + verify.yml (E2E)
- [ ] create `molecule/starship/molecule.yml` (mirror `shared`/`default`: docker, same platform
      images) with `provisioner.inventory.group_vars.all` setting `zsh_user: root` and
      `zsh_theme: starship` (reuse `../resources/prepare.yml`; converge `../resources/converge.yml`).
- [ ] create `molecule/starship/verify.yml` asserting: `starship --version` succeeds / binary on
      PATH; `.zshrc` contains `starship init zsh`; `.zshrc` contains no `POWERLEVEL9K_` and no
      p10k instant-prompt block; `~/.config/starship.toml` exists and is non-empty.
- [ ] reference `verify.yml` from `molecule.yml` (`verifier: name: ansible`) so
      `molecule test` runs it.
- [ ] run `molecule converge -s starship && molecule verify -s starship` (or
      `molecule test -s starship`) — all assertions must pass.
- [ ] run `molecule test -s default` to confirm the powerlevel10k path is still green.

### Task 6: Documentation
- [ ] update `README.md`: document `zsh_theme` (default `powerlevel10k`, option `starship`),
      `zsh_starship_version`, `zsh_starship_path`, `zsh_starship_manage_config`,
      `zsh_starship_config`; note starship needs a Nerd Font and is installed as a standalone
      binary; mention backward compatibility (defaults unchanged).
- [ ] update `meta/main.yml` description to mention selectable starship prompt (optional).
- [ ] add a CHANGELOG.md entry consistent with existing format.

### Task 7: Verify acceptance criteria
- [ ] verify Overview requirements: theme selectable; default = powerlevel10k; starship installs +
      activates; toml preset rendered; existing users unaffected.
- [ ] verify backward compat: with default vars the rendered `.zshrc` matches pre-change output.
- [ ] run `molecule test --all` — every scenario (default, shared, user, starship) must pass.
- [ ] confirm no YAML/Jinja syntax issues (`ansible-playbook --syntax-check`); fix any lint-level
      issues surfaced.

*Note: ralphex automatically moves completed plans to `docs/plans/completed/`.*

## Technical Details
- **Selector**: `zsh_theme ∈ {powerlevel10k, starship}`; `zsh_antigen_theme` remains the antigen
  theme string used only on the powerlevel10k path. `zsh_theme_is_starship` is the derived gate.
- **Install**: official `install.sh`, version-pinned (`v{{ zsh_starship_version }}`), `--bin-dir`
  = `zsh_starship_path_absolute`; idempotent via `which starship` + version compare; runs as
  `zsh_user`; only when `zsh_theme == 'starship'`.
- **zshrc activation**: `eval "$(starship init zsh)"` placed after `antigen apply` and user-config
  sourcing; `export STARSHIP_CONFIG` when role manages the toml. starship's own instant prompt is
  not used (powerlevel10k instant-prompt block is skipped on the starship path).
- **starship.toml**: starship style strings accept 0–255 color codes (e.g. `"fg:255 bg:240"`),
  matching the role's numeric p9k color vars. `right_format` carries the right-prompt segments.
- **Color/behavior mapping source of truth**: existing `zsh_powerlevel9k_*` vars, so a user who
  customized p9k colors gets a matching starship prompt without re-specifying them.

## Post-Completion
*Manual / external — no checkboxes*

**Manual verification:**
- Open a real terminal with a Nerd Font and confirm the starship prompt renders the expected
  segments/colors (icons/glyphs can't be verified in docker molecule).
- Verify on macOS hardware (molecule covers Linux/docker only): starship installs to `$HOME/bin`
  and the prompt activates.
- Sanity-check switching a host from powerlevel10k → starship and back leaves a clean `.zshrc`.
