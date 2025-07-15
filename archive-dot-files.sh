#!/bin/bash

# backup-dotfiles.sh - Backup important dotfiles for migration
# Usage: ./backup-dotfiles.sh [output-name] [--push] [--compression=TYPE] [--repo=GITHUB_REPO]
#        --push: Push the backup to GitHub repository
#        --repo=USER/REPO: GitHub repository for push (default: from git config or env)
#        --compression=TYPE: Set compression type (gzip, bzip2, xz) - default: gzip
#                           Use with --level=N for compression level (1-9, default: 6)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
# Default GitHub repository - can be overridden by:
# 1. --repo command line argument
# 2. SAVEDOTFILES_REPO environment variable
# 3. git config savedotfiles.repo
DEFAULT_GITHUB_REPO="${SAVEDOTFILES_REPO:-}"
if [[ -z "$DEFAULT_GITHUB_REPO" ]]; then
    DEFAULT_GITHUB_REPO=$(git config savedotfiles.repo 2>/dev/null || echo "")
fi
if [[ -z "$DEFAULT_GITHUB_REPO" ]]; then
    DEFAULT_GITHUB_REPO="cschladetsch/PrivateDotFiles"
fi

# Parse arguments
PUSH_TO_REPO=false
OUTPUT_NAME=""
COMPRESSION_TYPE="gzip"
COMPRESSION_LEVEL="6"
GITHUB_REPO="$DEFAULT_GITHUB_REPO"

for arg in "$@"; do
    if [[ "$arg" == "--push" ]]; then
        PUSH_TO_REPO=true
    elif [[ "$arg" =~ ^--repo=(.+)$ ]]; then
        GITHUB_REPO="${BASH_REMATCH[1]}"
    elif [[ "$arg" =~ ^--compression=(.+)$ ]]; then
        COMPRESSION_TYPE="${BASH_REMATCH[1]}"
    elif [[ "$arg" =~ ^--level=([1-9])$ ]]; then
        COMPRESSION_LEVEL="${BASH_REMATCH[1]}"
    elif [[ ! "$arg" =~ ^-- ]]; then
        OUTPUT_NAME="$arg"
    fi
done

# Set default output name if not provided
if [[ -z "$OUTPUT_NAME" ]]; then
    OUTPUT_NAME="dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
fi

# Validate compression type and set file extension
case "$COMPRESSION_TYPE" in
    gzip|gz)
        COMPRESSION_TYPE="gzip"
        FILE_EXT="tar.gz"
        TAR_FLAGS="-czf"
        EXTRACT_FLAGS="-xzf"
        ;;
    bzip2|bz2)
        COMPRESSION_TYPE="bzip2"
        FILE_EXT="tar.bz2"
        TAR_FLAGS="-cjf"
        EXTRACT_FLAGS="-xjf"
        ;;
    xz)
        COMPRESSION_TYPE="xz"
        FILE_EXT="tar.xz"
        TAR_FLAGS="-cJf"
        EXTRACT_FLAGS="-xJf"
        ;;
    *)
        echo -e "${RED}Error: Unknown compression type: $COMPRESSION_TYPE${NC}"
        echo "Supported types: gzip, bzip2, xz"
        exit 1
        ;;
esac

OUTPUT_FILE="${OUTPUT_NAME}.${FILE_EXT}"
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
    
    # User documents
    "doc"
    
    # User scripts
    "bin"
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
   tar ${EXTRACT_FLAGS} ${OUTPUT_FILE}
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
echo -e "  Compression: ${GREEN}${COMPRESSION_TYPE}${NC} (level ${COMPRESSION_LEVEL})"

cd /tmp

# Set compression environment variable based on type
case "$COMPRESSION_TYPE" in
    gzip)
        # Use environment variable despite deprecation warning
        # (--options flag not universally available)
        export GZIP="-${COMPRESSION_LEVEL}"
        ;;
    bzip2)
        export BZIP2="-${COMPRESSION_LEVEL}"
        ;;
    xz)
        export XZ_OPT="-${COMPRESSION_LEVEL}"
        ;;
esac

tar $TAR_FLAGS "$HOME/$OUTPUT_FILE" "$OUTPUT_NAME"
rm -rf "$TEMP_DIR"

