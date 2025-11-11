# WG-Manager

A simple, interactive bash script for managing WireGuard VPN profiles on Linux systems.

## Features

- 🚀 **Easy VPN Control**: Bring VPN connections up or down with a single command
- 📥 **Import Profiles**: Import new WireGuard configuration files via NetworkManager
- 🗑️ **Delete Profiles**: Remove VPN profiles and their associated NetworkManager connections
- 📋 **Profile Management**: Switch between multiple VPN profiles easily
- 🎨 **Colorful Interface**: User-friendly colored terminal interface with ASCII art
- ✅ **Error Handling**: Robust error handling and validation

## Requirements

- Linux system with WireGuard installed
- NetworkManager (`nmcli`) installed and running
- Root/sudo privileges
- Bash shell

### Installing WireGuard

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install wireguard wireguard-tools

# Fedora
sudo dnf install wireguard-tools

# Arch Linux
sudo pacman -S wireguard-tools
```

## Installation

1. Clone this repository:
```bash
git clone https://github.com/NadaNoyb/wg-manager.git
cd wg-manager
```

2. Make the script executable:
```bash
chmod +x wireguard.sh
```

3. Run the script with sudo:
```bash
sudo ./wireguard.sh
```

## Usage

### Starting the Script

The script must be run with root privileges:

```bash
sudo ./wireguard.sh
```

or

```bash
sudo bash wireguard.sh
```

### Main Menu Options

Once started, the script will display a menu with the following options:

#### 1. Bring VPN UP/DOWN
- Toggles the VPN connection based on its current status
- If the VPN is **UP**, it will bring it **DOWN**
- If the VPN is **DOWN**, it will bring it **UP**
- Uses `wg-quick` to manage the interface

#### 2. Change Selected VPN Profile
- Opens the profile selection menu
- Allows you to switch to a different VPN profile
- You can also import or delete profiles from this menu

#### 3. Import New VPN Profile
- Prompts you for the full path to a `.conf` file
- Copies the file to `/etc/wireguard/`
- Imports the profile into NetworkManager
- The profile becomes available for selection

**Example:**
```
Enter the full path to the .conf file you want to import: /home/user/my-vpn.conf
```

#### 4. Delete Existing VPN Profile
- Lists all available VPN profiles
- Select the profile you want to delete
- Confirms deletion (type "yes" to confirm)
- Removes both the NetworkManager connection and the config file

#### 5. Exit
- Exits the WG-Manager script

### Profile Selection Menu

When you first start the script or choose to change profiles, you'll see:

1. **List of existing profiles** (numbered)
2. **Import new VPN profile** option
3. **Delete existing VPN profile** option
4. **Exit WG-Manager** option

Simply enter the number corresponding to your choice.

## Configuration

The script stores WireGuard configuration files in `/etc/wireguard/` by default. This is the standard location for WireGuard configs on Linux systems.

You can modify the `WG_CONFIG_DIR` variable in the script if you need to use a different directory:

```bash
WG_CONFIG_DIR="/etc/wireguard/" # Change this to your preferred directory
```

## How It Works

1. **Profile Selection**: The script scans `/etc/wireguard/` for `.conf` files and lists them for selection
2. **NetworkManager Integration**: Uses `nmcli` to import and manage WireGuard connections
3. **Interface Management**: Uses `wg-quick` to bring interfaces up or down
4. **Status Checking**: Checks interface status using `ip link` commands

## Examples

### Example Workflow

1. **Start the script:**
   ```bash
   sudo ./wireguard.sh
   ```

2. **Import a new profile:**
   - Select option to import
   - Enter path: `/home/user/vpn-config.conf`
   - Script copies and imports the profile

3. **Select the profile:**
   - Choose the newly imported profile from the list

4. **Bring VPN up:**
   - Select option 1 (Bring VPN UP/DOWN)
   - VPN connection is established

5. **Bring VPN down:**
   - Select option 1 again
   - VPN connection is terminated

## Troubleshooting

### Script requires root privileges
- Make sure you're running with `sudo`
- The script will display an error message if run without root

### Import fails
- Check that the `.conf` file path is correct
- Ensure the file has proper WireGuard configuration format
- Verify NetworkManager is running: `sudo systemctl status NetworkManager`

### Profile not found
- Ensure `.conf` files are in `/etc/wireguard/`
- Check file permissions: `ls -la /etc/wireguard/`

### VPN won't start
- Check the configuration file for errors
- Verify WireGuard is installed: `which wg-quick`
- Check system logs: `sudo journalctl -u NetworkManager`

## Notes

- The script works with both NetworkManager-managed connections and standalone WireGuard configs
- If NetworkManager import fails, the config file is still copied and can be used with `wg-quick` directly
- Deleted profiles are removed from both NetworkManager and the filesystem
- The currently selected profile is shown in the main menu header

## License

This script is provided as-is for personal use.

## Creating a Desktop Shortcut

You can create a desktop shortcut to launch WG-Manager easily from your desktop environment.

### Steps to Create a Desktop Shortcut

1. Create a `.desktop` file in your applications directory:
   ```bash
   nano ~/.local/share/applications/wg-manager.desktop
   ```

2. Copy and paste the following content (adjust the path to your script location):

```ini
[Desktop Entry]
Name=WG-Manager
Comment=Manage WireGuard VPN connections
Exec=gnome-terminal -- /bin/bash -c "sudo /path/to/your/desktop/filename.sh; echo -e '\nPress Enter to close this window...'; read"
Icon=network-vpn  # You can choose a different icon, e.g., utilities-terminal
Terminal=false
Type=Application
Categories=Network;Utility;
```

3. Replace `/path/to/your/desktop/filename.sh` with the actual path to your `wireguard.sh` script. For example:
   ```bash
   Exec=gnome-terminal -- /bin/bash -c "sudo /home/ts/Documents/wg-mamanger/wireguard.sh; echo -e '\nPress Enter to close this window...'; read"
   ```

4. Make the file executable:
   ```bash
   chmod +x ~/.local/share/applications/wg-manager.desktop
   ```

5. The shortcut should now appear in your applications menu. You can also drag it to your desktop or pin it to your dock/panel.

**Note:** When you click the shortcut, it will open a terminal window asking for your sudo password, then launch the WG-Manager script.

## Contributing

Feel free to submit issues or pull requests if you find bugs or have suggestions for improvements