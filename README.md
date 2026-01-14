# Project Zomboid Proxmox Helper Scripts

Proxmox VE helper scripts for deploying a Project Zomboid dedicated server in an LXC container. Compatible with the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) project.

## Features

- **Build Selection**: Choose between Build 41 (stable) or Build 42 (beta) during installation
- **Automated Setup**: SteamCMD installation, 32-bit library support, systemd service
- **Console Access**: Screen-based server console for in-game administration
- **Management Scripts**: Built-in scripts for updates and backups
- **Update Support**: Update server and switch between builds via the script

## Requirements

- Proxmox VE 7.0 or later
- Network access for SteamCMD downloads
- Minimum resources: 2 CPU cores, 4GB RAM, 10GB disk

## Installation

### Option 1: Community Scripts (if merged)

```bash
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/project-zomboid.sh)"
```

### Option 2: Direct from this repository

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/mbarber107/pz-proxmox-hs/main/ct/project-zomboid.sh)"
```

## Default Configuration

| Setting | Default Value |
|---------|---------------|
| CPU Cores | 2 |
| RAM | 4096 MB |
| Disk | 10 GB |
| OS | Debian 12 |
| Container Type | Unprivileged |

## Ports

Ensure these ports are accessible on your network/firewall:

| Port | Protocol | Purpose |
|------|----------|---------|
| 16261 | UDP | Game Port 1 |
| 16262 | UDP | Game Port 2 |
| 27015 | TCP | RCON (optional) |

## Post-Installation Setup

### 1. Set Admin Password

After container creation, run the setup script to configure your admin account:

```bash
/opt/pzserver/setup-admin.sh
```

This starts the server interactively and prompts you to create an admin password.

### 2. Start the Server

```bash
systemctl start project-zomboid-screen
systemctl enable project-zomboid-screen  # Enable auto-start on boot
```

### 3. Access Server Console

```bash
screen -r pzserver
```

Detach from console: `Ctrl+A`, then `D`

## Server Management

### Service Commands

```bash
systemctl start project-zomboid-screen    # Start server
systemctl stop project-zomboid-screen     # Stop server (saves world)
systemctl restart project-zomboid-screen  # Restart server
systemctl status project-zomboid-screen   # Check status
```

### Update Server

Run the ct script again from Proxmox host to update:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/mbarber107/pz-proxmox-hs/main/ct/project-zomboid.sh)"
```

Or use the built-in update script from within the container:

```bash
/opt/pzserver/update-server.sh
```

### Backup Server

```bash
/opt/pzserver/backup-server.sh
```

Backups are stored in `/home/pzserver/backups/`

## Configuration Files

| File | Purpose |
|------|---------|
| `/home/pzserver/Zomboid/Server/servertest.ini` | Main server configuration |
| `/home/pzserver/Zomboid/Server/servertest_SandboxVars.lua` | Sandbox/gameplay settings |
| `/home/pzserver/Zomboid/Logs/` | Server logs |
| `/opt/pzserver/.pz_build_version` | Installed build version |

## Console Commands

Common server console commands (use via `screen -r pzserver`):

| Command | Description |
|---------|-------------|
| `quit` | Save and stop server |
| `save` | Force world save |
| `players` | List connected players |
| `adduser <user> <pass>` | Create new user |
| `setaccesslevel <user> <level>` | Set access (admin, moderator, overseer, gm, observer) |
| `kickuser <user>` | Kick a player |
| `banuser <user>` | Ban a player |
| `servermsg <message>` | Broadcast message to all players |

## Adding Mods

Edit `/home/pzserver/Zomboid/Server/servertest.ini`:

```ini
# Workshop item IDs (semicolon-separated)
WorkshopItems=1234567890;0987654321

# Mod folder names (must match WorkshopItems order)
Mods=ModFolder1;ModFolder2
```

Restart the server after adding mods.

## Troubleshooting

### Server won't start

Check logs:
```bash
journalctl -u project-zomboid-screen -f
cat /home/pzserver/Zomboid/Logs/*.txt
```

### Out of memory

Increase container RAM in Proxmox, then restart:
```bash
pct set <CTID> -memory 8192
pct restart <CTID>
```

### Can't connect to server

1. Verify ports 16261-16262 UDP are open
2. Check `Public=true` in servertest.ini for internet-accessible servers
3. Ensure container has network connectivity

## Build Versions

- **Build 41**: Stable release, recommended for most servers
- **Build 42**: Beta/unstable, latest features but may have bugs

Switching between builds is **not save-compatible**. Back up your world before switching.

## License

MIT License - See [LICENSE](https://github.com/community-scripts/ProxmoxVE/blob/main/LICENSE)

## Acknowledgments

- [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) - Helper script framework
- [The Indie Stone](https://projectzomboid.com/) - Project Zomboid developers
- [LinuxGSM](https://linuxgsm.com/) - Linux game server management reference
