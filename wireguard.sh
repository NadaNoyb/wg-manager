#!/bin/bash

# --- Configuration ---
WG_CONFIG_DIR="/etc/wireguard/" # Directory where WireGuard .conf files are stored

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- ASCII Art ---
# Tux Penguin ASCII art with "WG-Manager" correctly aligned
ASCII_ART="${GREEN}
            .--.     
           |o_o |    
           |:_/ |    WG-Manager
          //   \ \   
         (|     | )  
        / \_   _/ \ 
        \___)=(___/  
${NC}"

# --- Functions ---

# Function to check for root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run with sudo or as root.${NC}"
        echo -e "${YELLOW}Please run: sudo bash $0${NC}"
        exit 1
    fi
}

# Function to list available WireGuard configuration files (for selection/deletion)
list_wg_configs() {
    echo -e "${BLUE}Available WireGuard interfaces:${NC}"
    configs=("${WG_CONFIG_DIR}"*.conf)
    if [ ${#configs[@]} -eq 1 ] && [ ! -f "${configs[0]}" ]; then
        echo -e "${YELLOW}No WireGuard configuration files found in $WG_CONFIG_DIR${NC}"
        return 1
    fi
    for i in "${!configs[@]}"; do
        wg_interface=$(basename "${configs[$i]}" .conf)
        # Check if the interface is active
        if wg show "$wg_interface" &>/dev/null; then
            echo -e "  $((i+1))) $wg_interface ${GREEN}(UP)${NC}"
        else
            echo -e "  $((i+1))) $wg_interface ${RED}(DOWN)${NC}"
        fi
    done
    return 0
}

# Function to select a WireGuard interface from the list
select_wg_interface() {
    list_wg_configs
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo ""
    local choice
    read -rp "$(echo -e "${BLUE}Enter the number of the interface you want to manage (or 0 to cancel): ${NC}")" choice
    # Validate input
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt "${#configs[@]}" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return 1
    fi
    if [ "$choice" -eq 0 ]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        return 1
    fi
    WG_INTERFACE=$(basename "${configs[$((choice-1))]}" .conf)
    echo -e "${GREEN}Selected interface: $WG_INTERFACE${NC}"
    return 0
}

# Function to show active WireGuard interface and its status
show_active_interface() {
    echo -e "${BLUE}Checking active WireGuard interfaces...${NC}"
    active_interfaces=$(wg show interfaces)
    if [ -z "$active_interfaces" ]; then
        echo -e "${YELLOW}No active WireGuard interfaces found.${NC}"
        return
    fi
    echo -e "${GREEN}Active interfaces:${NC}"
    for interface in $active_interfaces; do
        echo -e "\n${BLUE}Interface: $interface${NC}"
        wg show "$interface"
    done
}

# Function to bring VPN up
wg_up() {
    echo -e "${BLUE}Bringing VPN $WG_INTERFACE UP...${NC}"
    if ! wg-quick up "$WG_INTERFACE"; then
        echo -e "${RED}ERROR: Failed to bring up VPN $WG_INTERFACE.${NC}"
        echo -e "${YELLOW}Please check your configuration file: $WG_CONFIG_DIR/${WG_INTERFACE}.conf${NC}"
        return 1
    fi
    echo -e "${GREEN}VPN $WG_INTERFACE is UP.${NC}"
    return 0
}

# Function to bring VPN down
wg_down() {
    echo -e "${BLUE}Bringing VPN $WG_INTERFACE DOWN...${NC}"
    if ! wg-quick down "$WG_INTERFACE"; then
        echo -e "${RED}ERROR: Failed to bring down VPN $WG_INTERFACE.${NC}"
        return 1
    fi
    echo -e "${GREEN}VPN $WG_INTERFACE is DOWN.${NC}"
    return 0
}

# Function: Import WireGuard config file
import_wg_config() {
    local config_file_path_orig
    echo ""
    read -rp "$(echo -e "${BLUE}Enter the full path to the .conf file you want to import: ${NC}")" config_file_path_orig

    # Replace spaces in the path with \ 
    local config_file_path="${config_file_path_orig// /\\ }"

    # Check if the file exists
    if [ ! -f "$config_file_path_orig" ]; then
        echo -e "${RED}ERROR: File not found at $config_file_path_orig${NC}"
        return
    fi

    # Extract the base name of the file (e.g., wg0.conf)
    local config_filename
    config_filename=$(basename "$config_file_path_orig")

    # Define the destination path
    local dest_path="${WG_CONFIG_DIR}${config_filename}"

    # Check if a configuration with the same name already exists
    if [ -f "$dest_path" ]; then
        echo -e "${YELLOW}A configuration named '$config_filename' already exists.${NC}"
        read -rp "$(echo -e "${BLUE}Do you want to overwrite it? (y/n): ${NC}")" confirm
        if [[ "$confirm" != "y" ]]; then
            echo -e "${YELLOW}Import cancelled.${NC}"
            return
        fi
    fi

    # Copy the file to the WireGuard directory
    if ! cp "$config_file_path_orig" "$dest_path"; then
        echo -e "${RED}ERROR: Failed to copy the configuration file.${NC}"
        echo -e "${YELLOW}Please check permissions.${NC}"
        return
    fi

    echo -e "${GREEN}Successfully imported '$config_filename' to $WG_CONFIG_DIR${NC}"

    # Set correct permissions for the configuration file
    chmod 600 "$dest_path"
    echo -e "${GREEN}Set permissions for $dest_path to 600.${NC}"
}

# Function to delete a WireGuard configuration file
delete_wg_config() {
    echo -e "${YELLOW}Select a WireGuard configuration to delete:${NC}"
    if ! select_wg_interface; then
        return # Return if no interface is selected or an error occurs
    fi
    
    local config_to_delete="$WG_INTERFACE"
    
    # Double-check with the user before deletion
    read -rp "$(echo -e "${RED}Are you sure you want to PERMANENTLY delete '$config_to_delete.conf'? (y/n): ${NC}")" confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        return
    fi

    # Bring the interface down before deleting, if it's up
    if wg show "$config_to_delete" &>/dev/null; then
        echo -e "${BLUE}Bringing down $config_to_delete before deleting...${NC}"
        if ! wg-quick down "$config_to_delete"; then
            echo -e "${RED}ERROR: Could not bring down $config_to_delete. Deletion aborted.${NC}"
            return
        fi
        echo -e "${GREEN}Interface $config_to_delete is down.${NC}"
    fi

    # Delete the configuration file
    if ! rm "${WG_CONFIG_DIR}${config_to_delete}.conf"; then
        echo -e "${RED}ERROR: Failed to delete '$config_to_delete.conf'.${NC}"
        echo -e "${YELLOW}Please check file permissions.${NC}"
        return
    fi

    echo -e "${GREEN}'$config_to_delete.conf' has been deleted.${NC}"
}

# Function to display the main menu for managing interfaces
manage_interfaces_menu() {
    while true; do
        clear
        echo -e "$ASCII_ART"
        echo -e "${BLUE}--- WireGuard Interface Management ---${NC}\n"
        list_wg_configs
        echo -e "\n${BLUE}Choose an option:${NC}"
        echo "  1) Import new WireGuard configuration"
        echo "  2) Delete existing WireGuard configuration"
        echo "  3) Back to Main Menu"

        local choice
        read -rp "$(echo -e "\n${BLUE}Enter your choice [1-3]: ${NC}")" choice

        case $choice in
            1)
                import_wg_config
                ;;
            2)
                delete_wg_config
                ;;
            3)
                return # Return to main menu
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read -r # Wait for user to press Enter
    done
}


# --- Main Script ---
check_root

while true; do
    clear
    echo -e "$ASCII_ART"
    echo -e "${BLUE}--- WG-Manager Main Menu ---${NC}\n"
    echo -e "${YELLOW}Current Status:${NC}"
    show_active_interface
    echo -e "\n${BLUE}Available Actions:${NC}"
    echo "  1) Activate a WireGuard Interface"
    echo "  2) Deactivate a WireGuard Interface"
    echo "  3) Manage WireGuard Configurations"
    echo "  4) Exit"

    read -rp "$(echo -e "\n${BLUE}Enter your choice [1-4]: ${NC}")" choice

    case $choice in
        1) # Activate
            if select_wg_interface; then
                wg_up
            fi
            ;;
        2) # Deactivate
            if select_wg_interface; then
                wg_down
            fi
            ;;
        3) # Manage
            manage_interfaces_menu
            ;;
        4) # Exit
            echo -e "${YELLOW}Exiting WG-Manager.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, 3, or 4.${NC}"
            ;;
    esac
    echo -e "\n${YELLOW}Press Enter to return to the main menu...${NC}"
    read -r
done
