#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES="${ASSUME_YES:-0}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
    [[ "$ASSUME_YES" == "1" ]] && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

############
### Help ###
############

show_help() {
    cat > /dev/null << 'EOF'
Usage: ./configure.sh [stages...] [option]

Stages (default stages run if omitted; grub and wallpaper-engine are opt-in):
  repo             Configure repo mirror + system update
  zsh              Install and configure zsh, oh-my-zsh, starship, rustup/hyperfine
  kitty            Install and configure kitty, register as default terminal
  ghostty          Install and configure ghostty, register as default terminal
  packages         Install misc packages (btop, neovim)
  vscode           Install VS Code
  firefox          Set Firefox default start page
  chrony           Install and configure chrony (NTP client)
  chrome           Install Google Chrome
  nextdns          Install and configure NextDNS
  ssh              Install and configure OpenSSH server
  hangul           Configure Korean (Hangul) input
  gnome-ext        Install and configure GNOME Shell extensions
  gnome            Configure GNOME settings (theme, touchpad, workspaces, etc.)
  keybindings      Configure keyboard shortcuts
  font             Install fonts
  grub             Configure GRUB (opt-in, asks for confirmation)
  wallpaper-engine Build and install linux-wallpaperengine (opt-in)

Presets:
  all              Run every stage above, including grub and wallpaper-engine
  headless         Run following stages only: repo, zsh, chrony, ssh

Options:
  -y, --yes        Assume yes to all confirmation prompts
  -h, --help       Show this help message

Examples: ./configure.sh
          ./configure.sh gnome-ext gnome keybindings
          ./configure.sh all --yes
EOF
}

########################################
### Configure repo and update system ###
########################################

configure_repo_n_update() {

    if [[ ! -f "/etc/yum.repos.d/fedora.repo.bak" ]]; then
        log "Configuring repository mirror..."
        sudo sed -i.bak \
            -e 's|^metalink|#metalink|g' \
            -e 's|^#baseurl=http://download.example/pub/fedora|baseurl=https://mirror-icn.yuki.net.uk/fedora|g' \
            /etc/yum.repos.d/fedora.repo /etc/yum.repos.d/fedora-updates*
    else
        log "Repository mirror already set. Skipping..."
    fi

    log "Updating system..."
    sudo dnf update -y
}

###########
### ZSH ###
###########

setup_zsh() {

    # Install zsh
    if ! command -v zsh >/dev/null 2>&1; then
        log "Installing zsh..."
        sudo dnf install -y zsh
    else
        log "zsh already installed. ($(zsh --help | grep version)) Skipping..."
    fi

    # Install oh-my-zsh
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log "Installing oh-my-zsh..."
        RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        log "oh-my-zsh already installed. Skipping..."
    fi

    # Configure zsh plugins
    log "Configuring zsh plugins..."
    local plugins_dir="$HOME/.oh-my-zsh/custom/plugins"

    mkdir -p "$plugins_dir"
    [[ -d "$plugins_dir/zsh-defer" ]] \
        || git clone --depth 1 https://github.com/romkatv/zsh-defer "$plugins_dir/zsh-defer"
    [[ -d "$plugins_dir/zsh-syntax-highlighting" ]] \
        || git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$plugins_dir/zsh-syntax-highlighting"

    # Install starship
    if ! command -v starship >/dev/null 2>&1; then
        log "Installing starship..."
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y
    else
        log "starship already installed. ($(starship --version | head -1)) Skipping..."
    fi

    if ! command -v gcc >/dev/null 2>&1; then
        log "Installing gcc..."
        sudo dnf install -y gcc
    else
        log "gcc already installed. ($(gcc --version | head -1)) Skipping..."
    fi

    # Install rustup and hyperfine
    if ! command -v rustup >/dev/null 2>&1; then
        log "Installing rustup..."
        curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        # shellcheck disable=SC1090
        source "$HOME/.cargo/env"
    else
        log "rustup already installed. Skipping..."
    fi

    if ! command -v hyperfine >/dev/null 2>&1; then
        log "Installing hyperfine (cargo)..."
        # shellcheck disable=SC1090
        source "$HOME/.cargo/env"
        cargo install hyperfine
    else
        log "hyperfine already installed. Skipping..."
    fi

    # Configure zsh
    log "Configuring zsh..."
    cp "$REPO_DIR/zsh/.zshrc" "$HOME/.zshrc"
    cp "$REPO_DIR/zsh/.zshenv" "$HOME/.zshenv"

    log "Configuring starship..."
    mkdir -p "$HOME/.config"
    cp "$REPO_DIR/zsh/starship.toml" "$HOME/.config/starship.toml"
    cp "$REPO_DIR/zsh/starship-plain.toml" "$HOME/.config/starship-plain.toml"

    # Set default shell
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
        log "Changing default shell to zsh (chsh)..."
        sudo usermod -s "$(command -v zsh)" "$USER"
    else
        log "Default shell already zsh. Skipping..."
    fi

}

