#!/bin/bash

# Characters for ID generation (a-z, 0-9)
CHARS="abcdefghijklmnopqrstuvwxyz0123456789"
CHAR_COUNT=${#CHARS}

# Base URL
BASE_URL="https://github.com/vishalkc9565/test-bug/commit/"

# Create results directory if it doesn't exist
mkdir -p results

# Function to convert number to base-36 ID
number_to_id() {
    local num=$1
    local id=""
    local temp_num=$num
    
    for ((i=0; i<7; i++)); do
        remainder=$((temp_num % CHAR_COUNT))
        id="${CHARS:$remainder:1}$id"
        temp_num=$((temp_num / CHAR_COUNT))
    done
    
    echo "$id"
}

# Function to make fast request and save if successful
check_commit() {
    local id="$1"
    local url="${BASE_URL}${id}"
    
    # Fast curl with minimal options and short timeout
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$url" 2>/dev/null)
    
    if [ "$http_code" = "200" ]; then
        # Quick save without full page content for speed
        mkdir -p "results/$id" 2>/dev/null
        echo "$url" > "results/$id/found.txt"
        echo "$(date +%s)" >> "results/$id/found.txt"
        return 0
    fi
    return 1
}

# Function to update progress display
update_display() {
    local current=$1
    local found=$2
    local rate=$3
    local elapsed=$4
    local eta=$5
    
    printf "\r\033[K"  # Clear line
    printf "Checked: %d | Found: %d | Rate: %.0f/s | Time: %ds | ETA: %ds" \
           "$current" "$found" "$rate" "$elapsed" "$eta"
}

# Calculate optimal range for 10 minutes
MAX_TIME=600  # 10 minutes in seconds
TARGET_RATE=20000  # Target 20k requests per 10 minutes = ~33/second
TOTAL_COMBINATIONS=$((CHAR_COUNT ** 7))

# Get parameters
MODE=${1:-"fast"}
MAX_CHECKS=${2:-$TARGET_RATE}

case "$MODE" in
    "fast")
        echo "Fast scan mode - optimized for 10 minutes"
        echo "Target checks: $MAX_CHECKS"
        ;;
    "sample")
        SAMPLE_RATE=${2:-$((TOTAL_COMBINATIONS / TARGET_RATE))}
        echo "Sample mode: every ${SAMPLE_RATE}th combination"
        MAX_CHECKS=$((TOTAL_COMBINATIONS / SAMPLE_RATE))
        ;;
    "range")
        START_NUM=${2:-0}
        MAX_CHECKS=${3:-$TARGET_RATE}
        echo "Range mode: starting from $START_NUM, max $MAX_CHECKS checks"
        ;;
    *)
        echo "Usage: $0 [mode] [options]"
        echo "  fast [max_checks]     - Fast random sampling (default: $TARGET_RATE)"
        echo "  sample [rate]         - Every Nth combination"
        echo "  range [start] [count] - Sequential from start position"
        exit 1
        ;;
esac

echo "Starting in 3 seconds... (Ctrl+C to cancel)"
sleep 3

# Initialize counters
found_count=0
total_checks=0
start_time=$(date +%s)

# Trap for clean exit
cleanup() {
    printf "\n\nScan interrupted!\n"
    echo "Total checked: $total_checks"
    echo "Found: $found_count"
    echo "Results in: ./results/"
    exit 0
}
trap cleanup INT

# Main scanning loop based on mode
case "$MODE" in
    "fast")
        # Random sampling for maximum coverage in time limit
        for ((i=0; i<MAX_CHECKS; i++)); do
            # Generate random number for ID
            random_num=$((RANDOM * RANDOM % TOTAL_COMBINATIONS))
            id=$(number_to_id $random_num)
            
            if check_commit "$id" &>/dev/null; then
                ((found_count++))
            fi
            ((total_checks++))
            
            # Update display every 50 checks
            if ((total_checks % 50 == 0)); then
                current_time=$(date +%s)
                elapsed=$((current_time - start_time))
                if [ $elapsed -gt 0 ]; then
                    rate=$((total_checks / elapsed))
                    eta=$(((MAX_CHECKS - total_checks) / (rate > 0 ? rate : 1)))
                else
                    rate=0
                    eta=0
                fi
                update_display $total_checks $found_count $rate $elapsed $eta
                
                # Exit if we're over time limit
                if [ $elapsed -gt $MAX_TIME ]; then
                    break
                fi
            fi
        done
        ;;
        
    "sample")
        for ((i=0; i<TOTAL_COMBINATIONS; i+=SAMPLE_RATE)); do
            id=$(number_to_id $i)
            
            if check_commit "$id" &>/dev/null; then
                ((found_count++))
            fi
            ((total_checks++))
            
            if ((total_checks % 50 == 0)); then
                current_time=$(date +%s)
                elapsed=$((current_time - start_time))
                if [ $elapsed -gt 0 ]; then
                    rate=$((total_checks / elapsed))
                    eta=$(((MAX_CHECKS - total_checks) / (rate > 0 ? rate : 1)))
                else
                    rate=0
                    eta=0
                fi
                update_display $total_checks $found_count $rate $elapsed $eta
                
                if [ $elapsed -gt $MAX_TIME ]; then
                    break
                fi
            fi
            
            if [ $total_checks -ge $MAX_CHECKS ]; then
                break
            fi
        done
        ;;
        
    "range")
        start_pos=${START_NUM:-0}
        for ((i=start_pos; i<start_pos+MAX_CHECKS && i<TOTAL_COMBINATIONS; i++)); do
            id=$(number_to_id $i)
            
            if check_commit "$id" &>/dev/null; then
                ((found_count++))
            fi
            ((total_checks++))
            
            if ((total_checks % 50 == 0)); then
                current_time=$(date +%s)
                elapsed=$((current_time - start_time))
                if [ $elapsed -gt 0 ]; then
                    rate=$((total_checks / elapsed))
                    eta=$(((MAX_CHECKS - total_checks) / (rate > 0 ? rate : 1)))
                else
                    rate=0
                    eta=0
                fi
                update_display $total_checks $found_count $rate $elapsed $eta
                
                if [ $elapsed -gt $MAX_TIME ]; then
                    break
                fi
            fi
        done
        ;;
esac

# Final results
current_time=$(date +%s)
elapsed=$((current_time - start_time))
rate=$((total_checks / (elapsed > 0 ? elapsed : 1)))

printf "\n\n================================\n"
echo "SCAN COMPLETED"
echo "================================"
echo "Time elapsed: ${elapsed}s"
echo "Total checked: $total_checks"
echo "Average rate: ${rate}/s"
echo "Valid commits found: $found_count"
echo ""

if [ $found_count -gt 0 ]; then
    echo "Found commits saved in ./results/"
    echo "Found commit IDs:"
    ls results/ 2>/dev/null | head -20
    if [ $(ls results/ 2>/dev/null | wc -l) -gt 20 ]; then
        echo "... and $(($(ls results/ | wc -l) - 20)) more"
    fi
else
    echo "No valid commits found in this scan."
fi 