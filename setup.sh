#!/usr/bin/env bash
# Ubuntu shell setup: zsh + powerlevel10k (zinit), tmux + TPM, neovim, eza, latest fzf and zoxide.
#
# Usage:
#   From a clone:  ./setup.sh                     (uses .zshrc/.p10k.zsh/.tmux.conf next to this script)
#   Remote:        curl -fsSL https://raw.githubusercontent.com/lb6eh/ubuntu-setup/main/setup.sh | bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/lb6eh/ubuntu-setup/main}"
CONFIG_FILES=(.zshrc .p10k.zsh .tmux.conf)
APT_PACKAGES=(ca-certificates curl wget git tar zsh tmux neovim eza xsel)
TPM_DIR="$HOME/.tmux/plugins/tpm"
TMUX_PLUGINS=(tmux-sensible tmux-yank nord-tmux)
TS="$(date +%Y%m%d%H%M%S)"
USER_NAME="$(id -un)"

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m[!!]\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[1;31m[xx]\033[0m %s\n' "$*" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

preflight() {
  info "Preflight checks"
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root (sudo is used where needed)."
  command -v sudo >/dev/null || die "sudo is required."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || warn "Not Ubuntu (${ID:-unknown}); continuing anyway."
  ok "${PRETTY_NAME:-unknown OS}"

  case "$(uname -m)" in
    x86_64)  FZF_ARCH=amd64; ZOXIDE_ARCH=x86_64 ;;
    aarch64) FZF_ARCH=arm64; ZOXIDE_ARCH=aarch64 ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
  ok "Architecture $(uname -m)"

  sudo -v || die "sudo authentication failed."
}

install_apt_packages() {
  info "Updating system and installing apt packages"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  local pkgs=() p
  for p in "${APT_PACKAGES[@]}"; do
    if apt-cache show "$p" >/dev/null 2>&1; then pkgs+=("$p"); else warn "Package '$p' not available in apt; skipping."; fi
  done
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  ok "Installed: ${pkgs[*]}"
}

# Resolves the latest release tag (e.g. v0.65.2) via GitHub's redirect, avoiding API rate limits.
latest_tag() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")" || return 1
  [[ "$url" == */tag/* ]] || return 1
  printf '%s\n' "${url##*/}"
}

install_fzf() {
  info "fzf"
  local tag ver current file
  tag="$(latest_tag junegunn/fzf)" || die "Could not resolve latest fzf release."
  ver="${tag#v}"
  current="$(fzf --version 2>/dev/null | awk '{print $1}' || true)"
  if [[ "$current" == "$ver" ]]; then ok "fzf $ver is already the latest"; return; fi

  file="fzf-${ver}-linux_${FZF_ARCH}.tar.gz"
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/${tag}/${file}" -o "$WORK/$file"
  if curl -fsSL "https://github.com/junegunn/fzf/releases/download/${tag}/fzf_${ver}_checksums.txt" -o "$WORK/fzf_sums.txt"; then
    (cd "$WORK" && grep " ${file}\$" fzf_sums.txt | sha256sum -c --quiet -) || die "fzf checksum mismatch."
    ok "Checksum verified"
  else
    warn "No checksum file published for fzf $ver; skipping checksum verification."
  fi
  mkdir -p "$WORK/fzf" && tar -xzf "$WORK/$file" -C "$WORK/fzf"
  sudo install -m 0755 "$WORK/fzf/fzf" /usr/local/bin/fzf
  hash -r
  ok "fzf ${current:-none} -> $ver"
}

install_zoxide() {
  info "zoxide"
  local tag ver current file bin
  tag="$(latest_tag ajeetdsouza/zoxide)" || die "Could not resolve latest zoxide release."
  ver="${tag#v}"
  current="$(zoxide --version 2>/dev/null | awk '{print $2}' || true)"
  current="${current#v}"
  if [[ "$current" == "$ver" ]]; then ok "zoxide $ver is already the latest"; return; fi

  # Remove an older .deb install so it doesn't shadow or conflict with the new binary.
  if dpkg -s zoxide >/dev/null 2>&1; then sudo apt-get remove -y zoxide; fi

  file="zoxide-${ver}-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz"
  curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/${tag}/${file}" -o "$WORK/$file"
  mkdir -p "$WORK/zoxide" && tar -xzf "$WORK/$file" -C "$WORK/zoxide"
  bin="$(find "$WORK/zoxide" -type f -name zoxide | head -n1)"
  [[ -n "$bin" ]] || die "zoxide binary not found in $file."
  sudo install -m 0755 "$bin" /usr/local/bin/zoxide
  hash -r
  ok "zoxide ${current:-none} -> $ver"
}

