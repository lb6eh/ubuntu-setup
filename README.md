# ubuntu-setup

Sets up an Ubuntu (incl. WSL) shell with:

- **zsh** + powerlevel10k, zinit, autosuggestions, syntax highlighting, fzf-tab
- **tmux** + TPM, tmux-sensible, tmux-yank, nord theme (default `Ctrl-b` prefix)
- **neovim**, **eza**, **xsel**
- Latest **fzf** and **zoxide** from GitHub releases

## Install

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/lb6eh/ubuntu-setup/main/setup.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/lb6eh/ubuntu-setup.git
cd ubuntu-setup
./setup.sh
```

Run as your normal user (not root); it uses `sudo` when needed. When it finishes, open a new terminal or run `exec zsh`.

## What it does

1. `apt update && apt upgrade`, then installs `curl wget git zsh tmux neovim eza xsel`
2. Installs/updates fzf and zoxide to the latest release in `/usr/local/bin` (skipped if already latest)
3. Installs `.zshrc`, `.p10k.zsh` and `.tmux.conf` to `~` (existing files are backed up as `*.bak.<timestamp>`)
4. Installs/updates TPM and tmux plugins
5. Pre-installs zsh plugins and sets zsh as the login shell
6. Verifies everything and exits non-zero if something is missing

Safe to re-run; it only changes what is missing or outdated.

## Tips

- `prefix + r` reloads the tmux config; `Alt + arrows` switches panes
- Run `p10k configure` to customize the prompt
- `cd <partial>` uses zoxide; `Ctrl-r` / `Ctrl-t` use fzf