###############
### Ghostty ###
###############

setup_ghostty() {

    # Install ghostty
    if ! command -v ghostty >/dev/null 2>&1; then
        log "Adding COPR repository..."
        sudo dnf copr enable -y scottames/ghostty

        log "Installing ghostty..."
        sudo dnf install -y ghostty
    else
        log "ghostty already installed. Skipping..."
    fi

    log "Configuring ghostty..."
    mkdir -p "$HOME/.config/ghostty"
    cp "$REPO_DIR/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"

    log "Registering ghostty as default terminal..."

    # gsettings
    gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''

    # .desktop
    xdg-mime default ghostty.desktop x-scheme-handler/terminal

    # xdg-terminal-exec
    sudo dnf install -y xdg-terminal-exec
    echo 'com.mitchellh.ghostty.desktop' > "$HOME/.config/xdg-terminals.list"

    # Remove ptyxis if installed
    sudo dnf remove -y ptyxis
}

################
### Packages ###
################

setup_packages() {

    log "Installing packages (btop, neovim, git, gh)..."
    sudo dnf install -y btop neovim git gh
}

###############
### VS Code ###
###############

setup_vscode() {

    log "Importing Microsoft key..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

    log "Creating repository file..."
    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

    # Check if VS Code is installed
    if ! command -v code >/dev/null 2>&1; then
        log "Installing VS Code..."
        sudo dnf install -y code
    else
        log "VS Code is already installed. Skipping..."
    fi

    log "Registering VS Code for common code MIME types..."
    code_mimes=(
        text/x-python
        text/x-shellscript
        text/x-csrc
        text/x-c++src
        text/x-chdr
        text/x-c++hdr
        text/x-java
        text/x-rust
        text/markdown
        application/json
        application/xml
        application/javascript
        application/typescript
        text/x-go
        application/x-yaml
        text/x-yaml
        text/yaml
        text/x-toml
        text/html
        text/css
    )

    for mime in "${code_mimes[@]}"; do
        xdg-mime default code.desktop "$mime"
    done

    log "Adding 'Open in Code' in nautilus..."
    wget -qO- https://raw.githubusercontent.com/harry-cpp/code-nautilus/master/install.sh | bash
}

##############
### chrony ###
##############

configure_chrony() {

    if ! command -v chronyd >/dev/null 2>&1; then
        log "Installing chrony..."
        sudo dnf install -y chrony
    else
        log "chrony already installed. Skipping..."
    fi

    log "Configuring chrony..."
    sudo tee /etc/chrony.conf > /dev/null << 'EOF'
server ntp.kriss.re.kr iburst prefer
pool kr.pool.ntp.org iburst

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

    log "Restarting chrony service..."
    sudo systemctl restart chronyd
}

##############
### Chrome ###
##############

setup_chrome() {
    log "Enabling Fedora Workstation repositories for Google Chrome..."
    sudo dnf install -y fedora-workstation-repositories

    log "Enabling Google Chrome repository..."
    sudo dnf config-manager setopt google-chrome.enabled=1

    if ! command -v google-chrome >/dev/null 2>&1; then
        log "Installing Google Chrome..."
        sudo dnf install -y google-chrome-stable
    else
        log "Google Chrome already installed. Skipping..."
    fi
}

