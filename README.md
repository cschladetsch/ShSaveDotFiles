# SaveDotFiles

A comprehensive backup solution for your dotfiles and configuration files, making system migrations and restorations simple and reliable.

## Description

`archive-dot-files.sh` creates a compressed archive of important dotfiles and configuration directories from your home directory. It intelligently selects common configuration files while preserving permissions, ownership, and directory structures.

## Features

- 📦 Archives essential dotfiles and configuration directories
- 🔒 Preserves file permissions and symbolic links
- 🎨 Color-coded output for better visibility
- 📊 Progress tracking with file counts
- 🗓️ Timestamped backups for version control
- ⚡ Automatic validation of backup integrity
- 🛡️ Safe extraction with backup of existing files
- 🔄 Push backups to GitHub with automatic cleanup (keeps last 5)

## What Gets Backed Up

The script backs up common configuration files including:

- **Shell Configurations**: `.bashrc`, `.zshrc`, `.bash_profile`, `.zprofile`, etc.
- **Shell History**: `.bash_history`, `.zsh_history` (optional)
- **Git Settings**: `.gitconfig`, `.gitignore_global`
- **SSH Keys**: Complete `.ssh` directory (⚠️ includes private keys)
- **Terminal Multiplexers**: `.tmux.conf`, `.screen*`
- **Editors**: `.vimrc`, `.vim/`, `.emacs.d/`
- **Development Tools**: `.npmrc`, `.cargo/`, `.rustup/`
- **Desktop Environments**: `.config/` directory for modern applications
- **User Documents**: `~/doc` directory with your documents
- **User Scripts**: `~/bin` directory with your personal scripts and tools
- **And many more...**

## Usage

### Creating a Backup

```bash
# Create backup with automatic timestamp
./archive-dot-files.sh

# Create backup with custom name
./archive-dot-files.sh my-backup-2024

# Create backup and push to GitHub repository
./archive-dot-files.sh --push

# Create backup with custom name and push to GitHub
./archive-dot-files.sh my-backup-2024 --push
```

This creates a `.tar.gz` file in the current directory. With the `--push` option, it will also push the backup to your private GitHub repository at https://github.com/cschladetsch/PrivateDotFiles.

**Note**: When using `--push`, the script automatically maintains only the 5 most recent backups in the repository, removing older ones to save space.

### Viewing Backup Contents

```bash
# List files in the archive
tar -tzf dotfiles-backup-20241112-143022.tar.gz

# List with details (permissions, sizes)
tar -tvzf dotfiles-backup-20241112-143022.tar.gz
```

## Restore Instructions

### Method 1: Full Restore (Recommended for New Systems)

```bash
# Extract to home directory
cd ~
tar -xzvf /path/to/dotfiles-backup-20241112-143022.tar.gz

# The archive preserves the full path structure
```

### Method 2: Selective Restore

```bash
# Extract specific files only
tar -xzvf dotfiles-backup-20241112-143022.tar.gz home/username/.bashrc home/username/.vimrc

# Extract to a temporary directory first
mkdir ~/dotfiles-restore
cd ~/dotfiles-restore
tar -xzvf /path/to/dotfiles-backup-20241112-143022.tar.gz

# Then manually copy what you need
cp -i home/username/.bashrc ~/.bashrc
```

### Method 3: Safe Restore with Backup

```bash
# Create a restore script that backs up existing files
cat > restore-dotfiles.sh << 'EOF'
#!/bin/bash
ARCHIVE="$1"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Backup existing dotfiles
mkdir -p "$BACKUP_DIR"
echo "Backing up existing dotfiles to $BACKUP_DIR"

# Extract archive contents to see what we're restoring
tar -tzf "$ARCHIVE" | while read -r file; do
    # Skip if it's just the home directory path
    [[ "$file" == "home/" || "$file" == "home/$(whoami)/" ]] && continue
    
    # Get the relative path from home
    rel_path="${file#home/$(whoami)/}"
    
    # If file exists, back it up
    if [[ -e "$HOME/$rel_path" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$rel_path")"
        cp -a "$HOME/$rel_path" "$BACKUP_DIR/$rel_path"
        echo "Backed up: $rel_path"
    fi
done

# Now restore
echo "Restoring dotfiles..."
cd ~
tar -xzvf "$ARCHIVE"
echo "Restore complete! Old files backed up to: $BACKUP_DIR"
EOF

chmod +x restore-dotfiles.sh
./restore-dotfiles.sh /path/to/dotfiles-backup.tar.gz
```

