#!/bin/bash
set -euo pipefail

DEVVM="devvm32391.prn0.facebook.com"
CTRL="/tmp/ssh-devvm-deploy"
STAGE="/tmp/devvm-deploy-bundle"
DROPBOX="$HOME/Dropbox/Dotfiles"

echo "==> Deploying everything to $DEVVM"
echo "    (single SSH connection — one Yubikey tap)"
echo ""

# --- Establish SSH ControlMaster (one Yubikey tap) ---
echo "==> Establishing SSH connection..."
ssh -o ControlMaster=yes -o ControlPath="$CTRL" -o ControlPersist=300 -fN "$DEVVM"
trap 'ssh -o ControlPath="$CTRL" -O exit "$DEVVM" 2>/dev/null; rm -rf "$STAGE"' EXIT
SSH="ssh -o ControlPath=$CTRL"
SCP="scp -o ControlPath=$CTRL"

# --- Stage all files into a tarball ---
echo "==> Staging files..."
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,config,dotfiles,vim}

# Scripts
cp ~/.local/bin/fp                          "$STAGE/bin/fp"
cp "$DROPBOX/bat-preview"                   "$STAGE/bin/bat-preview"
cp "$DROPBOX/nosudo"                        "$STAGE/bin/nosudo"
cp "$DROPBOX/rm"                            "$STAGE/bin/rm"

# Dotfiles
cp "$DROPBOX/vimrc"                         "$STAGE/dotfiles/vimrc"
cp "$DROPBOX/zshrc"                         "$STAGE/dotfiles/zshrc"
cp "$DROPBOX/gitconfig"                     "$STAGE/dotfiles/gitconfig"
cp "$DROPBOX/sharedrc"                      "$STAGE/dotfiles/sharedrc"
cp "$DROPBOX/terminfo-tmux-256color"        "$STAGE/dotfiles/terminfo-tmux-256color"

# Config
cp /tmp/starship-devvm.toml                 "$STAGE/config/starship.toml"

# Vim plugins
rsync -a "$DROPBOX/dotvim/bundle/"          "$STAGE/vim/bundle/"

# Deploy script (tmux + powerline + helpers)
cp "$DROPBOX/deploy-tmux-devserver.sh"      "$STAGE/deploy-tmux-devserver.sh"

# Setup script to run on devserver
cat > "$STAGE/setup.sh" << 'SETUP'
#!/bin/bash
set -euo pipefail
cd /tmp/devvm-deploy-bundle

echo "==> Installing dotfiles..."
mkdir -p ~/.local/bin ~/.config ~/.vim/bundle

# Dotfiles
cp dotfiles/vimrc               ~/.vimrc
cp dotfiles/zshrc                ~/.zshrc
cp dotfiles/gitconfig            ~/.gitconfig
cp dotfiles/sharedrc             ~/.sharedrc

# Starship config
mkdir -p ~/.config
cp config/starship.toml          ~/.config/starship.toml

# Terminfo
if command -v tic &>/dev/null; then
    tic -x dotfiles/terminfo-tmux-256color 2>/dev/null && echo "    terminfo compiled" || true
fi

# Scripts
cp bin/* ~/.local/bin/
chmod +x ~/.local/bin/fp ~/.local/bin/bat-preview ~/.local/bin/nosudo ~/.local/bin/rm

# Vim plugins
echo "==> Syncing vim plugins..."
rsync -a --delete vim/bundle/ ~/.vim/bundle/

# Run tmux deploy (tmux.conf, helpers, powerline, TPM)
echo "==> Running tmux deploy..."
chmod +x deploy-tmux-devserver.sh
./deploy-tmux-devserver.sh

# Fix tmux.conf: update tmux-resurrect-patch → tmux-patch reference
if grep -q 'tmux-resurrect-patch' ~/.tmux.conf; then
    sed -i 's|tmux-resurrect-patch/resurrect-patch.tmux|tmux-patch/tmux-patch.tmux|g' ~/.tmux.conf
    echo "    Fixed tmux-patch reference in tmux.conf"
fi

# Install/update tmux-patch from GitHub
echo "==> Installing tmux-patch..."
mkdir -p ~/.tmux/plugins
if [ -d ~/.tmux/plugins/tmux-patch/.git ]; then
    cd ~/.tmux/plugins/tmux-patch && git pull origin master 2>&1
else
    rm -rf ~/.tmux/plugins/tmux-patch
    git clone https://github.com/megadogsu/tmux-patch.git ~/.tmux/plugins/tmux-patch 2>&1
fi

# Install/update fzf
echo "==> Installing fzf..."
if [ -d ~/.fzf ]; then
    cd ~/.fzf && git pull 2>&1 && ./install --bin 2>&1
else
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf 2>&1
    ~/.fzf/install --key-bindings --completion --no-update-rc 2>&1
fi

# Install tmux plugins via TPM
echo "==> Installing tmux plugins..."
~/.tmux/plugins/tpm/bin/install_plugins 2>/dev/null || true

# Reload tmux if running
if tmux info &>/dev/null 2>&1; then
    echo "==> Reloading tmux..."
    tmux source-file ~/.tmux.conf 2>/dev/null || true
fi

# Cleanup
rm -rf /tmp/devvm-deploy-bundle

echo ""
echo "==> All done! Deployed:"
echo "    - fp (content search + 500-line history)"
echo "    - zshrc, vimrc, gitconfig, sharedrc"
echo "    - starship.toml (perf-tuned + Linux features)"
echo "    - terminfo (tmux-256color)"
echo "    - vim plugins ($(ls ~/.vim/bundle | wc -l) plugins)"
echo "    - bat-preview, nosudo, rm"
echo "    - tmux.conf + powerline + helper scripts"
echo "    - tmux-patch (latest from GitHub)"
echo "    - fzf ($(~/.fzf/bin/fzf --version 2>/dev/null || echo 'unknown'))"
echo "    - TPM plugins"
SETUP
chmod +x "$STAGE/setup.sh"

# --- Create tarball ---
echo "==> Creating tarball..."
tar czf /tmp/devvm-deploy.tar.gz -C /tmp devvm-deploy-bundle

# --- Single SCP transfer ---
echo "==> Uploading to $DEVVM..."
$SCP /tmp/devvm-deploy.tar.gz "$DEVVM":/tmp/devvm-deploy.tar.gz

# --- Single SSH to unpack and run ---
echo "==> Running setup on $DEVVM..."
$SSH "$DEVVM" 'cd /tmp && tar xzf devvm-deploy.tar.gz && cd devvm-deploy-bundle && bash setup.sh'

echo ""
echo "==> Deploy complete!"