###############
### NextDNS ###
###############

setup_nextdns() {
    log "Adding NextDNS repository..."
    sudo curl -Ls https://repo.nextdns.io/nextdns.repo -o /etc/yum.repos.d/nextdns.repo

    if ! command -v nextdns >/dev/null 2>&1; then
        log "Installing NextDNS..."
        sudo dnf install -y nextdns
    else
        log "NextDNS already installed. Skipping..."
    fi
}

##################
### ssh-server ###
##################

configure_ssh_server() {

    if ! command -v sshd >/dev/null 2>&1; then
        log "Installing OpenSSH server..."
        sudo dnf install -y openssh-server
    else
        log "OpenSSH server already installed. Skipping..."
    fi

    log "Configuring SSH server..."

    BASE_USERNAME="${1:-$USER}"

    if [ "$BASE_USERNAME" = "root" ]; then
        PERMIT_ROOT_LOGIN="prohibit-password"
    else
        PERMIT_ROOT_LOGIN="no"
    fi

    sudo mkdir -p /etc/ssh/sshd_config.d/

    sudo tee /etc/ssh/sshd_config.d/00-security.conf > /dev/null << EOF
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
PermitRootLogin ${PERMIT_ROOT_LOGIN}
AllowUsers ${BASE_USERNAME}
MaxAuthTries 3
LoginGraceTime 60
ClientAliveInterval 30
ClientAliveCountMax 0
MaxStartups 10
AllowTcpForwarding no
X11Forwarding no
AllowAgentForwarding no
UseDNS no
PrintMotd no
TCPKeepAlive yes
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
EOF

    log "Restarting SSH server..."
    sudo systemctl restart sshd
}

#########################
### Firefox StartPage ###
#########################

configure_ff_startpage() {
    sudo mkdir -p /etc/firefox/policies
    sudo tee /etc/firefox/policies/policies.json > /dev/null << 'EOF'
{
  "policies": {
    "Homepage": {
      "URL": "about:home",
      "StartPage": "homepage"
    }
  }
}
EOF
}

###################################
### gnome-extensions-cli (gext) ###
###################################

setup_gext() {

    # Install pip3
    if ! command -v pip3 >/dev/null 2>&1; then
        log "Installing pip3 system-wide..."
        sudo dnf install -y python3-pip
    fi

    # Install gnome-extensions-cli
    if ! command -v gext >/dev/null 2>&1; then
        log "Installing gnome-extensions-cli system-wide..."
        pip3 install --user gnome-extensions-cli
    fi
}

#####################
### Hangual Input ###
#####################

configure_hangul_input() {

    # Install prerequisites
    setup_gext

    # Configure Hangul input
    log "Configuring Hangul input..."

    dconf write /org/gnome/desktop/input-sources/sources "[('xkb', 'us'), ('ibus', 'hangul')]"
    dconf write /org/gnome/desktop/input-sources/xkb-options "['korean:ralt_hangul']"
    dconf write /org/gnome/desktop/input-sources/per-window true

    dconf write /org/gnome/desktop/wm/keybindings/switch-input-source "['Hangul']"
    dconf write /org/gnome/desktop/wm/keybindings/activate-window-menu "@as []"

    dconf write /org/freedesktop/ibus/general/hotkey/trigger "@as []"
    dconf write /org/freedesktop/ibus/general/hotkey/triggers "@as []"

    dconf write /org/freedesktop/ibus/engine/hangul/disable-latin-mode true
    dconf write /org/freedesktop/ibus/engine/hangul/initial-input-mode "'hangul'"
    dconf write /org/freedesktop/ibus/engine/hangul/switch-keys "''"

    # Disable input language selection popup
    log "Disabling input selection popup..."
    gext --filesystem install 4559
}


########################
### GNOME Extensions ###
########################