### Method 4: Preview and Interactive Restore

```bash
# Extract to temporary location for review
TEMP_RESTORE="/tmp/dotfiles-restore-$$"
mkdir -p "$TEMP_RESTORE"
cd "$TEMP_RESTORE"
tar -xzf /path/to/dotfiles-backup.tar.gz

# Review what was extracted
ls -la home/$(whoami)/

# Use rsync for intelligent merging with existing files
rsync -av --backup --backup-dir="$HOME/.dotfiles-old-$(date +%Y%m%d)" \
      home/$(whoami)/ $HOME/
```

## Important Security Notes

⚠️ **SSH Keys**: The backup includes your complete `.ssh` directory with private keys. When restoring:
```bash
# Fix SSH permissions after restore
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub
chmod 644 ~/.ssh/known_hosts
chmod 644 ~/.ssh/config
```

⚠️ **Sensitive Data**: Review the script's file list and remove any sensitive items you don't want backed up.

## Troubleshooting

### Permission Issues
If you encounter permission errors during restore:
```bash
# Extract without preserving ownership (useful when restoring to different user)
tar -xzvf dotfiles-backup.tar.gz --no-same-owner
```

### Path Mismatches
The archive stores full paths including username. If restoring to different username:
```bash
# Extract and rename paths
tar -xzvf backup.tar.gz --transform 's/home\/olduser/home\/newuser/g'
```

### Verify Backup Integrity
```bash
# Test archive without extracting
tar -tzf dotfiles-backup.tar.gz > /dev/null && echo "Archive is valid"

# Compare restored files with originals
diff -r ~/.bashrc /tmp/restore/home/$(whoami)/.bashrc
```

## Automated Weekly Backups

The `setup-cron.sh` script helps you configure automatic weekly backups using cron and anacron.

### Features

- **Anacron Support**: Automatically detects and uses anacron to ensure backups run even if your machine was off
- **Package Manager Detection**: Offers to install anacron if not present (supports apt, yum, dnf, pacman)
- **Flexible Scheduling**: Choose your preferred day and time for backups
- **GitHub Integration**: Option to automatically push backups to your PrivateDotFiles repository
- **Comprehensive Logging**: All backup operations logged to `~/.local/log/savedotfiles-backup.log`

### Setting Up Automated Backups

```bash
# Install weekly backup job (interactive setup)
./setup-cron.sh --install

# Check current backup job status
./setup-cron.sh --status

# Remove all backup jobs
./setup-cron.sh --remove
```

During installation, you'll be asked to:
1. Install anacron if not present (recommended)
2. Choose day of week (0=Sunday through 6=Saturday)
3. Choose hour (0-23 in 24-hour format)
4. Enable/disable automatic GitHub push

### How It Works

The script sets up:
1. **Anacron job** (if available): Ensures backups run even if the machine was off
2. **Regular cron job**: Runs at your specified time as a fallback
3. **Logging**: All operations logged for monitoring

### Example Schedule

With anacron:
```
# Anacron entry (runs within 10 minutes of machine startup if backup was missed)
7 10 savedotfiles-backup cd /path/to/ShSaveDotFiles && ./archive-dot-files.sh weekly-auto-backup --push >> ~/.local/log/savedotfiles-backup.log 2>&1
```

Regular cron:
```
# Runs every week on Sunday at 2:00 AM
0 2 * * 0 cd /path/to/ShSaveDotFiles && ./archive-dot-files.sh weekly-auto-backup --push >> ~/.local/log/savedotfiles-backup.log 2>&1
```

### Monitoring Automated Backups

```bash
# Check backup logs
tail -f ~/.local/log/savedotfiles-backup.log

# Verify backup jobs are configured
./setup-cron.sh --status

# List recent backups
ls -la ~/dotfiles-backup-*.tar.gz | tail -5
```

## Best Practices

1. **Regular Backups**: Run monthly or before major system changes
2. **Version Control**: Keep multiple backup versions
3. **Secure Storage**: Encrypt archives containing SSH keys:
   ```bash
   # Encrypt the backup
   gpg -c dotfiles-backup.tar.gz
   
   # Decrypt when needed
   gpg -d dotfiles-backup.tar.gz.gpg > dotfiles-backup.tar.gz
   ```
4. **Test Restores**: Verify your backups work before you need them
5. **Documentation**: Keep notes about any manual configuration steps

## Requirements

- Bash 4.0+
- GNU tar
- Standard Unix utilities (find, grep, wc)
- Sufficient disk space for the archive

## License

MIT