# Calculate size
SIZE=$(ls -lh "$HOME/$OUTPUT_FILE" | awk '{print $5}')

echo -e "\n${GREEN}✓ Backup complete!${NC}"
echo -e "  File: ${GREEN}$HOME/$OUTPUT_FILE${NC}"
echo -e "  Size: ${GREEN}$SIZE${NC}"
echo -e "\n${YELLOW}To restore on another machine:${NC}"
echo -e "  1. Copy $OUTPUT_FILE to the new machine"
echo -e "  2. tar $EXTRACT_FLAGS $OUTPUT_FILE"
echo -e "  3. cd $OUTPUT_NAME"
echo -e "  4. ./restore-dotfiles.sh"

# Optional: List items that were skipped
echo -e "\n${YELLOW}Note:${NC} Some files may not exist on your system and were skipped."
echo -e "This is normal if you don't use certain applications."

# Push to git repository if requested
if [[ "$PUSH_TO_REPO" == true ]]; then
    echo -e "\n${YELLOW}Pushing to GitHub repository: ${GITHUB_REPO}...${NC}"
    
    # Create a temporary directory for the git operation
    REPO_DIR="/tmp/PrivateDotFiles-$(date +%s)"
    
    # Clone the repository
    if git clone "git@github.com:${GITHUB_REPO}.git" "$REPO_DIR" 2>/dev/null; then
        # Copy the archive to the repo
        cp "$HOME/$OUTPUT_FILE" "$REPO_DIR/"
        
        # Change to repo directory
        cd "$REPO_DIR"
        
        # Keep only the last 5 backup files
        echo -e "${YELLOW}Cleaning up old backups (keeping last 5)...${NC}"
        
        # Get all tar.* files sorted by modification time (oldest first)
        BACKUP_FILES=($(ls -t *.tar.{gz,bz2,xz} 2>/dev/null | tail -r 2>/dev/null || ls -tr *.tar.{gz,bz2,xz} 2>/dev/null))
        TOTAL_FILES=${#BACKUP_FILES[@]}
        
        if [[ $TOTAL_FILES -gt 5 ]]; then
            # Calculate how many files to delete
            DELETE_COUNT=$((TOTAL_FILES - 5))
            echo -e "  Found $TOTAL_FILES backups, removing $DELETE_COUNT old files"
            
            # Delete the oldest files
            for ((i=0; i<$DELETE_COUNT; i++)); do
                FILE_TO_DELETE="${BACKUP_FILES[$i]}"
                git rm "$FILE_TO_DELETE" 2>/dev/null
                echo -e "${RED}  ✗ Removed old backup:${NC} $FILE_TO_DELETE"
            done
        else
            echo -e "  Found $TOTAL_FILES backups, no cleanup needed"
        fi
        
        # Add the new file
        git add "$OUTPUT_FILE"
        
        # Commit with appropriate message
        if [[ $TOTAL_FILES -gt 5 ]]; then
            git commit -m "Add dotfiles backup: $OUTPUT_FILE (cleaned up old backups)" 2>/dev/null
        else
            git commit -m "Add dotfiles backup: $OUTPUT_FILE" 2>/dev/null
        fi
        
        if git push origin main 2>/dev/null; then
            echo -e "${GREEN}✓ Successfully pushed to GitHub!${NC}"
            echo -e "  Repository: https://github.com/${GITHUB_REPO}"
            echo -e "  File: $OUTPUT_FILE"
            if [[ $TOTAL_FILES -gt 5 ]]; then
                echo -e "  Removed: $DELETE_COUNT old backup(s)"
            fi
        else
            echo -e "${RED}✗ Failed to push to GitHub${NC}"
            echo -e "  The backup file is still available at: $HOME/$OUTPUT_FILE"
        fi
        
        # Clean up
        rm -rf "$REPO_DIR"
    else
        echo -e "${RED}✗ Failed to clone repository${NC}"
        echo -e "  Please ensure you have access to: git@github.com:${GITHUB_REPO}.git"
        echo -e "  The backup file is still available at: $HOME/$OUTPUT_FILE"
    fi
fi
