# SaveDotFiles

A simple script to archive and backup dotfiles from your home directory.

## Description

`archive-dot-files.sh` creates a compressed archive of all dotfiles (files starting with `.`) in your home directory, making it easy to backup and restore your configuration files.

## Usage

```bash
./archive-dot-files.sh
```

This will create an archive containing all dotfiles from your home directory.

## Features

- Archives all dotfiles from the home directory
- Creates a compressed backup for easy storage and transfer
- Preserves file permissions and directory structure

## Requirements

- Bash shell
- Standard Unix utilities (tar, gzip, etc.)

## License

MIT