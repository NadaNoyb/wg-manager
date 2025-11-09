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
# This will now return the base filename (e.g., 'wg0' for 'wg0.conf')
list_config_files() {
    find "$WG_CONFIG_DIR" -maxdepth 1 -name "*.conf" -printf "%f\n" | sed 's/\.conf$//' | sort
}

# Function to get the actual NetworkManager connection name for a given WireGuard interface name
# Returns the NM connection name if found, otherwise empty.
get_nm_connection_name() {
    local interface_base_name="$1" # e.g., "tommy" from "tommy.conf"
    
    # Get all WireGuard connections (both active and inactive)
    # Format: NAME:TYPE where TYPE will be "wireguard"
    local all_wg_conns=$(sudo nmcli -t -f NAME,TYPE connection show | grep ":wireguard$")
    
    # Iterate through all WireGuard connections
    while IFS=: read -r conn_name conn_type; do
        # Try to match the connection name with the base name (without .conf)
        if [[ "$conn_name" == "$interface_base_name" ]]; then
            echo "$conn_name"
            return 0
        fi
        # Also try to match with the .conf extension
        if [[ "$conn_name" == "${interface_base_name}.conf" ]]; then
            echo "$conn_name"
            return 0
        fi
    done <<< "$all_wg_conns"
    
    return 1 # Not found
}


# Function to check WireGuard interface status
get_wg_status() {
    # Check if the interface is up
    if ip link show "$WG_INTERFACE" > /dev/null 2>&1; then
        echo "up"
    else
        echo "down"
    fi
}

# Function to display main menu text (after a profile has been selected)
display_main_menu_text() {
    local current_status=$(get_wg_status)
    echo ""
    echo -e "--- ${BLUE}WG-Manager${NC} (${YELLOW}$WG_INTERFACE${NC}) ---"
    echo -e "Status:        " $( [[ "$current_status" == "up" ]] && echo -e "${GREEN}UP${NC}" || echo -e "${RED}DOWN${NC}" )
    echo -e "---------------------------------"

    echo -e "${YELLOW}1. Bring VPN UP/DOWN${NC}"
    echo -e "${YELLOW}2. Change selected VPN profile${NC}"
    echo -e "${YELLOW}3. Import new VPN profile${NC}"
    echo -e "${YELLOW}4. Delete existing VPN profile${NC}" # New option
    echo -e "${YELLOW}5. Exit${NC}" # Changed number
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

    if [[ -z "$config_file_path_orig" ]]; then
        echo -e "${RED}No path entered. Aborting import.${NC}"
        return 1
    elif [[ ! -f "$config_file_path_orig" ]]; then
        echo -e "${RED}Error: File not found at '$config_file_path_orig'. Aborting import.${NC}"
        return 1
    elif [[ "${config_file_path_orig##*.}" != "conf" ]]; then
        echo -e "${YELLOW}Warning: The file '$config_file_path_orig' does not have a '.conf' extension. Proceeding anyway.${NC}"
    fi

    # Get the filename and base name
    local filename=$(basename "$config_file_path_orig")
    local base_name="${filename%.conf}"
    local dest_path="${WG_CONFIG_DIR}/${filename}"

    # First, copy the file to /etc/wireguard/ if it's not already there
    if [[ ! "$config_file_path_orig" -ef "$dest_path" ]]; then 
        echo -e "${BLUE}Copying '$filename' to $WG_CONFIG_DIR...${NC}"
        if ! sudo cp "$config_file_path_orig" "$dest_path"; then
            echo -e "${RED}Error: Failed to copy '$filename' to $WG_CONFIG_DIR. Aborting import.${NC}"
            return 1
        fi
        echo -e "${GREEN}File copied to $WG_CONFIG_DIR.${NC}"
    fi

    # Now try to import via NetworkManager
    echo -e "${BLUE}Importing '$config_file_path_orig' via nmcli...${NC}"
    local import_output
    import_output=$(sudo nmcli connection import type wireguard file "$dest_path" 2>&1)
    local import_exit=$?
    
    if [[ $import_exit -eq 0 ]]; then
        # Check if the connection was actually created
        local imported_conn=$(sudo nmcli -t -f NAME connection show 2>/dev/null | grep -i "$base_name" | head -n1)
        if [[ -n "$imported_conn" ]]; then
            echo -e "${GREEN}Successfully imported '$config_file_path_orig' as NetworkManager connection '$imported_conn'.${NC}"
        else
            echo -e "${YELLOW}Import command succeeded, but connection name verification failed.${NC}"
            echo -e "${YELLOW}The config file is available at $dest_path and can be used with wg-quick.${NC}"
        fi
        return 0
    else
        # Even if nmcli import fails, the file is already copied, so it's still usable
        echo -e "${YELLOW}Warning: nmcli import failed: ${import_output}${NC}"
        echo -e "${YELLOW}Config file is available at $dest_path and can be used with wg-quick directly.${NC}"
        return 0
    fi
}

