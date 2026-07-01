Tested on Ubuntu 20.04, Ubuntu 22.04, Ubuntu 24.04, MacOS 14.4.

Tested long time ago: Ubuntu 18.04, MacOS 10.12, CentOS 8

**For upgrade from viasite-ansible.zsh 1.x, 2.x to 3.0 see [below](#upgrade).**



## Zero-knowledge install:
If you are not familiar with Ansible, you can just execute [install.sh](install.sh) on the target machine. It detects the OS (Ubuntu/Debian or macOS), installs Ansible, and sets up zsh for the current user:
```
curl https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/install.sh | bash
```

- **Ubuntu/Debian**: installs pip3, Ansible (into `~/ansible-venv`) and zsh.
- **macOS**: requires `brew` and `python`; installs Ansible via brew and zsh.
- It runs non-interactively when possible — you are only asked for a password if `sudo` is not passwordless.
- To also provision the **root** user, set `ZSH_INSTALL_ROOT=1`:
  ```
  curl https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/install.sh | ZSH_INSTALL_ROOT=1 bash
  ```

> The previous `install-macos.sh` URL still works — it now forwards to `install.sh`.

Then [configure terminal application](#configure-terminal-application).


## Includes:
- zsh
- [antigen](https://github.com/zsh-users/antigen)
- [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh)
- [powerlevel9k/powerlevel10k theme](https://github.com/romkatv/powerlevel10k) (default prompt)
- [starship prompt](https://starship.rs/) (optional, via `zsh_theme: starship`)
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
- [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)
- [unixorn/autoupdate-antigen.zshplugin](https://github.com/unixorn/autoupdate-antigen.zshplugin)
- [sorenson-axial/fzf-widgets](https://github.com/sorenson-axial/fzf-widgets)
- [urbainvaes/fzf-marks](https://github.com/popstas/urbainvaes/fzf-marks)

## Features
- selectable prompt theme: powerlevel10k (default) or starship (see [Prompt theme](#prompt-theme))
- customize powerlevel9k theme prompt segments and colors
- default colors tested with solarized dark and default grey terminal in putty
- add custom prompt elements from yml
- custom zsh config with `~/.zshrc.local` or `/etc/zshrc.local`
- load `/etc/profile.d` scripts
- install only plugins that useful for your machine. For example, plugin `docker` will not install if you have not Docker

## Prompt theme
The role supports two selectable prompt themes via the `zsh_theme` variable:

- `powerlevel10k` (**default**) — the classic antigen-bundled [powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt.
- `starship` — the cross-shell [starship](https://starship.rs/) prompt, installed as a standalone binary.

The default stays `powerlevel10k`, so existing deployments are unaffected (fully backward compatible — with default vars the rendered `.zshrc` is unchanged).

To switch to starship:
``` yaml
- hosts: all
  vars:
    zsh_theme: starship
  roles:
    - viasite-ansible.zsh
```

When `starship` is selected, the powerlevel10k/powerlevel9k wiring is skipped, the starship binary is
installed to `zsh_starship_path`, the prompt is activated in `.zshrc` with `eval "$(starship init zsh)"`,
and a `~/.config/starship.toml` is generated to reproduce the role's p9k-style prompt segments and colors.

starship-related variables:

| Variable | Default | Description |
| --- | --- | --- |
| `zsh_theme` | `powerlevel10k` | Prompt theme: `powerlevel10k` or `starship`. |
| `zsh_starship_version` | `"1.23.0"` | Pinned starship binary version to install. |
| `zsh_starship_path` | `"$HOME/bin"` | Install directory for the starship binary (already on PATH; `/usr/local/bin` when `zsh_shared`). |
| `zsh_starship_manage_config` | `yes` | Render and manage `~/.config/starship.toml` (and export `STARSHIP_CONFIG`). Set `no` to leave the config alone. |
| `zsh_starship_config` | `""` | Raw verbatim `starship.toml` content. When set, it is written as-is instead of the generated preset (and no merge happens). |
| `zsh_starship_config_user_file` | `~<user>/.config/starship.user.toml` | User-editable override file. If present, its keys are deep-merged **over** the generated preset, so you can tweak a few settings while keeping the rest. |
| `zsh_starship_config_user` | `""` | Inline `starship.toml` override string. Merged **last**, so it beats both the generated preset and the user file. |

### Customizing the generated config

Starship reads a single config file and has no include/merge mechanism of its own, so the role
deep-merges your overrides into the generated preset **at provision time** and writes the result to
`~/.config/starship.toml`. You only specify the keys you want to change — everything else stays as
the generated preset.

Override precedence (low → high):

```
generated preset  →  zsh_starship_config_user_file  →  zsh_starship_config_user
```

A table you override is merged key-by-key (your keys win); a scalar or array replaces the generated
value outright. To override a whole prompt without merging, use `zsh_starship_config` instead — it is
written verbatim and bypasses the merge entirely.

Example — keep the generated prompt but change the right side and restyle the command-duration
segment (as an inline override in host/group vars):

```yaml
zsh_starship_config_user: |
  right_format = "$status$cmd_duration$time"

  [cmd_duration]
  style = "fg:green"
```

The same content can instead live in a host-side file (default `~/.config/starship.user.toml`) that
users edit directly; it is merged on every run if present. If both are set, the inline
`zsh_starship_config_user` wins over the file.

Requirements/notes for the merge:

- Needs Python 3.11+ on the managed host (uses the stdlib `tomllib`); no extra pip/collection deps.
- The merged file is re-serialized, so the generated header comment is dropped and strings are
  normalized (single → double quotes, inline tables expanded to `[table.subtable]`). The result is
  equivalent, valid TOML.

Note: like powerlevel10k, starship needs a [Nerd Font](https://www.nerdfonts.com/) installed in your terminal
to render the prompt icons/glyphs correctly.

## 1.5 mins demo
![1.5 mins demo](https://github.com/popstas/popstas.github.io/blob/master/images/2017-03/ansible-role-zsh-demo.gif?raw=true)

## Color schemes
![colors demo](https://github.com/popstas/popstas.github.io/blob/master/images/2017-03/ansible-role-zsh-colors.gif?raw=true)

## Midnight Commander Solarized Dark skin
If you are using Solarized Dark scheme and `mc`, you should want to install skin, then set `zsh_mc_solarized_skin: yes`


## Demo install in Vagrant
You can test work of role before install in real machine.
Just execute `vagrant up`, then `vagrant ssh` for enter in virtual machine.

Note: you cannot install vagrant on VPS like Digital Ocean or in Docker. Use local machine for it.
[Download](https://www.vagrantup.com/downloads.html) and install vagrant for your operating system.



## Testing with Molecule

The role ships [Molecule](https://ansible.readthedocs.io/projects/molecule/) scenarios
(`default`, `shared`, `user`, `starship`) that converge the role in Docker and verify
the result. They require Docker and Python 3.

```bash
# one-time setup
python3 -m venv .venv
.venv/bin/pip install molecule "molecule-plugins[docker]" docker ansible-core pytest pytest-testinfra
.venv/bin/ansible-galaxy collection install community.docker ansible.posix

# run a scenario (activate the venv so the testinfra verifier finds pytest)
source .venv/bin/activate
molecule test -s default    # also: shared, user, starship
```

Note: the venv must be activated (or `.venv/bin` on `PATH`) — the `default`
scenario's testinfra verifier shells out to `pytest` by name.



## Install for real machine
Zero-knowledge install: see [above](#zero-knowledge-install).

### Manual install

0. [Install Ansible](http://docs.ansible.com/ansible/intro_installation.html).
For Ubuntu:
``` bash
sudo apt update
sudo apt install python3-pip -y
sudo pip3 install ansible
```

1. Download role:
```
ansible-galaxy install viasite-ansible.zsh --force
```

2. Write playbook or use [playbook.yml](playbook.yml):
```
- hosts: all
  vars:
    zsh_antigen_bundles_extras:
      - nvm
      - joel-porquet/zsh-dircolors-solarized
    zsh_autosuggestions_bind_key: "^U"
  roles:
    - viasite-ansible.zsh
```

3. Provision playbook:
```
ansible-playbook -i "localhost," -c local -K playbook.yml
```

If you want to provision role for root user on macOS, you should install packages manually:
```
brew install zsh git wget
```

It will install zsh environment for ansible remote user. If you want to setup zsh for other users,
you should define variable `zsh_user`:

Via playbook:
```
- hosts: all
  roles:
    - { role: viasite-ansible.zsh, zsh_user: otheruser }
    - { role: viasite-ansible.zsh, zsh_user: thirduser }
```

Or via command:
```
ansible-playbook -i hosts zsh.yml -e zsh_user=otheruser
```

4. Install fzf **without shell extensions**, [download binary](https://github.com/junegunn/fzf-bin/releases)
or `brew install fzf` for macOS.

Note: I don't use `tmux-fzf` and don't tested work of it.



## Multiuser shared install
If you have 10+ users on host, probably you don't want manage tens of configurations and thousands of files.

In this case you can deploy single zsh config and include it to all users.

It causes some limitations:

- Users have read only access to zsh config
- Users cannot disable global enabled bundles
- Possible bugs such cache write permission denied
- Possible bugs with oh-my-zsh themes

For install shared configuration you should set `zsh_shared: yes`.
Configuration will install to `/usr/share/zsh-config`, then you just can include to user config:

## Install for all users
Set `zsh_source_for_all_users: yes`

``` bash
source /usr/share/zsh-config/.zshrc
```

You can still provision custom configs for several users.



## Configure
You should not edit `~/.zshrc`! 
Add your custom config to `~/.zshrc.local` (per user) or `/etc/zshrc.local` (global).
`.zshrc.local` will never touched by ansible.


### Configure terminal application
1. Download [powerline fonts](https://github.com/powerline/fonts), install font that you prefer.
You can see screenshots [here](https://github.com/powerline/fonts/blob/master/samples/All.md).

2. Set color scheme.

Personaly, I prefer Solarized Dark color sceme, Droid Sans Mono for Powerline in iTerm and DejaVu Sans Mono in Putty.

#### iTerm
Profiles - Text - Change Font - select font "for Powerline"

Profiles - Colors - Color Presets... - select Solarized Dark

#### Putty
Settings - Window - Appearance - Font settings

You can download [Solarized Dark for Putty](https://github.com/altercation/solarized/tree/master/putty-colors-solarized).

#### Gnome Terminal
gnome-terminal have built-in Solarized Dark, note that you should select both background color scheme and palette scheme.



### Hotkeys
You can view hotkeys in [defaults/main.yml](defaults/main.yml), `zsh_hotkeys`.

Sample hotkey definitions:
``` yaml
- { hotkey: '^r', action: 'fzf-history' }
# with dependency of bundle
- { hotkey: '`', action: autosuggest-accept, bundle: zsh-users/zsh-autosuggestions }
```

Useful to set `autosuggest-accept` to <kbd>`</kbd> hotkey, but it conflicts with Midnight Commander (break Ctrl+O subshell).

You can add your custom hotkeys without replace default hotkeys with `zsh_hotkeys_extras` variable:
``` yaml
zsh_hotkeys_extras:
  - { hotkey: '^[^[[D', action: backward-word } # alt+left
  - { hotkey: '^[^[[C', action: forward-word } # alt+right
  # Example <Ctrl+.><Ctrl+,> inserts 2nd argument from end of prev. cmd
  - { hotkey: '^[,', action: copy-earlier-word } # ctrl+,
```

### Aliases
You can use aliases for your command with easy deploy.
Aliases config mostly same as hotkeys config:

``` yaml
zsh_aliases:
  - { alias: 'dfh', action: 'df -h | grep -v docker' }
# with dependency of bundle and without replace default asiases
- zsh_aliases_extra
  - { alias: 'dfh', action: 'df -h | grep -v docker', bundle: }
```

#### Default hotkeys from plugins:
- <kbd>&rarr;</kbd> - accept autosuggestion
- <kbd>Ctrl+Z</kbd> - move current application to background, press again for return to foreground
- <kbd>Ctrl+G</kbd> - jump to bookmarked directory. Use `mark` in directory for add to bookmarks
- <kbd>Ctrl+R</kbd> - show command history
- <kbd>Ctrl+@</kbd> - show all fzf-widgets
- <kbd>Ctrl+@,C</kbd> - fzf-change-dir, press fast!
- <kbd>Ctrl+\\</kbd> - fzf-change-recent-dir
- <kbd>Ctrl+@,G</kbd> - fzf-change-repository
- <kbd>Ctrl+@,F</kbd> - fzf-edit-files
- <kbd>Ctrl+@,.</kbd> - fzf-edit-dotfiles
- <kbd>Ctrl+@,S</kbd> - fzf-exec-ssh (using your ~/.ssh/config)
- <kbd>Ctrl+@,G,A</kbd> - fzf-git-add-file
- <kbd>Ctrl+@,G,B</kbd> - fzf-git-checkout-branch
- <kbd>Ctrl+@,G,D</kbd> - fzf-git-delete-branches



## Configure bundles
You can check default bundles in [defaults/main.yml](defaults/main.yml#L37).
If you like default bundles, but you want to add your bundles, use `zsh_antigen_bundles_extras` variable (see example playbook above).
If you want to remove some default bundles, you should use `zsh_antigen_bundles` variable.

Format of list matches [antigen](https://github.com/zsh-users/antigen#antigen-bundle). All bellow variants valid:
``` yaml
- docker # oh-my-zsh plugin
- zsh-users/zsh-autosuggestions # plugin from github
- zsh-users/zsh-autosuggestions@v0.3.3 # plugin from github with fixed version
- ~/projects/zsh/my-plugin --no-local-clone # plugin from local directory
```

Note that bundles can use conditions for load. There are two types of conditions:

1. Command conditions. Just add `command` to bundle:
``` yaml
- { name: docker, command: docker }
- name: docker-compose
  command: docker-compose
```
Bundles `docker` and `docker-compose` will be added to config only if commands exists on target system.

2. When conditions. You can define any ansible conditions as you define in `when` in tasks:
``` yaml
# load only for zsh >= 4.3.17
- name: zsh-users/zsh-syntax-highlighting
  when: "{{ zsh_version is version_compare('4.3.17', '>=') }}"
# load only for macOS
- { name: brew, when: "{{ ansible_os_family != 'Darwin' }}" }
```
Note: you should wrap condition in `"{{ }}"`


## Custom config
You can add any code in variable `zsh_custom_before`, `zsh_custom_after`.

- zsh_custom_before - before include antigen.zsh
- zsh_custom_after - before include ~/.zshrc.local

## Upgrade
viasite-ansible.zsh v3.0 introduces antigen v2.0, it don't have backward compatibility to antigen 1.x.

I don't spent much time for smooth upgrade, therefore you probably should do some manual actions:
if powerlevel9k prompt don't loaded after provision role, you should execute `antigen reset`.

After reopen shell all should be done.

### Downgrade to antigen v1
Antigen v2 much faster (up to 2x more faster startup), but if something went wrong, you can downgrade to antigen v1,
see note for zsh 4.3 users below.

### For users with zsh 4.x
Antigen v2 not work on zsh < 5.0, if you use zsh 4.x, please add to you playbook:
``` yaml
zsh_antigen_version: v1.4.1
```


## Known bugs
### `su username` caused errors
See [antigen issue](https://github.com/zsh-users/antigen/issues/136).
If both root and su user using antigen, you should use `su - username` in place of `su username`.

Or you can use bundled alias `suser`.

Also, you can try to fix it, add to `~/.zshrc.local`:
```
alias su='su -'
```
But this alias can break you scripts, that using `su`.

