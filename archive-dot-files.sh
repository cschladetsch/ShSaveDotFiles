#!/bin/bash

# backup-dotfiles.sh - Backup important dotfiles for migration
# Usage: ./backup-dotfiles.sh [output-name]

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Output filename
OUTPUT_NAME="${1:-dotfiles-backup-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_FILE="${OUTPUT_NAME}.tar.gz"
TEMP_DIR="/tmp/${OUTPUT_NAME}"

# Create temporary directory
mkdir -p "$TEMP_DIR"

echo -e "${GREEN}Starting dotfiles backup...${NC}"

# Define dotfiles and directories to backup
DOTFILES=(
    # Shell configurations
    ".bashrc"
    ".bash_profile"
    ".bash_aliases"
    ".zshrc"
    ".zprofile"
    ".zsh_aliases"
    ".oh-my-zsh"
    ".p10k.zsh"
    
    # Shell history (optional - comment out if you don't want history)
    ".bash_history"
    ".zsh_history"
    
    # Git configuration
    ".gitconfig"
    ".gitignore_global"
    ".gitmessage"
    
    # SSH configuration (INCLUDING private keys - be careful!)
    ".ssh"  # Entire .ssh directory with all keys
    
    # Terminal multiplexers
    ".tmux.conf"
    ".tmux"
    ".screenrc"
    
    # Editors
    ".vimrc"
    ".vim"
    ".nanorc"
    ".emacs"
    ".emacs.d"
    
    # Development tools
    ".npmrc"
    ".yarnrc"
    ".cargo/config"
    ".rustup/settings.toml"
    ".pypirc"
    ".pip/pip.conf"
    ".gem/credentials"
    ".bundle/config"
    
    # Other CLI tools
    ".curlrc"
    ".wgetrc"
    ".dircolors"
    ".inputrc"
    ".hushlogin"
    ".selected_editor"
    
    # Application configs
    ".config"  # Entire .config directory with all application configurations
    
    # WSL specific
    ".wslconfig"
    ".wslgconfig"
)

# Function to check if file/directory exists and copy it
backup_item() {
    local item="$1"
    local source="$HOME/$item"
    
    # Handle wildcards
    if [[ "$item" == *"*"* ]]; then
        local dir=$(dirname "$item")
        local pattern=$(basename "$item")
        local source_dir="$HOME/$dir"
        
        if [[ -d "$source_dir" ]]; then
            mkdir -p "$TEMP_DIR/$dir"
            find "$source_dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | while read -r file; do
                if [[ -f "$file" ]]; then
                    cp "$file" "$TEMP_DIR/$dir/" 2>/dev/null || true
                    echo -e "${GREEN}  ✓${NC} $(basename "$file")"
                fi
            done
        fi
    elif [[ -e "$source" ]]; then
        # Create parent directory in temp location
        local parent_dir=$(dirname "$item")
        if [[ "$parent_dir" != "." ]]; then
            mkdir -p "$TEMP_DIR/$parent_dir"
        fi
        
        # Copy file or directory
        if [[ -d "$source" ]]; then
            cp -r "$source" "$TEMP_DIR/$item" 2>/dev/null || {
                echo -e "${YELLOW}  ⚠${NC}  Partial copy of $item (some files skipped)"
                return
            }
        else
            cp "$source" "$TEMP_DIR/$item" 2>/dev/null || {
                echo -e "${RED}  ✗${NC} Failed to copy $item"
                return
            }
        fi
        echo -e "${GREEN}  ✓${NC} $item"
    fi
}

# Backup each item
echo -e "\n${YELLOW}Backing up dotfiles:${NC}"
for item in "${DOTFILES[@]}"; do
    backup_item "$item"
done

