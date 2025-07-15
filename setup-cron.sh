#!/bin/bash

# setup-cron.sh - Setup automated weekly backups
# Usage: ./setup-cron.sh [--install|--remove|--status]

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BACKUP_SCRIPT="$SCRIPT_DIR/archive-dot-files.sh"
CRON_IDENTIFIER="# SaveDotFiles Weekly Backup"

# Default action
ACTION="${1:-install}"

# Function to check if cron job exists
cron_exists() {
    crontab -l 2>/dev/null | grep -q "SaveDotFiles Weekly Backup"
}

# Function to install cron job
install_cron() {
    echo -e "${YELLOW}Setting up weekly backup cron job...${NC}"
    
    # Check if backup script exists
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        echo -e "${RED}Error: Backup script not found at $BACKUP_SCRIPT${NC}"
        exit 1
    fi
    
    # Check if cron job already exists
    if cron_exists; then
        echo -e "${YELLOW}Cron job already exists. Use --remove first to reinstall.${NC}"
        exit 0
    fi
    
    # Get current crontab
    TEMP_CRON=$(mktemp)
    crontab -l 2>/dev/null > "$TEMP_CRON" || true
    
    # Ask user for preferences
    echo -e "\n${BLUE}Configure your backup schedule:${NC}"
    
    # Day of week
    while true; do
        echo -e "\nWhich day of the week?"
        echo -e "  0 = Sunday"
        echo -e "  1 = Monday"
        echo -e "  2 = Tuesday"
        echo -e "  3 = Wednesday"
        echo -e "  4 = Thursday"
        echo -e "  5 = Friday"
        echo -e "  6 = Saturday"
        read -p "Day [default: 0 (Sunday)]: " DAY_OF_WEEK
        DAY_OF_WEEK=${DAY_OF_WEEK:-0}
        
        # Validate day of week
        if [[ "$DAY_OF_WEEK" =~ ^[0-6]$ ]]; then
            break
        else
            echo -e "${RED}Invalid day! Please enter a number between 0 and 6.${NC}"
        fi
    done
    
    # Hour
    while true; do
        echo -e "\nWhat hour? (0-23, 24-hour format)"
        echo -e "  Examples: 0 = midnight, 2 = 2 AM, 14 = 2 PM, 18 = 6 PM"
        read -p "Hour [default: 2 (2 AM)]: " HOUR
        HOUR=${HOUR:-2}
        
        # Validate hour
        if [[ "$HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
            break
        else
            echo -e "${RED}Invalid hour! Please enter a number between 0 and 23.${NC}"
            echo -e "${YELLOW}Note: Use 24-hour format (0-23), not 1800 for 6 PM.${NC}"
        fi
    done
    
    # Push to GitHub?
    echo -e "\nPush backups to GitHub? (y/N)"
    read -p "Push to GitHub: " PUSH_GITHUB
    PUSH_OPTION=""
    if [[ "$PUSH_GITHUB" =~ ^[Yy]$ ]]; then
        PUSH_OPTION=" --push"
    fi
    
    # Log file location
    LOG_FILE="$HOME/.local/log/savedotfiles-backup.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check if anacron is available
    if ! command -v anacron >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Anacron not found!${NC}"
        echo -e "Anacron ensures backups run even if your machine was off at scheduled time."
        echo -e "\nWould you like to install anacron for better reliability?"
        read -p "Install anacron? (y/N): " INSTALL_ANACRON
        
        if [[ "$INSTALL_ANACRON" =~ ^[Yy]$ ]]; then
            # Detect package manager and install anacron
            if command -v apt-get >/dev/null 2>&1; then
                echo -e "${YELLOW}Installing anacron...${NC}"
                sudo apt-get update && sudo apt-get install -y anacron
            elif command -v yum >/dev/null 2>&1; then
                echo -e "${YELLOW}Installing anacron...${NC}"
                sudo yum install -y cronie-anacron
            elif command -v dnf >/dev/null 2>&1; then
                echo -e "${YELLOW}Installing anacron...${NC}"
                sudo dnf install -y cronie-anacron
            elif command -v pacman >/dev/null 2>&1; then
                echo -e "${YELLOW}Installing anacron...${NC}"
                sudo pacman -S --noconfirm cronie
            else
                echo -e "${RED}Could not detect package manager. Please install anacron manually.${NC}"
                echo -e "Then run this script again."
                exit 1
            fi
            
            # Check if installation was successful
            if command -v anacron >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Anacron installed successfully!${NC}"
            else
                echo -e "${RED}Anacron installation failed. Continuing with regular cron only.${NC}"
            fi
        fi
    fi
    
    # Check again if anacron is available (after potential installation)
    if command -v anacron >/dev/null 2>&1; then
        echo -e "\n${GREEN}Anacron detected!${NC} Using anacron for better reliability."
        echo -e "Backups will run even if your machine was off at scheduled time."
        
        # Create anacron entry
        # Anacron format: period delay job-identifier command
        ANACRON_ENTRY="7 10 savedotfiles-backup cd $SCRIPT_DIR && ./archive-dot-files.sh weekly-auto-backup$PUSH_OPTION >> $LOG_FILE 2>&1"
        
        # Check if we can write to system anacron (requires sudo)
        ANACRON_FILE="/etc/anacron"
        if [[ -w "$ANACRON_FILE" ]]; then
            # Add to system anacron
            if ! grep -q "savedotfiles-backup" "$ANACRON_FILE"; then
                echo "$ANACRON_ENTRY" >> "$ANACRON_FILE"
            fi
        else
            # Use user anacron if available
            USER_ANACRON="$HOME/.anacron"
            mkdir -p "$USER_ANACRON/spool"
            
            # Create anacrontab file with proper format
            cat > "$USER_ANACRON/anacrontab" << EOF
# period delay job-identifier command
7 10 savedotfiles-backup cd $SCRIPT_DIR && ./archive-dot-files.sh weekly-auto-backup$PUSH_OPTION >> $LOG_FILE 2>&1
EOF
            
            # Add a cron job to run user anacron hourly
            echo "" >> "$TEMP_CRON"
            echo "$CRON_IDENTIFIER - Anacron Runner" >> "$TEMP_CRON"
            echo "# Run anacron hourly to catch up on missed backups" >> "$TEMP_CRON"
            echo "0 * * * * /usr/sbin/anacron -t $USER_ANACRON/anacrontab -S $USER_ANACRON/spool" >> "$TEMP_CRON"
        fi
    fi
    
    # Always add regular cron job as fallback
    echo "" >> "$TEMP_CRON"
    echo "$CRON_IDENTIFIER - Regular" >> "$TEMP_CRON"
    echo "# Runs every week on day $DAY_OF_WEEK at $HOUR:00" >> "$TEMP_CRON"
    echo "0 $HOUR * * $DAY_OF_WEEK cd $SCRIPT_DIR && ./archive-dot-files.sh weekly-auto-backup$PUSH_OPTION >> $LOG_FILE 2>&1" >> "$TEMP_CRON"
    
    # Install new crontab
    crontab "$TEMP_CRON"
    rm "$TEMP_CRON"
    
    # Get day name for display
    DAY_NAMES=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
    DAY_NAME=${DAY_NAMES[$DAY_OF_WEEK]}
    
    echo -e "\n${GREEN}✓ Backup job installed successfully!${NC}"
    echo -e "  Schedule: Every $DAY_NAME at $HOUR:00 (${HOUR}:00 in 24-hour format)"
    echo -e "  Log file: $LOG_FILE"
    if [[ -n "$PUSH_OPTION" ]]; then
        echo -e "  GitHub push: ${GREEN}Enabled${NC}"
    else
        echo -e "  GitHub push: ${RED}Disabled${NC}"
    fi
    
    if command -v anacron >/dev/null 2>&1; then
        echo -e "\n${GREEN}✓ Anacron protection enabled${NC}"
        echo -e "  Missed backups will run when your machine is back online"
    else
        echo -e "\n${YELLOW}Note:${NC} Anacron not found. Backups will only run if machine is on at scheduled time."
        echo -e "  Consider installing anacron for better reliability: sudo apt install anacron"
    fi
}

# Function to remove cron job
remove_cron() {
    echo -e "${YELLOW}Removing backup jobs...${NC}"
    
    REMOVED=false
    
    # Remove cron job
    if cron_exists; then
        TEMP_CRON=$(mktemp)
        crontab -l 2>/dev/null | grep -v "SaveDotFiles Weekly Backup" | grep -v "weekly-auto-backup" | grep -v "anacron" > "$TEMP_CRON"
        crontab "$TEMP_CRON"
        rm "$TEMP_CRON"
        echo -e "${GREEN}✓ Cron job removed${NC}"
        REMOVED=true
    fi
    
    # Remove anacron entries if they exist
    if command -v anacron >/dev/null 2>&1; then
        # Remove from system anacron if we have permission
        if [[ -w "/etc/anacron" ]] && grep -q "savedotfiles-backup" "/etc/anacron" 2>/dev/null; then
            sudo sed -i '/savedotfiles-backup/d' /etc/anacron
            echo -e "${GREEN}✓ System anacron entry removed${NC}"
            REMOVED=true
        fi
        
        # Remove user anacron
        USER_ANACRON="$HOME/.anacron"
        if [[ -d "$USER_ANACRON" ]]; then
            rm -rf "$USER_ANACRON"
            echo -e "${GREEN}✓ User anacron entries removed${NC}"
            REMOVED=true
        fi
    fi
    
    if [[ "$REMOVED" == true ]]; then
        echo -e "\n${GREEN}✓ All backup jobs removed successfully!${NC}"
    else
        echo -e "${YELLOW}No backup jobs found to remove.${NC}"
    fi
}

# Function to show cron status
show_status() {
    echo -e "${BLUE}Backup Cron Job Status:${NC}"
    echo ""
    
    if cron_exists; then
        echo -e "Status: ${GREEN}Installed${NC}"
        echo -e "\nCurrent configuration:"
        crontab -l | grep -A2 "$CRON_IDENTIFIER" | sed 's/^/  /'
        
        # Check log file
        LOG_FILE="$HOME/.local/log/savedotfiles-backup.log"
        if [[ -f "$LOG_FILE" ]]; then
            echo -e "\nLast 5 backup entries:"
            tail -5 "$LOG_FILE" | sed 's/^/  /'
        else
            echo -e "\nNo backup logs found yet."
        fi
    else
        echo -e "Status: ${RED}Not installed${NC}"
        echo -e "\nRun './setup-cron.sh --install' to set up automatic backups."
    fi
}

# Main logic
case "$ACTION" in
    --install|install)
        install_cron
        ;;
    --remove|remove)
        remove_cron
        ;;
    --status|status)
        show_status
        ;;
    --help|help|-h)
        echo "Usage: $0 [--install|--remove|--status]"
        echo ""
        echo "Options:"
        echo "  --install  Set up weekly backup cron job (default)"
        echo "  --remove   Remove the backup cron job"
        echo "  --status   Show current cron job status"
        echo "  --help     Show this help message"
        ;;
    *)
        echo -e "${RED}Unknown option: $ACTION${NC}"
        echo "Use --help for usage information."
        exit 1
        ;;
esac