install_config() {
  local name="$1" dest="$HOME/$1" src="$WORK/$1"
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/$name" ]]; then
    cp "$SCRIPT_DIR/$name" "$src"
  else
    curl -fsSL "$BASE_URL/$name" -o "$src" || die "Download failed: $BASE_URL/$name"
  fi
  [[ -s "$src" ]] || die "$name is empty."
  sed -i 's/\r$//' "$src"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then ok "~/$name unchanged"; return; fi
  if [[ -e "$dest" ]]; then
    cp -a "$dest" "$dest.bak.$TS"
    warn "Backed up existing ~/$name to ~/$name.bak.$TS"
  fi
  install -m 0644 "$src" "$dest"
  ok "Installed ~/$name"
}

install_configs() {
  info "Config files"
  local f
  for f in "${CONFIG_FILES[@]}"; do install_config "$f"; done
}

install_tmux_plugins() {
  info "tmux plugins (TPM)"
  if [[ -d "$TPM_DIR/.git" ]]; then
    git -C "$TPM_DIR" pull --ff-only --quiet && ok "TPM updated"
  else
    git clone --quiet --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" && ok "TPM cloned"
  fi
  TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" "$TPM_DIR/bin/install_plugins"
  TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" "$TPM_DIR/bin/update_plugins" all >/dev/null || warn "TPM plugin update failed."
}

prewarm_zsh() {
  info "Pre-installing zsh plugins (zinit, powerlevel10k)"
  if TERM=xterm-256color zsh -i -c exit </dev/null >/dev/null 2>&1; then
    ok "zsh plugins installed"
  else
    warn "zsh pre-warm failed; plugins will be installed on first zsh start."
  fi
}

set_default_shell() {
  info "Default shell"
  local zsh_path current
  zsh_path="$(command -v zsh)"
  grep -qxF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  current="$(getent passwd "$USER_NAME" | cut -d: -f7)"
  if [[ "$current" == "$zsh_path" ]]; then ok "Already zsh"; return; fi
  sudo chsh -s "$zsh_path" "$USER_NAME"
  ok "Changed $current -> $zsh_path"
}

verify() {
  info "Verification"
  local failed=0 cmd p f

  for cmd in git curl wget zsh tmux nvim eza xsel fzf zoxide; do
    if command -v "$cmd" >/dev/null; then ok "$cmd ($(command -v "$cmd"))"; else warn "$cmd missing"; failed=1; fi
  done

  [[ "$(command -v fzf)" == /usr/local/bin/fzf ]] || { warn "fzf on PATH is not /usr/local/bin/fzf (shadowed)"; failed=1; }
  fzf --zsh >/dev/null 2>&1 || { warn "fzf does not support 'fzf --zsh' (too old)"; failed=1; }

  for f in "${CONFIG_FILES[@]}"; do
    [[ -f "$HOME/$f" ]] && ok "~/$f present" || { warn "~/$f missing"; failed=1; }
  done
  zsh -n "$HOME/.zshrc" && ok ".zshrc syntax OK" || { warn ".zshrc has syntax errors"; failed=1; }
  if grep -Eq '^[^#]*prefix[[:space:]]+C-a' "$HOME/.tmux.conf"; then warn "tmux prefix is not Ctrl-b"; failed=1; else ok "tmux prefix is Ctrl-b"; fi

  [[ -x "$TPM_DIR/tpm" ]] && ok "TPM installed" || { warn "TPM missing"; failed=1; }
  for p in "${TMUX_PLUGINS[@]}"; do
    [[ -d "$HOME/.tmux/plugins/$p" ]] && ok "tmux plugin $p" || { warn "tmux plugin $p missing"; failed=1; }
  done

  [[ "$(getent passwd "$USER_NAME" | cut -d: -f7)" == "$(command -v zsh)" ]] && ok "Login shell is zsh" || { warn "Login shell is not zsh"; failed=1; }

  info "Versions"
  printf '  %s\n' "$(tmux -V)" "$(nvim --version | head -n1)" "fzf $(fzf --version | awk '{print $1}')" "$(zoxide --version)" "$(zsh --version)"

  return "$failed"
}

main() {
  preflight
  install_apt_packages
  install_fzf
  install_zoxide
  install_configs
  install_tmux_plugins
  prewarm_zsh
  set_default_shell
  if verify; then
    info "Done. Open a new terminal (or run 'exec zsh') to start using it."
  else
    die "Setup finished with problems; see warnings above."
  fi
}

main "$@"