# Function: Delete WireGuard config file
delete_wg_config() {
    local base_config_names=($(list_config_files))
    local num_configs=${#base_config_names[@]}

    if [[ $num_configs -eq 0 ]]; then
        echo -e "${RED}No VPN profiles available to delete.${NC}"
        return 1
    fi

    echo ""
    echo -e "${BLUE}--- Select VPN Profile to DELETE ---${NC}"
    local i=1
    for base_name in "${base_config_names[@]}"; do
        echo -e "  ${YELLOW}$i)${NC} $base_name"
        ((i++))
    done
    echo -e "  ${YELLOW}$i) Cancel${NC}"
    echo -e "------------------------------------"

    local delete_choice
    while true; do
        read -rp "$(echo -e "${BLUE}Enter the number of the VPN profile to delete, or '$i' to cancel: ${NC}")" delete_choice
        if [[ "$delete_choice" =~ ^[0-9]+$ ]] && (( delete_choice >= 1 && delete_choice <= num_configs + 1 )); then
            break
        else
            echo -e "${RED}Invalid selection. Please try again.${NC}"
        fi
    done

    if (( delete_choice == num_configs + 1 )); then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        return 1
    fi

    local selected_base_name="${base_config_names[$((delete_choice - 1))]}"
    local conf_file_path="${WG_CONFIG_DIR}/${selected_base_name}.conf"
    
    # Try to find NetworkManager connection (more flexible search)
    local nm_conn_name=$(get_nm_connection_name "$selected_base_name")
    
    # If exact match fails, try to find by partial match or interface name
    if [[ -z "$nm_conn_name" ]]; then
        # Get all WireGuard connections and try to find one that matches
        local all_wg_conns=$(sudo nmcli -t -f NAME,TYPE connection show | grep ":wireguard$")
        while IFS=: read -r conn_name conn_type; do
            # Check if connection name contains the base name or vice versa
            if [[ "$conn_name" == *"$selected_base_name"* ]] || [[ "$selected_base_name" == *"$conn_name"* ]]; then
                nm_conn_name="$conn_name"
                break
            fi
        done <<< "$all_wg_conns"
    fi

    # Build deletion message
    if [[ -n "$nm_conn_name" ]]; then
        echo -e "${YELLOW}WARNING: You are about to DELETE VPN profile '${nm_conn_name}' (associated with '${selected_base_name}.conf').${NC}"
    else
        echo -e "${YELLOW}WARNING: You are about to DELETE VPN profile '${selected_base_name}.conf'.${NC}"
        echo -e "${YELLOW}Note: No NetworkManager connection found for this profile.${NC}"
    fi
    
    read -rp "$(echo -e "${RED}Are you sure you want to delete? (yes/no): ${NC}")" confirm_delete

    if [[ "${confirm_delete,,}" != "yes" ]]; then # Convert to lowercase for case-insensitivity
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        return 1
    fi

    # Delete NetworkManager connection if it exists
    if [[ -n "$nm_conn_name" ]]; then
        echo -e "${BLUE}Deleting NM connection for '${nm_conn_name}'...${NC}"
        if sudo nmcli connection delete "$nm_conn_name" 2>/dev/null; then
            echo -e "${GREEN}Successfully deleted NM connection '${nm_conn_name}'.${NC}"
        else
            echo -e "${YELLOW}Warning: Failed to delete NM connection '${nm_conn_name}', but continuing with file deletion.${NC}"
        fi
    fi
    
    # Always try to remove the .conf file from /etc/wireguard/
    if [[ -f "$conf_file_path" ]]; then
        echo -e "${BLUE}Removing configuration file: '$conf_file_path'...${NC}"
        if sudo rm "$conf_file_path"; then
            echo -e "${GREEN}Configuration file removed.${NC}"
        else
            echo -e "${RED}Error: Failed to remove configuration file '$conf_file_path'. You may need to delete it manually.${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Warning: Configuration file '$conf_file_path' not found.${NC}"
    fi

    # If the deleted profile was the currently selected one, clear WG_INTERFACE
    if [[ "$WG_INTERFACE" == "$selected_base_name" ]]; then
        WG_INTERFACE=""
        echo -e "${YELLOW}The currently selected VPN profile was deleted. Please select a new one.${NC}"
    fi
    
    echo -e "${GREEN}Profile deletion completed.${NC}"
    return 0
}

# Function to handle initial/re-selection of WireGuard interface
select_or_import_profile() {
    while true; do
        local configs=($(list_config_files))
        local num_configs=${#configs[@]}
        local current_option=1 # Counter for menu options

        echo ""
        echo -e "${BLUE}--- Select WireGuard VPN Profile ---${NC}"
        if [[ $num_configs -eq 0 ]]; then
            echo -e "${YELLOW}No existing VPN profiles found.${NC}"
        else
            for config in "${configs[@]}"; do
                echo -e "  ${YELLOW}$current_option)${NC} $config"
                ((current_option++))
            done
        fi
        
        local opt_import=$current_option; ((current_option++))
        local opt_delete=$current_option; ((current_option++))
        local opt_exit=$current_option; # final option number

        echo -e "  ${YELLOW}$opt_import) Import new VPN profile${NC}"
        echo -e "  ${YELLOW}$opt_delete) Delete existing VPN profile${NC}"
        echo -e "  ${YELLOW}$opt_exit) Exit WG-Manager${NC}"
        echo -e "------------------------------------"

        read -rp "$(echo -e "${BLUE}Enter your choice (1-${opt_exit}): ${NC}")" profile_choice

        if [[ "$profile_choice" =~ ^[0-9]+$ ]]; then
            if (( profile_choice >= 1 && profile_choice <= num_configs )); then
                WG_INTERFACE="${configs[$((profile_choice - 1))]}"
                echo -e "${GREEN}Selected profile: $WG_INTERFACE${NC}"
                return 0 # Profile selected
            elif (( profile_choice == opt_import )); then
                if import_wg_config; then
                    echo -e "${YELLOW}Refreshing profile list after import...${NC}"
                    # Loop will re-list profiles
                    configs=($(list_config_files)) # Update configs array
                    num_configs=${#configs[@]}
                    opt_import=$((num_configs + 1))
                    opt_delete=$((num_configs + 2))
                    opt_exit=$((num_configs + 3)) # Ensure these are correct after array update
                fi
            elif (( profile_choice == opt_delete )); then
                if delete_wg_config; then
                    echo -e "${YELLOW}Refreshing profile list after deletion...${NC}"
                    # If the selected WG_INTERFACE was deleted, we need to prompt for re-selection
                    if [[ -z "$WG_INTERFACE" ]]; then
                        echo -e "${YELLOW}No profile currently selected.${NC}"
                    fi
                    configs=($(list_config_files)) # Update configs array
                    num_configs=${#configs[@]}
                    opt_import=$((num_configs + 1))
                    opt_delete=$((num_configs + 2))
                    opt_exit=$((num_configs + 3)) # Ensure these are correct after array update
                fi
            elif (( profile_choice == opt_exit )); then
                echo -e "${YELLOW}Exiting WG-Manager.${NC}"
                exit 0
            else
                echo -e "${RED}Invalid selection. Please try again.${NC}"
            fi
        else
            echo -e "${RED}Invalid input. Please enter a number.${NC}"
        fi
    done
}


# --- Main Script Logic ---

check_root # Ensure the script is run as root/sudo

echo -e "$ASCII_ART" # Display ASCII art

# Initial profile selection or import
# This function now handles initial selection, import, delete, and exit.
WG_INTERFACE="" # Initialize WG_INTERFACE before calling
select_or_import_profile 

# After a profile is successfully selected (function returns 0),
# we enter the main management loop.
while true; do
    # If WG_INTERFACE somehow got cleared (e.g., current profile was deleted),
    # force re-selection before displaying main menu.
    if [[ -z "$WG_INTERFACE" ]]; then
        echo -e "${YELLOW}No VPN profile currently selected. Please choose one.${NC}"
        select_or_import_profile
        continue # Restart loop to display main menu for the new selection
    fi

    display_main_menu_text # Display the main menu
    read -rp "$(echo -e "${BLUE}Enter your choice (1-5): ${NC}")" CHOICE

    CURRENT_STATUS=$(get_wg_status)

    case "$CHOICE" in
        1) # Bring VPN UP/DOWN
            if [[ "$CURRENT_STATUS" == "up" ]]; then
                wg_down
            else
                wg_up
            fi
            ;;
        2) # Change selected VPN profile
            echo -e "${YELLOW}Changing selected VPN profile...${NC}"
            select_or_import_profile # Re-run selection menu
            ;;
        3) # Import new VPN profile
            import_wg_config
            if [[ $? -eq 0 ]]; then # If import was successful
                echo -e "${YELLOW}New profile imported. Please select it or another one.${NC}"
                # After import, force re-selection from the initial menu
                select_or_import_profile 
            fi
            ;;
        4) # Delete existing VPN profile
            delete_wg_config
            # If a profile was deleted, select_or_import_profile will be called in the next loop iteration
            # if WG_INTERFACE is empty.
            ;;
        5) # Exit
            echo -e "${YELLOW}Exiting WG-Manager.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, 3, 4, or 5.${NC}"
            ;;
    esac
    # Add a small delay to make output readable before next loop
    sleep 1
done