# Create a restore script
cat > "$TEMP_DIR/restore-dotfiles.sh" << 'EOF'
#!/bin/bash
# Restore script for dotfiles

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Restoring dotfiles to $HOME${NC}"
echo -e "${RED}WARNING: This will overwrite existing files!${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Find the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Copy all files back to home directory
cd "$SCRIPT_DIR"
for item in $(find . -type f -not -name "restore-dotfiles.sh" -not -name "README.md" | sed 's|^./||'); do
    # Create parent directory if needed
    parent_dir=$(dirname "$item")
    if [[ "$parent_dir" != "." ]]; then
        mkdir -p "$HOME/$parent_dir"
    fi
    
    # Copy file
    cp "$item" "$HOME/$item"
    echo -e "${GREEN}  ✓${NC} Restored $item"
done

# Copy directories
for dir in $(find . -type d -not -path "." | sed 's|^./||'); do
    if [[ ! -d "$HOME/$dir" ]]; then
        mkdir -p "$HOME/$dir"
    fi
done

echo -e "\n${GREEN}Dotfiles restored successfully!${NC}"
echo -e "${YELLOW}You may need to:${NC}"
echo "  - Reload your shell: source ~/.zshrc or source ~/.bashrc"
echo "  - Restart your terminal"
echo "  - Install Oh My Zsh if using zsh configuration"
echo "  - Install any required tools (tmux, vim plugins, etc.)"
EOF

chmod +x "$TEMP_DIR/restore-dotfiles.sh"

# Create README
cat > "$TEMP_DIR/README.md" << EOF
# Dotfiles Backup

Created on: $(date)
From host: $(hostname)
User: $(whoami)

## Contents

This archive contains configuration files (dotfiles) from your home directory.

## ⚠️ SECURITY WARNING

**This backup includes SSH PRIVATE KEYS!**
- Keep this archive secure
- Do not share it publicly
- Delete it after restoring on the new machine
- Consider encrypting it during transfer

## How to restore

1. Extract this archive:
   \`\`\`bash
   tar -xzf ${OUTPUT_FILE}
   cd ${OUTPUT_NAME}
   \`\`\`

2. Run the restore script:
   \`\`\`bash
   ./restore-dotfiles.sh
   \`\`\`

3. Reload your shell configuration:
   \`\`\`bash
   source ~/.zshrc  # or ~/.bashrc
   \`\`\`

## Notes

- **SSH private keys ARE included** - handle with care!
- Set proper permissions after restore: \`chmod 600 ~/.ssh/id_*\`
- Some application passwords/tokens may need to be re-entered
- You may need to install applications separately (tmux, vim, etc.)

## Manual steps after restore

1. Fix SSH key permissions: 
   \`\`\`bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/id_*
   chmod 644 ~/.ssh/*.pub
   chmod 644 ~/.ssh/config
   \`\`\`
2. Install Oh My Zsh: \`sh -c "\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"\`
3. Install Powerlevel10k: \`git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/themes/powerlevel10k\`
4. Install tmux plugins: Press \`prefix + I\` in tmux
5. Install vim plugins (if using vim-plug): \`:PlugInstall\` in vim
EOF

# Create the archive
echo -e "\n${YELLOW}Creating archive...${NC}"
cd /tmp
tar -czf "$HOME/$OUTPUT_FILE" "$OUTPUT_NAME"
rm -rf "$TEMP_DIR"

# Calculate size
SIZE=$(ls -lh "$HOME/$OUTPUT_FILE" | awk '{print $5}')

echo -e "\n${GREEN}✓ Backup complete!${NC}"
echo -e "  File: ${GREEN}$HOME/$OUTPUT_FILE${NC}"
echo -e "  Size: ${GREEN}$SIZE${NC}"
echo -e "\n${YELLOW}To restore on another machine:${NC}"
echo -e "  1. Copy $OUTPUT_FILE to the new machine"
echo -e "  2. tar -xzf $OUTPUT_FILE"
echo -e "  3. cd $OUTPUT_NAME"
echo -e "  4. ./restore-dotfiles.sh"

# Optional: List items that were skipped
echo -e "\n${YELLOW}Note:${NC} Some files may not exist on your system and were skipped."
echo -e "This is normal if you don't use certain applications."