configure_gnome_ext() {

    log "Installing and configuring GNOME extensions..."

    # Install and configure GTK3 theme for UI theme uniformity
    sudo dnf install -y adw-gtk3-theme
    gext --filesystem install 4998
    dconf write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3'"

    # Clipboard (copyous)
    sudo dnf install -y libgda libgda-sqlite
    gext --filesystem install 8834
    mkdir -p "$HOME/.local/share/copyous@boerdereinar.dev/"
    curl https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/es/highlight.min.js -o "$HOME/.local/share/copyous@boerdereinar.dev/highlight.min.js"
    dconf load /org/gnome/shell/extensions/copyous/ < "$REPO_DIR/gnome/copyous.ini"

    # Dash to Panel
    gext --filesystem install 1160
    dconf load /org/gnome/shell/extensions/dash-to-panel/ < "$REPO_DIR/gnome/dash-to-panel.ini"

    # Panel Date Format
    gext --filesystem install 1462
    dconf load /org/gnome/shell/extensions/panel-date-format/ < "$REPO_DIR/gnome/panel-date-format.ini"

    # Media Controls
    gext --filesystem install 10373
    dconf load /org/gnome/shell/extensions/media-controller/ < "$REPO_DIR/gnome/media-controller.ini"

    # Multi Monitor Bar
    gext --filesystem install 8773

    # Alt Tab
    gext --filesystem install 4412
    dconf load /org/gnome/shell/extensions/advanced-alt-tab-window-switcher/ < "$REPO_DIR/gnome/advanced-alt-tab-window-switcher.ini"

    # tiling-assistant
    gext --filesystem install 3733
    dconf load /org/gnome/shell/extensions/tiling-assistant/ < "$REPO_DIR/gnome/tiling-assistant.ini"

    # Rounded Window Corners Reborn
    gext --filesystem install 7048

    # Steal my focus window
    gext --filesystem install 6385
}


######################
### GNOME Settings ###
######################

configure_gnome() {

    log "Configuring GNOME..."

    dconf write /org/gnome/desktop/interface/color-scheme "'default'"
    dconf write /org/gnome/desktop/interface/enable-hot-corners false
    dconf write /org/gnome/desktop/interface/font-antialiasing "'grayscale'"
    dconf write /org/gnome/desktop/interface/toolkit-accessibility false

    # Workspaces on primary display only (true) / all displays (false)
    dconf write /org/gnome/mutter/workspaces-only-on-primary true

    # App switcher: current workspace only (true) / all workspaces (false)
    dconf write /org/gnome/shell/app-switcher/current-workspace-only true

    # Window Buttons
    dconf write /org/gnome/desktop/wm/preferences/button-layout "'appmenu:minimize,maximize,close'"

    # Touchpad Config
    dconf write /org/gnome/desktop/peripherals/touchpad/click-method "'fingers'"
    dconf write /org/gnome/desktop/peripherals/touchpad/two-finger-scrolling-enabled true

    # Font
    dconf write /org/gnome/desktop/interface/font-name "'Pretendard 11'"
    dconf write /org/gnome/desktop/interface/document-font-name "'Pretendard 11'"
    dconf write /org/gnome/desktop/interface/monospace-font-name "'CodexMono EA Nerd 11'"

    # Disable 'Support GNOME' popup
    dconf write /org/gnome/settings-daemon/plugins/housekeeping/donation-reminder-enabled false

    # Set pinned apps
    dconf load /org/gnome/shell/favorite-apps/ < "$REPO_DIR/gnome/pinned-apps.ini"

    # Launch New Instance
    gnome-extensions enable launch-new-instance@gnome-shell-extensions.gcampax.github.com
}

##########################
### Keyboard Shortcuts ###
##########################

