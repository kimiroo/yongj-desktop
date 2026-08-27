# yongj-desktop GNOME Setup Scripts

## Quick Start (remote)

```bash
curl -fsSL https://raw.githubusercontent.com/kimiroo/yongj-desktop/main/bootstrap.sh | bash
```

With arguments:

```bash
curl -fsSL https://raw.githubusercontent.com/kimiroo/yongj-desktop/main/bootstrap.sh | bash -s -- all --yes
```

## Usage

```
Usage: ./configure.sh [stages...] [option]

Stages (default stages run if omitted; grub and wallpaper-engine are opt-in):
  repo             Configure repo mirror + system update
  zsh              Install and configure zsh, oh-my-zsh, starship, rustup/hyperfine
  kitty            Install and configure kitty, register as default terminal
  ghostty          Install and configure ghostty, register as default terminal
  packages         Install misc packages (btop, neovim)
  vscode           Install VS Code
  firefox          Set Firefox default start page
  hangul           Configure Korean (Hangul) input
  gnome-ext        Install and configure GNOME Shell extensions
  gnome            Configure GNOME settings (theme, touchpad, workspaces, etc.)
  keybindings      Configure keyboard shortcuts
  font             Install fonts
  grub             Configure GRUB (opt-in, asks for confirmation)
  wallpaper-engine Build and install linux-wallpaperengine (opt-in)
  all              Run every stage above, including grub and wallpaper-engine

Options:
  -y, --yes        Assume yes to all confirmation prompts
  -h, --help       Show this help message

Examples: ./configure.sh
          ./configure.sh gnome-ext gnome keybindings
          ./configure.sh all --yes
```