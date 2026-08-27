#!/bin/bash
set -euo pipefail

if (( EUID != 0 )); then
    SUDO=sudo
else
    SUDO=
fi

${SUDO} pacman -S --noconfirm zsh git thunderbird firefox code virtualbox virtualbox-host-dkms timeshift proton-vpn-gtk-app plasma-meta plasma-login-manager base-devel cmake extra-cmake-modules kwin kconfig kconfigwidgets kcmutils kcoreaddons kwindowsystem qt6-base libdrm vulkan-headers oxygen kdeconnect noto-fonts
${SUDO} pacman -Rns --noconfirm falkon || true

# Install Oh My Zsh without an interactive prompt if not already installed
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"

git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" || true
git clone https://github.com/zsh-users/zsh-history-substring-search "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search" || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" || true

if [[ -f "$HOME/.zshrc" ]]; then
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-history-substring-search zsh-syntax-highlighting)/' "$HOME/.zshrc" || true
    grep -q "history-substring-search-up" "$HOME/.zshrc" || printf '\nbindkey "^[[A" history-substring-search-up\nbindkey "^[[B" history-substring-search-down\n' >> "$HOME/.zshrc"
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="bira"/' "$HOME/.zshrc" || true
fi