configure_key() {

    log "Configuring keyboard shortcuts..."

    # Alt+Tab
    dconf write /org/gnome/desktop/wm/keybindings/switch-applications "@as []"
    dconf write /org/gnome/desktop/wm/keybindings/switch-applications-backward "@as []"

    dconf write /org/gnome/desktop/wm/keybindings/switch-windows "['<Alt>Tab']"
    dconf write /org/gnome/desktop/wm/keybindings/switch-windows-backward "['<Shift><Alt>Tab']"

    # Switch workspaces (Ctrl+Super+←/→)
    dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-left "['<Control><Super>Left']"
    dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-right "['<Control><Super>Right']"

    # Move apps between workspaces (Ctrl+Shift+Super+←/→)
    dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-left "['<Control><Shift><Super>Left']"
    dconf write /org/gnome/desktop/wm/keybindings/move-to-workspace-right "['<Control><Shift><Super>Right']"

    # Alt+F4 / Super+C → Close app
    dconf write /org/gnome/desktop/wm/keybindings/close "['<Alt>F4', '<Super>c']"

    # Super+D → Show desktop
    dconf write /org/gnome/desktop/wm/keybindings/show-desktop "['<Super>d']"

    # Empty keybinding for message tray
    dconf write /org/gnome/shell/keybindings/toggle-message-tray "@as []"

    # Create custom key bindings
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings \
        "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-file/', \
        '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal/', \
        '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-taskmgr/']"

    # Super+E → File Manager
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-file/name "'Files'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-file/command "'nautilus'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-file/binding "'<Super>e'"

    # Super+Q → Terminal
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal/name "'Terminal'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal/command "'ghostty'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal/binding "'<Super>q'"

    # Ctrl+Shift+Esc → System Monitor
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-taskmgr/name "'Task Manager'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-taskmgr/command "'gnome-system-monitor'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-taskmgr/binding "'<Control><Shift>Escape'"
}

#############
### Fonts ###
#############

install_fonts() {
    local src_dir="$HOME/src"
    mkdir -p "$src_dir" "$HOME/.local/share/fonts"

    log "yongj-custom-fonts"
    if [[ ! -d "$src_dir/yongj-custom-fonts" ]]; then
        log "  Cloning repository..."
        git clone https://github.com/kimiroo/yongj-custom-fonts "$src_dir/yongj-custom-fonts"
    else
        log "  Already cloned — skipping (run git pull manually to update)"
    fi

    log "  Installing CodexMono EA Nerd Font..."
    mkdir -p "$HOME/.local/share/fonts/yongj-custom-fonts"
    cp "$src_dir/yongj-custom-fonts/dst/codexmono/nerd/CodexMono-EA-Nerd.ttf" \
        "$HOME/.local/share/fonts/yongj-custom-fonts/"

    log "Pretendard v1.3.9 (official GitHub release)"
    if [[ ! -f "$HOME/.local/share/fonts/pretendard/PretendardVariable.ttf" ]]; then
        local tmp
        tmp=$(mktemp -d)
        log "  Downloading..."
        curl -fsSL -o "$tmp/pretendard.zip" \
            https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip
        log "  Extracting..."
        unzip -q "$tmp/pretendard.zip" -d "$tmp/extracted"
        mkdir -p "$HOME/.local/share/fonts/pretendard"
        log "  Installing .ttf files..."
        find "$tmp/extracted" -type f -name '*.ttf' \
            -exec cp {} "$HOME/.local/share/fonts/pretendard/" \;
        rm -rf "$tmp"
    else
        log "  Already installed — skipping"
    fi

    log "Refreshing font cache (fc-cache)..."
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null
}

############
### Grub ###
############

configure_grub() {

    confirm "Configure GRUB?" || {
        warn "User skipped GRUB stage."
        return 0
    }

    log "Applying backlight kernel parameter..."
    sudo grubby --update-kernel=ALL --args=i915.enable_dpcd_backlight=3

    log "Applying grub parameters for silent boot..."
    sudo sed -i \
        -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
        -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' \
        /etc/default/grub
    grep -q '^GRUB_TIMEOUT=' /etc/default/grub || echo 'GRUB_TIMEOUT=0' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub || echo 'GRUB_TIMEOUT_STYLE=hidden' | sudo tee -a /etc/default/grub >/dev/null

    log "Configuring GRUB..."
    if [[ -d /sys/firmware/efi ]]; then
        sudo grub2-mkconfig -o /etc/grub2-efi.cfg
    else
        sudo grub2-mkconfig -o /etc/grub2.cfg
    fi
}

