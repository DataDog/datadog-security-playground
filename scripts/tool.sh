#!/usr/bin/sh

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
WAIT_FOR_CONFIRM=false
SILENT_MODE=false
STEP=1
ENDPOINT="http://localhost:5000"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -w, --wait     Wait for user confirmation between each step"
    echo "  -s, --silent   Execute inject commands silently (no output)"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                   # Run all steps automatically"
    echo "  $0 --wait            # Wait for confirmation between steps"
    echo "  $0 --silent          # Execute commands silently"
    echo "  $0 -w -s             # Wait for confirmation and execute silently"
}

# Parse command line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case $1 in
            -w|--wait)
                WAIT_FOR_CONFIRM=true
                shift
                ;;
            -s|--silent)
                SILENT_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [ "$SILENT_MODE" = "true" ]; then
        WAIT_FOR_CONFIRM=false
    fi
}

# Wait for user confirmation
wait_for_confirmation() {
    if [ "$WAIT_FOR_CONFIRM" = "true" ]; then
        echo ""
        echo "${YELLOW}Press Enter to continue to the next step, or Ctrl+C to exit...${NC}"
        read -r dummy
        echo ""
    fi
}

# Inject command to target
inject() {
    if [ "$SILENT_MODE" = "true" ]; then
        # Silent mode: execute command without any output
        curl -s -X POST -d "$1" ${ENDPOINT}/inject -o /dev/null
    else
        # Normal mode: show command and execute
        echo "${BLUE}Executing command...${NC}"
        echo
        echo "\033[0;36m\`\`\`\033[0m"
        echo "\033[1;33m$ curl -s -X POST -d \"$1\" ${ENDPOINT}/inject\033[0m"
        echo "\033[0;36m\`\`\`\033[0m"
        echo
        curl -s -X POST -d "$1" ${ENDPOINT}/inject -o /dev/null
    fi
}

# Print function for here-documents
print() {
    if [ "$SILENT_MODE" = "false" ]; then
        while IFS= read -r line; do
            echo "$line"
        done
        echo
    fi

}

# Step function
step() {
    if [ "$SILENT_MODE" = "true" ]; then
        # Silent mode: only increment step counter, no output
        STEP=$(( STEP + 1))
    else
        # Normal mode: show step headers and content
        if [ $STEP = 1 ]; then
            echo "\033[0;34m# Attack steps\033[0m"
            echo
        fi
        echo "\033[1;32m## Step $STEP\033[0m"
        STEP=$(( STEP + 1))
        echo

        print
    fi
}
