# Omarchy Update Fix

## Problem
Running `omarchy-update` was breaking configs due to git merge conflicts, especially in files like `pip.conf` and `apps.conf`.

## Solution

### 1. Safe Update Wrapper
Use `omarchy-update-safe` instead of `omarchy-update`:

```bash
omarchy-update-safe
```

This script:
- Creates automatic backups before updating
- Handles git conflicts better
- Provides restore instructions if something goes wrong

### 2. Git Configuration
Git has been configured in the omarchy directory to handle merges better:
- `merge.ours.driver` - Prefers local changes during conflicts
- `pull.rebase false` - Uses merge instead of rebase (less likely to cause issues)

### 3. What Was Fixed
- Resolved git rebase conflict in `pip.conf` (merge conflict markers removed)
- Fixed syntax errors in `bindings.conf` (spacing issues)
- Fixed syntax error in `scratchpad.conf` (trailing comma)
- Cleaned up `hyprland.conf` (trailing spaces)

## Usage

### Normal Update (Recommended)
```bash
omarchy-update-safe
```

### Manual Update (if you know what you're doing)
```bash
omarchy-update
```

### Restore from Backup
If an update breaks something, restore from the latest backup:
```bash
# Find the latest backup
ls -t ~/.local/share/omarchy-backups/ | head -1

# Restore (replace TIMESTAMP with actual timestamp)
cp -r ~/.local/share/omarchy-backups/TIMESTAMP/* ~/.local/share/omarchy/
```

## Prevention
- **Don't modify files in `~/.local/share/omarchy/default/` directly**
- Instead, override them in `~/.config/hypr/` or `~/.config/waybar/`
- Use `omarchy-update-safe` for all updates
- Keep your dotfiles repo updated so you can restore quickly