install_wallpaperengine() {
    local src_dir="$HOME/src/linux-wallpaperengine"

    log "Installing linux-wallpaperengine build dependencies..."
    sudo dnf install -y \
        gcc gcc-c++ cmake libXrandr-devel libXinerama-devel libXcursor-devel \
        libXi-devel mesa-libGL-devel glew-devel freeglut-devel sdl2-compat-devel lz4-devel \
        ffmpeg-free-devel libXxf86vm-devel glm-devel glfw-devel mpv mpv-devel \
        pulseaudio-libs-devel fftw-devel gmp-devel dbus-devel

    if [[ ! -d "$src_dir" ]]; then
        log "Cloning linux-wallpaperengine clone..."
        git clone --recurse-submodules https://github.com/Almamu/linux-wallpaperengine "$src_dir"
    else
        log "Already cloned. Skipping..."
    fi

    if [[ -x "$src_dir/build/output/linux-wallpaperengine" ]]; then
        log "Already built. Skipping..."
        return 0
    fi

    log "Building linux-wallpaperengine... This will take some time."
    mkdir -p "$src_dir/build"
    (cd "$src_dir/build" && cmake -DCMAKE_BUILD_TYPE='Release' .. && make -j"$(nproc)")

    warn "실행하려면 Steam에서 Wallpaper Engine(appid 431960)과 원하는 워크샵 아이템을 직접 소유/다운로드해야 함 (이 스크립트가 대신 할 수 없음)."
    warn "예: $src_dir/build/output/linux-wallpaperengine --scaling fill --screen-root <출력이름> --bg <workshop_id>"
}

############
### Base ###
############

main() {
    local steps=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) ASSUME_YES=1 ;;
            -h|--help) show_help; exit 0 ;;
            repo|zsh|ghostty|packages|vscode|firefox|chrony|chrome|nextdns|ssh|hangul|gnome-ext|gnome|keybindings|font|grub|wallpaper-engine|all|headless)
                steps+=("$1") ;;
            *) die "Unknown argument: $1 (see --help)" ;;
        esac
        shift
    done

    [[ "$(id -u)" -eq 0 ]] && die "Do not run as root — run as a regular user, sudo will be requested when needed"

    if [[ ${#steps[@]} -eq 0 ]]; then
        steps=(repo zsh ghostty packages vscode firefox chrony nextdns ssh hangul gnome-ext gnome keybindings font)
        log "No arguments given — running default stages: ${steps[*]} (grub/wallpaper-engine are opt-in, see --help)"
    fi

    # "all" expands to every stage in place, without pulling in duplicates
    # if other stage names were listed alongside it.
    local expanded=() s
    for s in "${steps[@]}"; do
        if [[ "$s" == "all" ]]; then
            expanded+=(repo zsh ghostty packages vscode firefox chrony nextdns chrome ssh hangul gnome-ext gnome keybindings font grub wallpaper-engine)
        elif [[ "$s" == "headless" ]]; then
            expanded+=(repo zsh chrony ssh)
        else
            expanded+=("$s")
        fi
    done
    steps=()
    local seen=","
    for s in "${expanded[@]}"; do
        [[ "$seen" == *",$s,"* ]] && continue
        steps+=("$s")
        seen+="$s,"
    done

    for step in "${steps[@]}"; do
        case "$step" in
            repo) configure_repo_n_update ;;
            zsh) setup_zsh ;;
            ghostty) setup_ghostty ;;
            packages) setup_packages ;;
            vscode) setup_vscode ;;
            firefox) configure_ff_startpage ;;
            chrony) configure_chrony ;;
            chrome) setup_chrome ;;
            nextdns) setup_nextdns ;;
            ssh) configure_ssh_server ;;
            hangul) configure_hangul_input ;;
            gnome-ext) configure_gnome_ext ;;
            gnome) configure_gnome ;;
            keybindings) configure_key ;;
            font) install_fonts ;;
            grub) configure_grub ;;
            wallpaper-engine) install_wallpaperengine ;;
        esac
    done

    log "Done. Re-login/reboot may be required for some changes to take effect (e.g., zsh, gnome extensions, grub)."
}

main "$@"
