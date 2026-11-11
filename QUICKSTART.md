# GlassFilee Quick Start Guide

Get up and running with GlassFilee in 5 minutes!

## Prerequisites

You need these tools installed:

```bash
# Check if you have Zig
zig version  # Should be 0.13.0+

# Check if you have Odin
odin version  # Should be recent dev build

# If not installed, see docs/BUILDING.md
```

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/AmeFileManger.git
cd AmeFileManger
```

### 2. Build

```bash
# Simple way (recommended)
make build

# Or use Zig directly
mkdir -p zig-cache
odin build src/core -file -build-mode:obj -target:linux_amd64 -out:zig-cache/gfcore
zig build
```

### 3. Run

```bash
# Show help
./zig-out/bin/gf-cli help

# List files
./zig-out/bin/gf-cli ls .

# Get file info
./zig-out/bin/gf-cli stat README.md
```

## Basic Usage

### List Directory
```bash
gf-cli ls /home/user/Documents
gf-cli list ~/Downloads
```

### Copy File
```bash
gf-cli cp source.txt backup.txt
gf-cli copy photo.jpg /tmp/photo_backup.jpg
```

### Move/Rename File
```bash
gf-cli mv old_name.txt new_name.txt
gf-cli move file.txt ~/Documents/file.txt
```

### Delete File
```bash
gf-cli rm unwanted.txt
gf-cli delete /tmp/old_file.log
# Note: Will ask for confirmation
```

### Create Directory
```bash
gf-cli mkdir new_folder
gf-cli mkdir ~/Documents/Projects/GlassFilee
```

### Get File Information
```bash
gf-cli stat document.pdf
gf-cli stat ~/Downloads/video.mp4
```

## Examples

### Organize Downloads

```bash
# List all files
gf-cli ls ~/Downloads

# Create organized folders
gf-cli mkdir ~/Downloads/Images
gf-cli mkdir ~/Downloads/Documents
gf-cli mkdir ~/Downloads/Videos

# Move files (do this manually for now)
gf-cli mv ~/Downloads/photo.jpg ~/Downloads/Images/
gf-cli mv ~/Downloads/report.pdf ~/Downloads/Documents/
```

### Backup Important Files

```bash
# Create backup directory
gf-cli mkdir ~/Backups

# Copy files
gf-cli cp ~/Documents/important.txt ~/Backups/important.txt
gf-cli cp ~/Documents/project.zip ~/Backups/project.zip

# Verify
gf-cli ls ~/Backups
```

### Check Disk Usage

```bash
# List files with sizes
gf-cli ls /var/log

# Get individual file sizes
gf-cli stat /var/log/syslog
gf-cli stat /var/log/kern.log
```

## Troubleshooting

### "Command not found"

Add to PATH or use full path:
```bash
export PATH=$PATH:$(pwd)/zig-out/bin
# Or
alias gf-cli="$(pwd)/zig-out/bin/gf-cli"
```

### "Cannot open directory: Permission denied"

You need read permissions:
```bash
# Try with sudo (careful!)
sudo ./zig-out/bin/gf-cli ls /root

# Or change permissions
chmod +r directory
```

### "Build failed"

Make sure you built Odin core first:
```bash
make odin-core
```

Check that `zig-cache/gfcore.o` exists:
```bash
ls -l zig-cache/gfcore.o
```

## Next Steps

1. **Read the docs:**
   - [Architecture Overview](docs/ARCHITECTURE.md)
   - [API Documentation](docs/API.md)
   - [Building Guide](docs/BUILDING.md)

2. **Run tests:**
   ```bash
   zig build test
   ```

3. **Contribute:**
   - Check [TODO.md](TODO.md) for tasks
   - Read [CONTRIBUTING.md](CONTRIBUTING.md)
   - Pick an issue and start coding!

4. **Stay updated:**
   - Check [ROADMAP.md](docs/ROADMAP.md) for upcoming features
   - Watch the repository for updates

## Tips & Tricks

### Aliases

Add to your `.bashrc` or `.zshrc`:

```bash
alias gf='./zig-out/bin/gf-cli'
alias gfls='gf ls'
alias gfcp='gf cp'
alias gfmv='gf mv'
```

### Shell Integration

Create a function to cd and list:

```bash
gfcd() {
    cd "$1" && gf-cli ls
}
```

### Performance

For large directories, redirect output:

```bash
gf-cli ls /usr/bin > files.txt
wc -l files.txt
```

## FAQ

**Q: Is there a GUI?**  
A: Not yet! We're working on v0.2 with DVUI + SDL3.

**Q: Can I convert files?**  
A: Not yet! Conversion comes in v0.5 (Filee integration).

**Q: Does it work on macOS?**  
A: Should work, but untested. Try building and let us know!

**Q: How do I uninstall?**  
A: Just delete the directory:
```bash
cd .. && rm -rf AmeFileManger
```

## Getting Help

- Read the docs in `docs/`
- Check existing issues on GitHub
- Open a new issue with details
- Join discussions

---

Happy file managing! 🎉

For more details, see [README.md](README.md).
