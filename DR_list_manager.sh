#!/bin/bash

# ==============================================================================
# INITIAL SETTINGS AND VARIABLES
# ==============================================================================
APP_VERSION="3.8_en"
# Default .csv file, whenever the app starts this file is loaded
CSV_FILE="Repeater_list.csv"
TEMP_FILE="temp_fixed.csv"
LOCK_FILE="/tmp/dr_list_manager.lock"
exit_to_main=0
SCRIPT_PID=$$

count_records() {
    local n
    n=$(tail -n +2 "$CSV_FILE" 2>/dev/null | grep -c '[^[:space:]]' 2>/dev/null) || n=0
    echo "$n"
}

check_csv_integrity() {
    local file="${1:-$CSV_FILE}"
    [ -f "$file" ] || return 0
    local wrong_line
    wrong_line=$(awk -F';' 'NR>1 && NF!=17 && NF>0 {print NR; exit}' "$file")
    if [[ -n "$wrong_line" ]]; then
        local field_count
        field_count=$(awk -F';' -v l="$wrong_line" 'NR==l{print NF}' "$file")
        echo -e "${RED}⚠ Warning: The file '$file' is corrupted at line $wrong_line (expected 17 fields, found $field_count)${NC}"
        echo -e "${YELLOW}Execute Option 5 -> Validate Database to try to repair.${NC}"
        return 1
    fi
    return 0
}

clear_lock() {
    rm -f "$LOCK_FILE"
}

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo -e "${RED}Error: An instance is already running (PID $lock_pid). Close the other instance before opening again.${NC}"
            return 1
        else
            echo -e "${YELLOW}Stale lock removed (PID $lock_pid no longer responding).${NC}"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo "$SCRIPT_PID" > "$LOCK_FILE"
    trap clear_lock EXIT INT TERM
    return 0
}

GREEN='\033[38;5;46m'
WHITE='\033[1;37m'
YELLOW='\033[38;5;226m'
ORANGE='\033[38;5;208m'
RED='\033[38;5;196m'
RED_DARK='\033[38;5;124m'
GRAY='\033[38;5;250m'
GREEN2='\033[0;32m'
YELLOW2='\033[1;33m'
RED2='\033[0;31m'
BLUE='\033[38;5;39m'
BLUE_BRIGHT='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

VALID_TONES=(
    "67,0" "69,3" "71,9" "74,4" "77,0" "79,7" "82,5" "85,4" "88,5" "91,5"
    "94,8" "97,4" "100,0" "103,5" "107,2" "110,9" "114,8" "118,8" "123,0"
    "127,3" "131,8" "136,5" "141,3" "146,2" "151,4" "156,7" "159,8" "162,2"
    "165,5" "167,9" "171,3" "173,8" "177,3" "179,9" "183,5" "186,2" "189,9"
    "192,8" "196,6" "199,5" "203,5" "206,5" "210,7" "218,1" "225,7" "229,1"
    "233,6" "241,8" "250,3" "254,1"
)

# ==============================================================================
# INTERACTIVE ENGINE 1: TEXT READING AND REGEX (WITH AUTO-UPPERCASE)
# ==============================================================================
read_field() {
    local prompt="$1" regex="$2" error_msg="$3" current_value="$4" max_len="$5"

    while true; do
        local hint="[X to cancel]"
        if [[ -n "$current_value" ]]; then hint="[Enter keeps: ${ORANGE}${current_value}${NC} | X to cancel]"; fi

        local input_val
        echo -en ">> $prompt $hint: " >&2
        read input_val < /dev/tty

        if [[ "${input_val,,}" == "x" ]]; then return 1; fi
        if [[ -z "$input_val" && -n "$current_value" ]]; then echo "$current_value"; return 0; fi

        if [[ "$prompt" == *"Frequency"* || "$prompt" == *"Offset"* || "$prompt" == *"Latitude"* || "$prompt" == *"Longitude"* || "$prompt" == *"Tone"* ]]; then
            input_val="${input_val//./,}"
        fi

        if [[ "$prompt" == *"Call Sign"* || "$prompt" == *"Gateway"* ]]; then
            input_val="${input_val^^}"
        fi

        if [[ "$input_val" == *";"* ]]; then echo -e "  ${RED}Error: The ';' character is not allowed.${NC}" >&2; continue; fi
        if [[ -n "$max_len" && ${#input_val} -gt $max_len ]]; then echo -e "  ${RED}Error: Maximum $max_len characters allowed.${NC}" >&2; continue; fi

        if [[ -n "$regex" ]]; then
            if [[ "$input_val" =~ $regex ]]; then echo "$input_val"; return 0; else echo -e "  ${RED}Error: $error_msg${NC}" >&2; fi
        else
            if [[ "$input_val" =~ ^[[:print:]]*$ ]]; then echo "$input_val"; return 0; else echo -e "  ${RED}Error: Unsupported characters.${NC}" >&2; fi
        fi
    done
}

# ==============================================================================
# INTERACTIVE ENGINE 2: NUMBERED MENUS FOR STANDARDIZED VALUES
# ==============================================================================
read_option() {
    local prompt="$1" default_val="$2"
    shift 2
    local options=("$@")

    while true; do
        local menu_str=""
        for i in "${!options[@]}"; do
            menu_str+="$((i+1))) ${options[$i]}   "
        done

        local hint="[X to cancel]"
        [[ -n "$default_val" ]] && hint="[Enter keeps: ${ORANGE}${default_val}${NC} | X to cancel]"

        echo -e "  $prompt: ${YELLOW2}${menu_str}${NC}" >&2
        local input_val
        echo -en ">> Choose (1-${#options[@]}) $hint: " >&2
        read input_val < /dev/tty

        [[ "${input_val,,}" == "x" ]] && return 1
        [[ -z "$input_val" && -n "$default_val" ]] && { echo "$default_val"; return 0; }

        if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#options[@]}" ]; then
            echo "${options[$((input_val - 1))]}"
            return 0
        fi
        echo -e "  ${RED}Error: Choose a number between 1 and ${#options[@]}.${NC}" >&2
    done
}

# ==============================================================================
# INTERACTIVE ENGINE 3: CTCSS TONE TABLE
# ==============================================================================
read_tone() {
    local prompt="$1" default_val="${2:-}"

    echo -e "\n  ${CYAN}--- STANDARD ICOM CTCSS TONE TABLE ---${NC}" >&2
    local i col=0
    for ((i = 0; i < ${#VALID_TONES[@]}; i++)); do
        printf "  ${YELLOW2}%2d${NC}) %-6s" "$((i+1))" "${VALID_TONES[$i]}" >&2
        ((col++))
        if [[ $((col % 7)) -eq 0 ]]; then echo >&2; fi
    done
    echo >&2

    while true; do
        local hint="[X to cancel]"
        [[ -n "$default_val" ]] && hint="[Enter keeps: ${ORANGE}${default_val}${NC} | X to cancel]"

        local input_val
        echo -en ">> $prompt (1-${#VALID_TONES[@]}) $hint: " >&2
        read input_val < /dev/tty

        [[ "${input_val,,}" == "x" ]] && return 1
        [[ -z "$input_val" && -n "$default_val" ]] && { echo "$default_val"; return 0; }

        if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#VALID_TONES[@]}" ]; then
            echo "${VALID_TONES[$((input_val - 1))]}Hz"
            return 0
        fi
        echo -e "  ${RED}Error: Choose a number between 1 and ${#VALID_TONES[@]}.${NC}" >&2
    done
}

# ==============================================================================
# FUNCTION: DYNAMIC HEADER (ADAPTS TO TERMINAL WIDTH)
# ==============================================================================
show_header() {
    local border_color="${BLUE_BRIGHT}"
    if [[ "$1" == "--green" ]]; then border_color="${GREEN}"; shift; fi

    local cols
    cols=$(tput cols 2>/dev/null)
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [[ "$cols" -lt 30 ]]; then cols=53; fi
    [[ "$cols" -gt 80 ]] && cols=80
    local inner=$((cols - 2))
    local border
    printf -v border '%*s' "$inner" ''
    border="${border// /═}"

    echo -e "${border_color}╔${border}╗"
    for title in "$@"; do
        local len=${#title}
        local pad=$(( (inner - len) / 2 ))
        local pad_r=$(( inner - len - pad ))
        local title_safe="${title//%/%%}"
        printf "${border_color}║${WHITE}%${pad}s%s%${pad_r}s${border_color}║${NC}\n" '' "$title_safe" ''
    done
    echo -e "${border_color}╚${border}╝${NC}"
}

print_text() {
    local color="${1:-$NC}"; shift
    local cols
    cols=$(tput cols 2>/dev/null)
    [[ ! "$cols" =~ ^[0-9]+$ ]] || [[ "$cols" -lt 30 ]] && cols=53
    [[ "$cols" -gt 80 ]] && cols=80
    local max_char=$((cols - 2))
    local fold_text
    fold_text=$(printf '%s' "$*" | fold -s -w "$max_char")
    while IFS= read -r line; do
        echo -e "${color}${line}${NC}"
    done <<< "$fold_text"
}

# ==============================================================================
# FUNCTION: DYNAMIC SEPARATOR (ADAPTS TO TERMINAL WIDTH, MAX 80)
# ==============================================================================
separator() {
    local color="${1:-$GREEN2}" char="${2:-═}"
    local cols
    cols=$(tput cols 2>/dev/null)
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [[ "$cols" -lt 30 ]]; then cols=53; fi
    [[ "$cols" -gt 80 ]] && cols=80
    local line
    printf -v line '%*s' "$cols" ''
    line="${line// /$char}"
    echo -e "${color}${line}${NC}"
}

# ==============================================================================
# FUNCTION: DISPLAY MAIN MENU
# ==============================================================================
show_menu() {
    clear

    local _cols_m
    _cols_m=$(tput cols 2>/dev/null)
    [[ ! "$_cols_m" =~ ^[0-9]+$ ]] || [[ "$_cols_m" -lt 30 ]] && _cols_m=53
    [[ "$_cols_m" -gt 80 ]] && _cols_m=80
    local _inner_m=$(( _cols_m - 2 ))
    local _border_m
    printf -v _border_m '%*s' "$_inner_m" ''
    _border_m="${_border_m// /═}"

    echo -e "${GREEN}╔${_border_m}╗"
    local _t1="REPEATER MANAGER - D-Star / FM"
    local _len1=${#_t1}
    local _pad1=$(( (_inner_m - _len1) / 2 ))
    local _pad1r=$(( _inner_m - _len1 - _pad1 ))
    printf "${GREEN}║${WHITE}%${_pad1}s%s%${_pad1r}s${GREEN}║${NC}\n" '' "$_t1" ''
    local _t2l="ICOM DR LIST"
    local _t2r="v${APP_VERSION}"
    local _len2l=${#_t2l}
    local _pad2=$(( (_inner_m - _len2l) / 2 ))
    local _len2r=${#_t2r}
    local _gap=$(( _inner_m - _pad2 - _len2l - _len2r - 3 ))
    [[ "$_gap" -lt 1 ]] && _gap=1
    local _gap_pad
    printf -v _gap_pad '%*s' "$_gap" ''
    printf "${GREEN}║${WHITE}%${_pad2}s%s${_gap_pad}${GREEN}  ${_t2r} ║${NC}\n" '' "$_t2l"
    echo -e "${GREEN}╚${_border_m}╝${NC}"
    echo -e "    File     : ${ORANGE}${CSV_FILE}${NC}"
    echo -e "    Records  : ${ORANGE}$(count_records)${NC}"

    if [ -f "$CSV_FILE" ]; then
        local n_groups
        n_groups=$(awk -F';' 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' "$CSV_FILE" | sort -u | wc -l)
        echo -e "    Groups   : ${ORANGE}${n_groups}${NC}"
    fi
    echo
    echo -e "1. Edit Repeaters ${GRAY}(List / Edit / Delete)${NC}"
    echo    "2. Add Repeater"
    echo -e "3. Edit Groups ${GRAY}(Rename / Remove)${NC}"
    echo -e "4. General Query ${GRAY}(Advanced Filters)${NC}"
    echo    "5. Manage Database"
    echo    "X. Exit System"
    separator "$GREEN2" "═"
    read -p "Choose an option: " option < /dev/tty
}

# ==============================================================================
# FILE VALIDATION ENGINE WITH INTERACTIVE ON-THE-FLY CORRECTION
# ==============================================================================
validate_file_engine() {
    local target_file="$1"
    > "$TEMP_FILE"
    local line_num=1
    local auto_corrections=0
    local ignored_lines=0

    local total_lines
    total_lines=$(wc -l < "$target_file")
    local total_data=$((total_lines - 1))

    declare -A seen_keys
    declare -A callsigns_modes
    declare -A callsigns_bands
    while IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset || [ -n "$group_no" ]; do
        utc_offset=$(echo "$utc_offset" | tr -d '\r')

        if [ "$line_num" -gt 1 ]; then
            local pct=$(( (line_num - 2) * 100 / total_data ))
            [[ "$pct" -gt 100 ]] && pct=100
            printf "\r${ORANGE}Progress: %d / %d lines (%d%%)${NC}" "$((line_num - 1))" "$total_data" "$pct" >&2
        fi

        if [ "$line_num" -eq 1 ]; then
            echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$TEMP_FILE"
            ((line_num++)); continue
        fi

        while true; do
            local line_errors=""
            local line_corrections=""

            # Convert periods to commas - do this first!
            if [[ "$freq" == *.* ]]; then 
                line_corrections+="Frequency: converted decimal point to comma ($freq -> ${freq//./,}). "
                freq="${freq//./,}"; ((auto_corrections++))
            fi
            if [[ "$offset" == *.* ]]; then 
                line_corrections+="Offset: converted decimal point to comma ($offset -> ${offset//./,}). "
                offset="${offset//./,}"; ((auto_corrections++))
            fi
            if [[ "$lat" == *.* ]]; then 
                line_corrections+="Latitude: converted decimal point to comma ($lat -> ${lat//./,}). "
                lat="${lat//./,}"; ((auto_corrections++))
            fi
            if [[ "$lon" == *.* ]]; then 
                line_corrections+="Longitude: converted decimal point to comma ($lon -> ${lon//./,}). "
                lon="${lon//./,}"; ((auto_corrections++))
            fi
            if [[ "$rpt_tone" == *.* ]]; then 
                line_corrections+="Repeater Tone: converted decimal point to comma ($rpt_tone -> ${rpt_tone//./,}). "
                rpt_tone="${rpt_tone//./,}"; ((auto_corrections++))
            fi

            # Fix Repeater Tone without Hz suffix
            if [[ "$mode" == "FM" || "$mode" == "FM-N" || "$mode" == "DV" ]]; then
                if [[ -n "$rpt_tone" ]] && [[ "$rpt_tone" != *Hz ]] && [[ ! "$rpt_tone" =~ [Hh][Zz]$ ]]; then
                    line_corrections+="Repeater Tone: added Hz suffix ($rpt_tone -> ${rpt_tone}Hz). "
                    rpt_tone="${rpt_tone}Hz"; ((auto_corrections++))
                fi
            fi

            if [[ "$dup" == "OFF" && "$offset" != "0,000000" ]]; then
                line_corrections+="Offset: reset to 0,000000 for Simplex mode (was $offset). "
                offset="0,000000"; ((auto_corrections++))
            fi

            if [[ "$mode" == "DV" ]]; then
                if [[ "$tone" != "OFF" ]]; then 
                    line_corrections+="TONE: set to OFF for DV mode (was $tone). "
                    tone="OFF"; ((auto_corrections++))
                fi
                if [[ "$rpt_tone" != "88,5Hz" ]]; then 
                    line_corrections+="Repeater Tone: set to 88,5Hz for DV mode (was $rpt_tone). "
                    rpt_tone="88,5Hz"; ((auto_corrections++))
                fi
            elif [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
                if [[ "$tone" == "OFF" && "$rpt_tone" != "88,5Hz" ]]; then
                    line_corrections+="Repeater Tone: set to 88,5Hz for FM mode with OFF tone (was $rpt_tone). "
                    rpt_tone="88,5Hz"; ((auto_corrections++))
                fi
            fi

            local key_dup="${group_no}_${name}_${freq}"
            if [[ -n "${seen_keys[$key_dup]}" && "${seen_keys[$key_dup]}" != "$line_num" ]]; then
                line_errors+="  - Duplicate Entry: identical to line ${seen_keys[$key_dup]}.\n"
            fi

            # Extract Current Band - After converting from period to comma
            local freq_int="${freq//,/}"
            local current_band=""

            # Validate if freq_int is a valid number
            if [[ "$freq_int" =~ ^[0-9]+$ ]]; then
                if [[ 10#$freq_int -ge 144000000 && 10#$freq_int -le 148000000 ]]; then current_band="VHF"
                elif [[ 10#$freq_int -ge 430000000 && 10#$freq_int -le 450000000 ]]; then current_band="UHF"
                else line_errors+="  - Frequency: Out of allowed range (144-148 / 430-450 MHz).\n"; fi
            else
                line_errors+="  - Frequency: Invalid format ($freq).\n"
            fi

            # Hybrid Repeater Callsign Validation (DV vs Cross-Band Analog)
            if [[ -n "$rpt_call" ]]; then
                local conflict_res=""

                # Check 1: Main CSV (if we are importing an external)
                if [[ "$target_file" != "$CSV_FILE" && -f "$CSV_FILE" ]]; then
                    conflict_res=$(awk -F';' -v call="$rpt_call" -v mode="$mode" -v band="$current_band" '
                    $5==call {
                        if ($10 == "DV" || mode == "DV") { print "DV"; exit }
                        f=$7; gsub(",", "", f); b="";
                        if (f >= 144000000 && f <= 148000000) b="VHF";
                        else if (f >= 430000000 && f <= 450000000) b="UHF";
                        if (b == band) { print "BAND"; exit }
                    }' "$CSV_FILE")
                fi

                # Check 2: Memory of the file being processed
                if [[ -z "$conflict_res" ]]; then
                    local mem_mode="${callsigns_modes[$rpt_call]}"
                    local mem_bands="${callsigns_bands[$rpt_call]}"
                    if [[ -n "$mem_mode" ]]; then
                        if [[ "$mode" == "DV" || "$mem_mode" == "DV" ]]; then conflict_res="DV"
                        elif [[ -n "$current_band" && "$mem_bands" == *"$current_band"* ]]; then conflict_res="BAND"
                        fi
                    fi
                fi

                if [[ "$conflict_res" == "DV" ]]; then
                    line_errors+="  - Callsign '$rpt_call' conflicts with DV rule (total exclusivity).\n"
                elif [[ "$conflict_res" == "BAND" ]]; then
                    line_errors+="  - Callsign '$rpt_call' already has a repeater on band $current_band.\n"
                fi
            fi

            if ! [[ "$group_no" =~ ^([1-9]|[1-4][0-9]|50)$ ]]; then line_errors+="  - Group No: Invalid ($group_no).\n"; fi
            if [[ ${#group_name} -gt 16 ]] || ! [[ "$group_name" =~ ^[[:print:]]*$ ]]; then line_errors+="  - Group Name: Invalid or too long.\n"; fi
            if [[ ${#name} -gt 16 ]] || ! [[ "$name" =~ ^[[:print:]]*$ ]]; then line_errors+="  - Name: Invalid or too long.\n"; fi
            if [[ ${#sub_name} -gt 8 ]] || ! [[ "$sub_name" =~ ^[[:print:]]*$ ]]; then line_errors+="  - Sub Name: Invalid or too long.\n"; fi
            if ! [[ "$dup" =~ ^(OFF|DUP\+|DUP\-)$ ]]; then line_errors+="  - Dup: Invalid ($dup).\n"; fi
            if ! [[ "$mode" =~ ^(DV|FM|FM-N)$ ]]; then line_errors+="  - Mode: Invalid ($mode).\n"; fi

            if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then
                if [[ "$mode" == "DV" ]]; then
                    if [[ -z "$rpt_call" ]] || [[ ${#rpt_call} -gt 8 ]] || ! [[ "$rpt_call" =~ ^.{7}[A-Z]$ ]]; then line_errors+="  - Repeater Call: Invalid for DV.\n"; fi
                    if [[ -z "$gw_call" ]] || ! [[ "$gw_call" =~ ^.{7}G$ ]] || [[ "${rpt_call:0:7}" != "${gw_call:0:7}" ]]; then line_errors+="  - Gateway Call: Invalid for DV.\n"; fi
                else
                    if [[ -n "$rpt_call" && ${#rpt_call} -gt 8 ]]; then line_errors+="  - Repeater Call: Exceeds 8 chars.\n"; fi
                    if [[ -n "$gw_call" ]]; then line_errors+="  - Gateway Call: Must be empty for FM/FM-N.\n"; fi
                fi
            else
                if [[ -n "$rpt_call" ]]; then line_errors+="  - Repeater Call: Must be empty for Simplex.\n"; fi
                if [[ -n "$gw_call" ]]; then line_errors+="  - Gateway Call: Must be empty for Simplex.\n"; fi
            fi

            if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then
                if ! [[ "$offset" =~ ^[0-9],[0-9]{6}$ ]]; then line_errors+="  - Offset: Invalid format ($offset).\n"; fi
            fi

            if [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
                if ! [[ "$tone" =~ ^(OFF|TONE|TSQL)$ ]]; then line_errors+="  - TONE: Invalid ($tone).\n"; fi
                if [[ -n "$rpt_tone" ]]; then
                    local clean_tone
                    clean_tone=$(echo "$rpt_tone" | sed 's/Hz//i')
                    local tone_valid=false
                    for t in "${VALID_TONES[@]}"; do if [[ "$t" == "$clean_tone" ]]; then tone_valid=true; break; fi; done
                    if [[ "$tone_valid" == false ]]; then line_errors+="  - Repeater Tone: Outside Icom standard ($rpt_tone).\n"; fi
                else
                    line_errors+="  - Repeater Tone: Cannot be empty in FM/FM-N.\n"
                fi
            elif [[ "$mode" == "DV" ]]; then
                if [[ "$tone" != "OFF" ]]; then line_errors+="  - TONE: Must be OFF for DV.\n"; fi
                if [[ "$rpt_tone" != "88,5Hz" ]]; then line_errors+="  - Repeater Tone: Must be 88,5Hz for DV.\n"; fi
            fi

            if ! [[ "$rpt1use" =~ ^(YES|NO)$ ]]; then line_errors+="  - RPT1USE: Invalid.\n"; fi
            if ! [[ "$position" =~ ^(None|Approximate|Exact)$ ]]; then line_errors+="  - Position: Invalid.\n"; fi
            if ! [[ "$lat" =~ ^-?[0-9]{1,2},[0-9]{6}$ ]]; then line_errors+="  - Latitude: Invalid.\n"; fi
            if ! [[ "$lon" =~ ^-?[0-9]{1,3},[0-9]{6}$ ]]; then line_errors+="  - Longitude: Invalid.\n"; fi
            if ! [[ "$utc_offset" =~ ^([+-]?[0-9]{1,2}:[0-9]{2}|--:--)$ ]]; then line_errors+="  - UTC Offset: Invalid.\n"; fi

            if [[ -n "$line_errors" ]]; then
                echo -e "\n${RED}⚠ Error(s) found at Line $line_num (${name}):${NC}"
                printf '%b\n' "$line_errors"

                local error_action
                while true; do
                    read -p ">> Choose: [C]orrect | [I]gnore line | [A]bort process: " error_action < /dev/tty
                    error_action="${error_action,,}"
                    if [[ "$error_action" == "c" || "$error_action" == "i" || "$error_action" == "a" ]]; then break; fi
                done

                if [[ "$error_action" == "a" ]]; then
                    echo -e "${YELLOW}Validation aborted by user.${NC}"
                    rm -f "$TEMP_FILE"; return 1
                elif [[ "$error_action" == "i" ]]; then
                    echo -e "${YELLOW}Line $line_num ignored and will not be imported.${NC}"
                    log_operation "IMPORT_VALIDATION_IGNORED" "Line $line_num (Group: $group_no | Name: $name | Reason: Errors in record)"
                    ((ignored_lines++)); break
                elif [[ "$error_action" == "c" ]]; then
                    echo -e "${CYAN}--- CORRECTION MODE ---${NC}"

                    group_no=$(read_field "Group No (1-50)" "^([1-9]|[1-4][0-9]|50)$" "1-50" "$group_no" "") || return 1
                    group_name=$(read_field "Group Name" "" "" "$group_name" 16) || return 1
                    name=$(read_field "Name" "" "" "$name" 16) || return 1
                    sub_name=$(read_field "Sub Name" "" "" "$sub_name" 8) || return 1
                    mode=$(read_option "Mode" "$mode" "DV" "FM" "FM-N") || return 1
                    dup=$(read_option "Dup" "$dup" "OFF" "DUP-" "DUP+") || return 1

                    if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then offset=$(read_field "Offset" "^[0-9],[0-9]{6}$" "0,000000" "$offset" "") || return 1
                    else offset="0,000000"; fi

                    while true; do
                        freq=$(read_field "Frequency (ex: 439,975000)" "^[0-9]{3},[0-9]{6}$" "Format 000,000000" "$freq" "") || return 1
                        local f_int="${freq//,/}"
                        if [[ 10#$f_int -ge 144000000 && 10#$f_int -le 148000000 ]]; then current_band="VHF"; break;
                        elif [[ 10#$f_int -ge 430000000 && 10#$f_int -le 450000000 ]]; then current_band="UHF"; break;
                        else echo -e "  ${RED}Error: Out of allowed range.${NC}" >&2; fi
                    done

                    while true; do
                        if [[ "$dup" != "OFF" ]]; then
                            if [[ "$mode" == "DV" ]]; then rpt_call=$(read_field "Repeater Call Sign" "^.{7}[A-Z]$" "Requires 8 chars, last A-Z" "$rpt_call" 8) || return 1
                            else rpt_call=$(read_field "Repeater Call Sign (Optional)" "" "" "$rpt_call" 8) || return 1; fi
                        else rpt_call=""; fi

                        if [[ -n "$rpt_call" ]]; then
                            local invalid=0

                            local m_md="${callsigns_modes[$rpt_call]}"
                            local m_bd="${callsigns_bands[$rpt_call]}"
                            if [[ -n "$m_md" ]]; then
                                if [[ "$mode" == "DV" || "$m_md" == "DV" ]]; then
                                    echo -e "  ${RED}Error: Callsign '$rpt_call' conflicts with DV rule (in this file).${NC}" >&2; invalid=1
                                elif [[ -n "$current_band" && "$m_bd" == *"$current_band"* ]]; then
                                    echo -e "  ${RED}Error: Callsign '$rpt_call' already filled band $current_band (in this file).${NC}" >&2; invalid=1
                                fi
                            fi

                            if [[ "$invalid" == "0" && "$target_file" != "$CSV_FILE" && -f "$CSV_FILE" ]]; then
                                local c_res
                            c_res=$(awk -F';' -v call="$rpt_call" -v mode="$mode" -v band="$current_band" '
                                $5==call {
                                    if ($10 == "DV" || mode == "DV") { print "DV"; exit }
                                    f=$7; gsub(",", "", f); b="";
                                    if (f >= 144000000 && f <= 148000000) b="VHF";
                                    else if (f >= 430000000 && f <= 450000000) b="UHF";
                                    if (b == band) { print "BAND"; exit }
                                }' "$CSV_FILE")

                                if [[ "$c_res" == "DV" ]]; then echo -e "  ${RED}Error: Callsign '$rpt_call' conflicts with DV rule in DB.${NC}" >&2; invalid=1;
                                elif [[ "$c_res" == "BAND" ]]; then echo -e "  ${RED}Error: Callsign '$rpt_call' already occupies band $current_band in DB.${NC}" >&2; invalid=1; fi
                            fi
                            if [ $invalid -eq 1 ]; then continue; fi
                        fi
                        break
                    done

                    if [[ "$dup" != "OFF" && "$mode" == "DV" ]]; then
                        local gw_def="${rpt_call:0:7}G"
                        gw_call=$(read_field "Gateway Call Sign" "^.{7}G$" "Requires 8 positions, last G." "$gw_def" 8) || return 1
                    else gw_call=""; fi

                    if [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
                        tone=$(read_option "TONE" "$tone" "OFF" "TONE" "TSQL") || return 1
                        if [[ "$tone" != "OFF" ]]; then rpt_tone=$(read_tone "Choose Repeater Tone" "${rpt_tone//Hz/}") || return 1
                        else rpt_tone="88,5Hz"; fi
                    elif [[ "$mode" == "DV" ]]; then
                        tone="OFF"; rpt_tone="88,5Hz"
                    fi

                    rpt1use=$(read_option "RPT1USE" "$rpt1use" "YES" "NO") || return 1
                    position=$(read_option "Position" "$position" "None" "Approximate" "Exact") || return 1

                    if [[ "$position" != "None" ]]; then
                        lat=$(read_field "Latitude" "^-?[0-9]{1,2},[0-9]{6}$" "Format -00,000000" "$lat" "") || return 1
                        lon=$(read_field "Longitude" "^-?[0-9]{1,3},[0-9]{6}$" "Format -000,000000" "$lon" "") || return 1
                    else lat="0,000000"; lon="0,000000"; fi

                    utc_offset=$(read_field "UTC Offset" "^([+-]?[0-9]{1,2}:[0-9]{2}|--:--)$" "-3:00 or --:--" "$utc_offset" "") || return 1
                    log_operation "IMPORT_VALIDATION_CORRECTED" "Line $line_num manually corrected (Group: $group_no | Name: $name)"
                    continue
                fi
            else
                seen_keys[$key_dup]=$line_num

                if [[ -n "$rpt_call" ]]; then
                    callsigns_modes[$rpt_call]="$mode"
                    if [[ -z "${callsigns_bands[$rpt_call]}" ]]; then
                        callsigns_bands[$rpt_call]="$current_band"
                    elif [[ "${callsigns_bands[$rpt_call]}" != *"$current_band"* ]]; then
                        callsigns_bands[$rpt_call]+=",$current_band"
                    fi
                fi

                # Log automatic corrections for this line
                if [[ -n "$line_corrections" ]]; then
                    log_operation "IMPORT_AUTO_CORRECTION_LINE_$line_num" "Group: $group_no | Name: $name | Corrections: $line_corrections"
                fi

                echo "$group_no;$group_name;$name;$sub_name;$rpt_call;$gw_call;$freq;$dup;$offset;$mode;$tone;$rpt_tone;$rpt1use;$position;$lat;$lon;$utc_offset" >> "$TEMP_FILE"
                break
            fi
        done
        ((line_num++))
    done < "$target_file"

    printf "\r${ORANGE}Progress: %d / %d lines (100%%)${NC}\n" "$total_data" "$total_data" >&2
    echo -e "\n${GREEN2}Validation completed. Valid lines processed: $((line_num - 2 - ignored_lines))${NC}"
    if [ $ignored_lines -gt 0 ]; then echo -e "${YELLOW}Lines ignored due to errors: $ignored_lines${NC}"; fi
    if [ $auto_corrections -gt 0 ]; then echo -e "${CYAN}Automatic corrections applied: $auto_corrections${NC}"; fi
    
    # Summary log
    log_operation "IMPORT_VALIDATION_SUMMARY" "Total lines processed: $((line_num - 2)) | Auto-corrections: $auto_corrections | Ignored lines: $ignored_lines"
    
    return 0
}

# ==============================================================================
# FILE MANAGEMENT FUNCTIONS (SELECT AND EXPORT)
# ==============================================================================
select_base() {
    echo -e "\n${CYAN}--- SELECT DATABASE ---${NC}"
    local backup_before="${CSV_FILE}.backup"
    if [ -f "$CSV_FILE" ]; then
        cp "$CSV_FILE" "$backup_before"
        echo -e "${YELLOW}Automatic backup saved: $backup_before${NC}"
    fi
    echo -e "Current base: ${YELLOW}$CSV_FILE${NC}"

    local csv_files=()
    for f in *.csv; do
        if [[ -f "$f" && "$f" != "$TEMP_FILE" ]]; then csv_files+=("$f"); fi
    done

    local input_val="" create=""
    if [ ${#csv_files[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}--- CSV FILES FOUND ---${NC}"
        for i in "${!csv_files[@]}"; do
            if [[ "${csv_files[$i]}" == "$CSV_FILE" ]]; then
                printf " [%02d] - %s ${ORANGE}(Current Base)${NC}\n" "$((i+1))" "${csv_files[$i]}"
            else
                printf " [%02d] - %s\n" "$((i+1))" "${csv_files[$i]}"
            fi
        done
        separator "$YELLOW"
        read -p ">> Choose the number, type a new name, or X to cancel: " input_val < /dev/tty
    else
        read -p ">> Type the name of the new CSV file (or X to cancel): " input_val < /dev/tty
    fi

    if [[ "${input_val,,}" == "x" || -z "$input_val" ]]; then return; fi

    local new_base=""
    if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#csv_files[@]}" ]; then
        new_base="${csv_files[$((input_val-1))]}"
    else
        new_base="$input_val"
    fi

    if [[ "$new_base" != *".csv" ]]; then
        new_base="${new_base}.csv"
    fi

    if [ ! -f "$new_base" ]; then
        echo -e "${YELLOW}Warning: The file '$new_base' does not exist in the current directory.${NC}"
        read -p "Do you want to create a new empty base with this name? (y/N): " create < /dev/tty
        if [[ "${create,,}" == "y" ]]; then
            echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$new_base"
            CSV_FILE="$new_base"
            echo -e "${GREEN2}New base '$CSV_FILE' created and selected successfully!${NC}"
        else
            echo -e "${RED}Operation cancelled.${NC}"
        fi
    else
        CSV_FILE="$new_base"
        log_operation "BASE_SELECT" "Base selected: $CSV_FILE"
        echo -e "${GREEN2}Base changed successfully to: '$CSV_FILE'${NC}"
    fi
    sleep 2
}

export_base() {
    echo -e "\n${CYAN}--- EXPORT DATABASE ---${NC}"
    if [ ! -f "$CSV_FILE" ]; then
        echo -e "${RED}Error: The current base '$CSV_FILE' was not found.${NC}"
        sleep 2; return
    fi

    local current_date
    current_date=$(date +%Y%m%d)
    local seq=1
    local export_name=""

    while true; do
        export_name=$(printf "Rpt%s_%02d.csv" "$current_date" "$seq")
        if [ ! -f "$export_name" ]; then
            break
        fi
        ((seq++))
    done

    if cp "$CSV_FILE" "$export_name"; then
        log_operation "EXPORT" "Base exported as $export_name"
        echo -e "${GREEN2}Export completed successfully!${NC}"
        echo -e "File generated: ${YELLOW}$export_name${NC}"
    else
        echo -e "${RED}Error: Export failed. Check disk space.${NC}"
        rm -f "$export_name"
    fi
    sleep 2
}

delete_base() {
    echo -e "\n${CYAN}--- DELETE DATABASE ---${NC}"
    
    local csv_files=()
    for f in *.csv; do
        if [[ -f "$f" && "$f" != "$TEMP_FILE" ]]; then csv_files+=("$f"); fi
    done

    if [ ${#csv_files[@]} -eq 0 ]; then
        echo -e "${RED}No CSV files available to delete.${NC}"
        sleep 2; return
    fi

    echo -e "${YELLOW}--- AVAILABLE CSV FILES ---${NC}"
    for i in "${!csv_files[@]}"; do
        if [[ "${csv_files[$i]}" == "$CSV_FILE" ]]; then
            printf " [%02d] - %s ${ORANGE}(Current Base - Cannot Delete)${NC}\n" "$((i+1))" "${csv_files[$i]}"
        else
            printf " [%02d] - %s\n" "$((i+1))" "${csv_files[$i]}"
        fi
    done
    separator "$YELLOW"
    read -p ">> Choose the file number to delete, or X to cancel: " input_val < /dev/tty

    if [[ "${input_val,,}" == "x" || -z "$input_val" ]]; then return; fi

    if ! [[ "$input_val" =~ ^[0-9]+$ ]] || [ "$input_val" -lt 1 ] || [ "$input_val" -gt "${#csv_files[@]}" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        sleep 2; return
    fi

    local file_to_delete="${csv_files[$((input_val-1))]}"

    if [[ "$file_to_delete" == "$CSV_FILE" ]]; then
        echo -e "${RED}Error: You cannot delete the current base. Select another base first.${NC}"
        sleep 2; return
    fi

    echo -e "\n${RED}⚠️  WARNING: You are about to DELETE the file: ${YELLOW}$file_to_delete${NC}"
    read -p "Are you absolutely sure you want to DELETE this file permanently? (y/N): " conf < /dev/tty

    if [[ "${conf,,}" == "y" ]]; then
        if rm -f "$file_to_delete"; then
            log_operation "DELETE_BASE" "Database file deleted: $file_to_delete"
            echo -e "${GREEN2}File deleted successfully!${NC}"
        else
            echo -e "${RED}Error: Could not delete the file.${NC}"
        fi
    else
        echo -e "${CYAN}Operation cancelled. File kept intact.${NC}"
    fi
    sleep 2
}

# ==============================================================================
# OPTION 5: MANAGE DATABASE (Import / Validate / Clean / Export)
# ==============================================================================
manage_base_menu() {
    clear
    show_header "MANAGE DATABASE"
    echo -e "    Currently selected base: ${ORANGE}$CSV_FILE${NC}"
    echo -e "    CSV standard: ${ORANGE}Separator [ ; ], Decimal [ , ]${NC}\n"

    echo    "1. Select Base CSV File"
    echo    "2. Import CSV"
    echo -e "3. Export DR_list.csv ${GRAY}(RptYYYYMMDD_XX.csv)${NC}"
    echo    "4. Validate Database"
    echo    "5. Delete Database"
    echo -e "6. Clear Database ${GRAY}(Keep header only)${NC}"
    echo    "X. Return"
    separator "$GREEN2"
    read -p ">> Option: " sub_opt < /dev/tty

    case $sub_opt in
        1) select_base ;;
        2) import_csv ;;
        3) export_base ;;
        4)
            if [ ! -f "$CSV_FILE" ]; then
                echo -e "${RED}Error: The file '$CSV_FILE' was not found.${NC}"
                sleep 2; return
            fi
            validate_database
            ;;
        5) delete_base ;;
        6)
            if [ ! -f "$CSV_FILE" ]; then
                echo -e "${RED}Error: The file '$CSV_FILE' was not found.${NC}"
                sleep 2; return
            fi
            clear_database
            ;;
        *) return ;;
    esac
}

validate_database() {
    echo -e "\n${ORANGE}CHECKING DATABASE...${NC}"
    if validate_file_engine "$CSV_FILE"; then
        mv "$TEMP_FILE" "$CSV_FILE"
        echo -e "${GREEN2}Database is standardized.${NC}"
    fi
    read -p $'\nPress [Enter] to return...' < /dev/tty
}

clear_database() {
    echo -e "\n${RED}⚠️  WARNING: You are about to DELETE ALL records!${NC}"
    print_text "${GRAY}" "This action cannot be undone, the base will be empty."
    read -p "Are you absolutely sure you want to CLEAR the CSV file? (y/N): " conf < /dev/tty

    if [[ "${conf,,}" == "y" ]]; then
        echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$CSV_FILE"
        log_operation "CLEANUP" "Database cleared by user"
        clean_old_backups 7
        echo -e "${GREEN2}Database cleared successfully! Only the header was kept.${NC}"
    else
        echo -e "${CYAN}Operation cancelled. Database kept intact.${NC}"
    fi
    sleep 2
}

# ==============================================================================
# OPTION 5: IMPORT CSV
# ==============================================================================
import_csv() {
    clear
    show_header "IMPORT CSV"

    local csv_files=()
    for f in *.csv; do
        if [[ -f "$f" && "$f" != "$TEMP_FILE" ]]; then csv_files+=("$f"); fi
    done

    local input_val=""
    if [ ${#csv_files[@]} -gt 0 ]; then
        echo -e "${YELLOW}--- AVAILABLE CSV FILES ---${NC}"
        for i in "${!csv_files[@]}"; do
            if [[ "${csv_files[$i]}" == "$CSV_FILE" ]]; then
                printf " [%02d] - %s ${ORANGE}(Current Base - Do Not Import)${NC}\n" "$((i+1))" "${csv_files[$i]}"
            else
                printf " [%02d] - %s\n" "$((i+1))" "${csv_files[$i]}"
            fi
        done
        separator "$YELLOW"
        read -p ">> Choose the file number, type the name, or X to cancel: " input_val < /dev/tty
    else
        read -p ">> Type the file name (ex: file.csv) or X to cancel: " input_val < /dev/tty
    fi

    if [[ "${input_val,,}" == "x" || -z "$input_val" ]]; then return; fi

    local file_import=""
    if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#csv_files[@]}" ]; then
        file_import="${csv_files[$((input_val-1))]}"
    else
        file_import="$input_val"
    fi

    if [[ "$file_import" != *".csv" ]]; then
        file_import="${file_import}.csv"
    fi

    if [ ! -f "$file_import" ]; then echo -e "${RED}Error: File '$file_import' not found!${NC}"; sleep 2; return; fi

    if [[ "$file_import" == "$CSV_FILE" ]]; then
        echo -e "${RED}Critical error: You cannot import the current base into itself!${NC}"
        sleep 3; return
    fi

    echo -e "\n${ORANGE}--- Auditing the file to import ---${NC}"

    if validate_file_engine "$file_import"; then
        echo -e "\n${YELLOW}How would you like to integrate this data into your base?${NC}"
        echo "  [R] - REPLACE the entire current base with this file"
        echo "  [A] - ADD (Append) this data to the end of the current base"
        echo "  [C] - CANCEL import"
        read -p ">> Option: " action_import < /dev/tty

        if [[ "${action_import,,}" == "r" ]]; then
            mv "$TEMP_FILE" "$CSV_FILE"
            log_operation "IMPORT" "Base replaced by: $TEMP_FILE"
            echo -e "${GREEN2}Base replaced successfully!${NC}"
        elif [[ "${action_import,,}" == "a" ]]; then
            if [ ! -f "$CSV_FILE" ]; then
                mv "$TEMP_FILE" "$CSV_FILE"
            else
                declare -A base_groups
                while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
                    if [[ "$g_no" =~ ^[0-9]+$ ]]; then base_groups["$g_no"]="$g_name"; fi
                done < "$CSV_FILE"

                declare -A import_groups
                while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
                    if [[ "$g_no" =~ ^[0-9]+$ ]]; then import_groups["$g_no"]="$g_name"; fi
                done < "$TEMP_FILE"

                for g in "${!import_groups[@]}"; do
                    if [[ -n "${base_groups[$g]}" && "${base_groups[$g]}" != "${import_groups[$g]}" ]]; then
                        echo -e "\n${YELLOW}⚠ Conflict detected in Group $g!${NC}"
                        echo -e "  Current base: ${GREEN2}${base_groups[$g]}${NC}"
                        echo -e "  Import: ${CYAN}${import_groups[$g]}${NC}"
                        echo "  [K] Keep current base name"
                        echo "  [U] Update to import name"

                        while true; do
                            read -p ">> Which name do you want to unify? (K/U): " conflict_opt < /dev/tty
                            if [[ "${conflict_opt,,}" == "u" ]]; then
                                local tmp_gi; tmp_gi=$(mktemp)
                                awk -F';' -v OFS=';' -v gno="$g" -v gname="${import_groups[$g]}" \
                                    'NR==1 {print; next} $1==gno {$2=gname} {print}' "$CSV_FILE" > "$tmp_gi" && mv "$tmp_gi" "$CSV_FILE"
                                break
                            elif [[ "${conflict_opt,,}" == "k" ]]; then
                                local tmp_gb; tmp_gb=$(mktemp)
                                awk -F';' -v OFS=';' -v gno="$g" -v gname="${base_groups[$g]}" \
                                    'NR==1 {print; next} $1==gno {$2=gname} {print}' "$TEMP_FILE" > "$tmp_gb" && mv "$tmp_gb" "$TEMP_FILE"
                                break
                            else
                                echo -e "${RED}Choose K or U.${NC}"
                            fi
                        done
                    fi
                done

                tail -n +2 "$TEMP_FILE" >> "$CSV_FILE"
            fi
            rm -f "$TEMP_FILE"
            log_operation "IMPORT" "Data added by append to current base"
            echo -e "${GREEN2}Data added to existing base successfully!${NC}"
        else
            rm -f "$TEMP_FILE"
            echo -e "${YELLOW}Import cancelled.${NC}"
        fi
    fi
    read -p $'\nPress [Enter] to return to menu...' < /dev/tty
}

# ==============================================================================
# OPTION 4: GENERAL QUERY WITH ADVANCED FILTERS AND NAVIGATION
# ==============================================================================
general_query() {
    exit_to_main=0
    unset map_groups

    while true; do
        clear
        show_header "QUERY DATABASE"
        if [ ! -f "$CSV_FILE" ]; then echo -e "${RED}Empty base.${NC}"; sleep 2; return; fi

        local filters_col=()
        local filters_val=()
        local filters_type=()

        print_text "$GRAY" "Allows combining filters for up to 3 key fields."
        print_text "$GRAY" "Choose one or more fields and enter a value, when done press [Enter] to search."

        for i in {1..3}; do
            echo -e "\n${CYAN}--- Filter $i ---${NC}"
            echo "1) Group    2) Mode    3) RPT1USE    4) Call Sign    5) Frequency"
            read -p "Choose the field by number (or [Enter] / X to cancel): " field_choice < /dev/tty

            if [[ "${field_choice,,}" == "x" ]]; then return; fi
            if [[ -z "$field_choice" ]]; then break; fi

            local col_idx=0
            local search_term=""
            local match_type="partial"

            case "$field_choice" in
                1)
                    echo -e "\n${YELLOW}--- AVAILABLE GROUPS ---${NC}"
                    unset map_groups
                    declare -A map_groups
                    while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
                        if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_groups["$g_no"]="$g_name"; fi
                    done < "$CSV_FILE"

                    for k in $(printf "%s\n" "${!map_groups[@]}" | sort -n); do
                        printf " [%02d] - %s\n" "$k" "${map_groups[$k]}"
                    done
                    separator "$YELLOW"

                    search_term=$(read_field "Group Number" "^([1-9]|[1-4][0-9]|50)$" "Must be between 1 and 50" "" "") || return
                    search_term=$((10#$search_term))
                    col_idx=1; match_type="exact"
                    ;;
                2)
                    search_term=$(read_option "Mode" "" "DV" "FM" "FM-N") || return
                    col_idx=10; match_type="exact"
                    ;;
                3)
                    search_term=$(read_option "RPT1USE" "" "YES" "NO") || return
                    col_idx=13; match_type="exact"
                    ;;
                4)
                    search_term=$(read_field "Call Sign (or part of it)" "" "" "" 8) || return
                    col_idx=5; match_type="partial"
                    ;;
                5)
                    search_term=$(read_field "Frequency (or part of it)" "" "" "" "") || return
                    col_idx=7; match_type="partial"
                    ;;
                *)
                    echo -e "${RED}Invalid option, ignored.${NC}"; continue
                    ;;
            esac

            if [[ -n "$search_term" ]]; then
                filters_col+=("$col_idx")
                filters_val+=("${search_term,,}")
                filters_type+=("$match_type")
            fi
        done

        if [ ${#filters_col[@]} -eq 0 ]; then
            echo -e "${YELLOW}No filters applied. Returning to menu...${NC}"
            sleep 1; return
        fi

        unset results_data results_data_sorted
        declare -a results_data=()
        declare -a result_lines=()
        local csv_line=1
        while IFS=';' read -ra COLUMNS || [ -n "${COLUMNS[0]}" ]; do
            if [ "$csv_line" -eq 1 ]; then ((csv_line++)); continue; fi

            local match_all=true
            for j in "${!filters_col[@]}"; do
                local idx=$((${filters_col[$j]} - 1))
                local column_value="${COLUMNS[$idx],,}"
                local filter_value="${filters_val[$j]}"
                local match_type_current="${filters_type[$j]}"

                if [[ "$match_type_current" == "exact" ]]; then
                    if [[ "$column_value" != "$filter_value" ]]; then match_all=false; break; fi
                else
                    if [[ "$column_value" != *"$filter_value"* ]]; then match_all=false; break; fi
                fi
            done

            if $match_all; then
                results_data+=("${COLUMNS[1]};${COLUMNS[2]};${COLUMNS[4]};${COLUMNS[9]};${COLUMNS[6]};${csv_line}")
            fi
            ((csv_line++))
        done < "$CSV_FILE"

        if [ ${#results_data[@]} -eq 0 ]; then
            echo -e "${RED}No results found for the given filters.${NC}"
            read -p $'\nPress [Enter]...' < /dev/tty
            break
        fi

        declare -a results_data_sorted=()
        while IFS= read -r sorted_line; do
            results_data_sorted+=("$sorted_line")
        done < <(printf '%s\n' "${results_data[@]}" | sort -t';' -k1,1f -k2,2f)
        results_data=("${results_data_sorted[@]}")
        unset results_data_sorted

        local page=1
        local total_items=${#results_data[@]}

        while true; do
            clear
            local _cols_r; _cols_r=$(tput cols 2>/dev/null)
            [[ ! "$_cols_r" =~ ^[0-9]+$ ]] && _cols_r=53
            [[ "$_cols_r" -gt 80 ]] && _cols_r=80
            local _lines_r; _lines_r=$(tput lines 2>/dev/null)
            [[ ! "$_lines_r" =~ ^[0-9]+$ ]] || [[ "$_lines_r" -lt 15 ]] && _lines_r=24
            local items_per_page=$(( _lines_r - 12 ))
            [[ "$items_per_page" -lt 5 ]] && items_per_page=5
            local total_pages=$(( (total_items + items_per_page - 1) / items_per_page ))
            local _label=" RESULTS "
            local _side=$(( (_cols_r - ${#_label}) / 2 ))
            local _side_r=$(( _cols_r - ${#_label} - _side ))
            local _left _right
            printf -v _left '%*s' "$_side" ''; _left="${_left// /═}"
            printf -v _right '%*s' "$_side_r" ''; _right="${_right// /═}"
            echo -e "\n${GREEN2}${_left}${_label}${_right}${NC}"
            printf "${YELLOW}%-3s | %-16s | %-16s | %-10s | %-4s | %-10s${NC}\n" " No " "GROUP" "REPEATER" "CALLSIGN" "MODE" "FREQUENCY"
            separator "$GREEN2"

            local start=$(( (page - 1) * items_per_page ))
            local end=$(( start + items_per_page ))
            [ "$end" -gt "$total_items" ] && end=$total_items
            declare -A line_map=()
            local screen_counter=1

            for ((i=start; i<end; i++)); do
                IFS=';' read -r gn nm rc md fr lorig <<< "${results_data[$i]}"
                line_map[$((screen_counter+start))]="$lorig"
                printf " %-3s | %-16.16s | %-16.16s | %-10.10s | %-4.4s | %-10.10s\n" \
                    "$((screen_counter+start))" "$gn" "$nm" "$rc" "$md" "$fr"
                ((screen_counter++))
            done

            separator "$GREEN2"
            echo -e "${YELLOW}Page $page of $total_pages ($total_items items)${NC}"
            echo -e "${CYAN}[N] Next pg | [P] Prev pg | [S] New Search | [X] Main Menu${NC}"
            read -p ">> Number to detail (or indicated key): " chosen_rep < /dev/tty
            if [[ "${chosen_rep,,}" == "x" ]]; then exit_to_main=1; return; fi
            if [[ "${chosen_rep,,}" == "s" || -z "$chosen_rep" ]]; then break; fi
            if [[ "${chosen_rep,,}" == "n" ]]; then
                if [[ "$page" -lt "$total_pages" ]]; then ((page++)); fi
                unset line_map
                continue
            fi
            if [[ "${chosen_rep,,}" == "p" ]]; then
                if [[ "$page" -gt 1 ]]; then ((page--)); fi
                unset line_map
                continue
            fi

            if ! [[ "$chosen_rep" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: Enter only numbers or [N/P] to navigate pages.${NC}"; sleep 1; continue
            fi

            local real_line=${line_map[$chosen_rep]}
            if [[ -z "$real_line" ]]; then echo -e "${RED}Invalid option.${NC}"; sleep 1; continue; fi

            detail_repeater "$real_line"
            if [[ "$exit_to_main" == "1" ]]; then return; fi
        done
    done
}

# ==============================================================================
# OPTION 1: LIST AND DETAIL REPEATERS WITH "BACK" NAVIGATION
# ==============================================================================
list_repeaters() {
    exit_to_main=0
    while true; do
        clear
        show_header "LIST OF REGISTERED GROUPS"
        if [ ! -f "$CSV_FILE" ]; then echo -e "${RED}Warning: Empty base.${NC}"; sleep 2; return; fi
        unset map_groups count_groups
        declare -A map_groups; declare -A count_groups; local has_groups=0
        while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
            if [[ "$g_no" =~ ^[0-9]+$ ]]; then
                map_groups["$g_no"]="$g_name"; count_groups["$g_no"]=$((count_groups["$g_no"] + 1)); has_groups=1
            fi
        done < "$CSV_FILE"

        if [ $has_groups -eq 0 ]; then echo -e "${RED}No groups found.${NC}"; read -p "Press [Enter]..." < /dev/tty; return; fi

        for k in $(printf "%s\n" "${!map_groups[@]}" | sort -n); do
            printf " ${YELLOW}[%02d]${NC} - %-22.22s ${CYAN}( %02d stations registered )${NC}\n" "$k" "${map_groups[$k]}" "${count_groups[$k]}"
        done

        separator "$GREEN2"
        read -p "Type the group number (or [X] Main Menu): " group_num < /dev/tty
        if [[ "${group_num,,}" == "x" || -z "$group_num" ]]; then return; fi

        if ! [[ "$group_num" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: Enter only numbers.${NC}"; sleep 1; continue
        fi

        group_num=$((10#$group_num))

        if [[ -z "${map_groups[$group_num]}" ]]; then echo -e "${RED}Invalid group.${NC}"; sleep 1; continue; fi

        list_repeaters_from_group "$group_num" "${map_groups[$group_num]}"
        if [[ "$exit_to_main" == "1" ]]; then return; fi
    done
}

list_repeaters_from_group() {
    local group_num=$1; local group_name=$2
    local page=1

    while true; do
        local term_lines
        term_lines=$(tput lines 2>/dev/null)
        [[ ! "$term_lines" =~ ^[0-9]+$ ]] || [[ "$term_lines" -lt 15 ]] && term_lines=24
        local items_per_page=$(( term_lines - 12 ))
        [[ "$items_per_page" -lt 5 ]] && items_per_page=5
        clear
        show_header "LISTING REPEATERS FROM GROUP $group_num — $group_name"

        printf "${YELLOW}%-3s | %-16s | %-16s | %-10s | %-4s | %-10s${NC}\n" " No " "GROUP" "REPEATER" "CALLSIGN" "MODE" "FREQUENCY"
        separator "$GREEN2"

        local raw_data=()
        local csv_line=1
        while IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset || [ -n "$group_no" ]; do
            if [ "$csv_line" -eq 1 ]; then ((csv_line++)); continue; fi
            if [ "$group_no" == "$group_num" ]; then
                raw_data+=("$(printf '%-16s|%-16s|%-10s|%-4s|%-10s|%s' "$group_name" "$name" "$rpt_call" "$mode" "$freq" "$csv_line")")
            fi
            ((csv_line++))
        done < "$CSV_FILE"

        local group_data=()
        if [ ${#raw_data[@]} -gt 0 ]; then
            while IFS= read -r sorted_line; do
                group_data+=("$sorted_line")
            done < <(printf '%s\n' "${raw_data[@]}" | sort -t'|' -k2,2f)
        fi

        declare -a final_data=()
        declare -a origin_lines=()
        for data_item in "${group_data[@]}"; do
            IFS='|' read -r gn nm rc md fr lorig <<< "$data_item"
            final_data+=("${gn};${nm};${rc};${md};${fr}")
            origin_lines+=("$lorig")
        done

        local total_items=${#final_data[@]}
        if [ "$total_items" -eq 0 ]; then
            echo -e "${RED}No repeaters found.${NC}"
            unset group_data raw_data final_data origin_lines
            read -p $'\nPress [Enter]...' < /dev/tty
            return
        fi

        local total_pages=$(( (total_items + items_per_page - 1) / items_per_page ))
        local start=$(( (page - 1) * items_per_page ))
        local end=$(( start + items_per_page ))
        [ "$end" -gt "$total_items" ] && end=$total_items

        local screen_counter=1; declare -A line_map=()
        for ((i=start; i<end; i++)); do
            IFS=';' read -r gn nm rc md fr <<< "${final_data[$i]}"
            line_map[$((screen_counter+start))]="${origin_lines[$i]}"
            printf " %-3s | %-16.16s | %-16.16s | %-10.10s | %-4.4s | %-10.10s\n" \
                "$((screen_counter+start))" "$gn" "$nm" "$rc" "$md" "$fr"
            ((screen_counter++))
        done

        separator "$GREEN2"
        echo -e "${YELLOW}Page $page of $total_pages ($total_items items)${NC}"
        unset group_data raw_data final_data origin_lines

        echo -e "${CYAN}[N] Next pg | [P] Prev pg | [B] Back Groups | [X] Main Menu${NC}"
        read -p ">> Number to detail (or indicated key): " chosen_rep < /dev/tty

        if [[ "${chosen_rep,,}" == "x" ]]; then exit_to_main=1; return; fi
        if [[ "${chosen_rep,,}" == "b" || -z "$chosen_rep" ]]; then return; fi
        if [[ "${chosen_rep,,}" == "n" ]]; then
            if [[ "$page" -lt "$total_pages" ]]; then ((page++)); fi
            unset line_map
            continue
        fi
        if [[ "${chosen_rep,,}" == "p" ]]; then
            if [[ "$page" -gt 1 ]]; then ((page--)); fi
            unset line_map
            continue
        fi

        if ! [[ "$chosen_rep" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: Enter only numbers or [N/P] to navigate pages.${NC}"; sleep 1; continue
        fi

        local real_line=${line_map[$chosen_rep]}
        if [[ -z "$real_line" ]]; then echo -e "${RED}Invalid option.${NC}"; sleep 1; continue; fi

        detail_repeater "$real_line"
        if [[ "$exit_to_main" == "1" ]]; then return; fi
    done
}

detail_repeater() {
    local target_line=$1; local current_line=1; local repeater_data=""
    while IFS= read -r line; do
        if [ "$current_line" -eq "$target_line" ]; then repeater_data="$line"; break; fi
        ((current_line++))
    done < "$CSV_FILE"

    IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset <<< "$repeater_data"

    clear
    show_header "REPEATER DETAILS"

    echo -e " ${GREEN2}1.  Group Number:${NC}                 $group_no"
    echo -e " ${GREEN2}2.  Group Name:${NC}                   $group_name"
    echo -e " ${GREEN2}3.  Repeater Name:${NC}                $name"
    echo -e " ${GREEN2}4.  Sub Name:${NC}                     $sub_name"
    echo -e " ${GREEN2}5.  Callsign:${NC}                     $rpt_call"
    echo -e " ${GREEN2}6.  Gateway Callsign:${NC}             $gw_call"
    echo -e " ${GREEN2}7.  Frequency:${NC}                    $freq"
    echo -e " ${GREEN2}8.  Duplex (DUP):${NC}                 $dup"
    echo -e " ${GREEN2}9.  Freq. Offset:${NC}                 $offset"
    echo -e " ${GREEN2}10. Operation Mode:${NC}               $mode"
    echo -e " ${GREEN2}11. TONE Type:${NC}                    $tone"
    echo -e " ${GREEN2}12. Repeater Tone:${NC}                $rpt_tone"
    echo -e " ${GREEN2}13. USE (From):${NC}                   $rpt1use"
    echo -e " ${GREEN2}14. Location:${NC}                     $position"
    echo -e " ${GREEN2}15. Latitude:${NC}                     $lat"
    echo -e " ${GREEN2}16. Longitude:${NC}                    $lon"
    echo -e " ${GREEN2}17. UTC Offset:${NC}                   $utc_offset"
    separator "$GREEN2" "═"

    echo -e "${CYAN}[E] Edit | [D] Delete | [B] Back | [X] Main Menu${NC}"
    read -p ">> Option: " detail_action < /dev/tty

    case "${detail_action,,}" in
        e) repeater_form "edit" "$target_line" "$repeater_data" ;;
        d)
            read -p "Are you sure you want to DELETE this repeater? (y/N): " conf < /dev/tty
            if [[ "${conf,,}" == "y" ]]; then
                local backup_del
                cp "$CSV_FILE" "${CSV_FILE}.backup"
                local line_content
                line_content=$(sed -n "${target_line}p" "$CSV_FILE")
                if [[ "$line_content" == "$repeater_data" ]]; then
                    local tmp_del_file
                    tmp_del_file=$(mktemp)
                    awk -v tgt="$target_line" 'NR!=tgt' "$CSV_FILE" > "$tmp_del_file" && mv "$tmp_del_file" "$CSV_FILE"
                    log_operation "DELETE" "Repeater '$name' removed from base"
                    echo -e "${GREEN2}Repeater deleted successfully!${NC}"
                else
                    echo -e "${RED}Error: The line was changed since reading. Delete aborted for safety.${NC}"
                    echo -e "${YELLOW}Backup available: ${CSV_FILE}.backup${NC}"
                fi
                sleep 2
            fi
            ;;
        b) return ;;
        x) exit_to_main=1; return ;;
        *) return ;;
    esac
}

# ==============================================================================
# OPTION 2: REPEATER INSERTION AND EDIT FORM
# ==============================================================================
repeater_form() {
    local action=$1; local target_line=${2:-}; local old_data=${3:-}
    local group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset
    unset map_groups

    clear
    if [[ "$action" == "edit" ]]; then
        IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset <<< "$old_data"
        show_header "EDITING REPEATER: $name"
    else
        show_header "ADDING NEW REPEATER"
        dup="OFF"; offset="0,000000"; mode="FM"; tone="OFF"; rpt_tone=""; rpt1use="YES"
        position="None"; lat="0,000000"; lon="0,000000"; utc_offset="-3:00"
    fi

    declare -A map_groups
    if [ -f "$CSV_FILE" ]; then
        while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
            if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_groups["$g_no"]="$g_name"; fi
        done < "$CSV_FILE"
    fi

    echo -e "\n${YELLOW}--- AVAILABLE GROUPS ---${NC}"
    if [ ${#map_groups[@]} -gt 0 ]; then
        for k in $(printf "%s\n" "${!map_groups[@]}" | sort -n); do printf " [%02d] - %s\n" "$k" "${map_groups[$k]}"; done
    else echo " No groups registered."; fi
    separator "$YELLOW"
    echo

    group_no=$(read_field "Group No (1-50)" "^([1-9]|[1-4][0-9]|50)$" "Must be between 1 and 50" "$group_no" "") || return

    if [[ -n "${map_groups[$group_no]}" ]]; then
        group_name="${map_groups[$group_no]}"
        echo -e "  ${GREEN2}>> Associated Group Name: $group_name${NC}"
    else
        group_name=$(read_field "New Group Name" "" "" "$group_name" 16) || return
    fi

    name=$(read_field "Name" "" "" "$name" 16) || return
    sub_name=$(read_field "Sub Name" "" "" "$sub_name" 8) || return

    mode=$(read_option "Mode" "$mode" "DV" "FM" "FM-N") || return
    dup=$(read_option "Dup" "$dup" "OFF" "DUP-" "DUP+") || return

    if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then offset=$(read_field "Offset (ex: 5,000000)" "^[0-9],[0-9]{6}$" "Format 0,000000" "$offset" "") || return
    else offset="0,000000"; fi

    local current_band=""
    while true; do
        freq=$(read_field "Frequency (ex: 439,975000)" "^[0-9]{3},[0-9]{6}$" "Format 000,000000" "$freq" "") || return
        local freq_int="${freq//,/}"
        if [[ 10#$freq_int -ge 144000000 && 10#$freq_int -le 148000000 ]]; then
            current_band="VHF"
            break
        elif [[ 10#$freq_int -ge 430000000 && 10#$freq_int -le 450000000 ]]; then
            current_band="UHF"
            break
        else
            echo -e "  ${RED}Error: Frequency must be between 144-148 MHz or 430-450 MHz.${NC}" >&2
        fi
    done

    while true; do
        if [[ "$dup" != "OFF" ]]; then
            if [[ "$mode" == "DV" ]]; then
                rpt_call=$(read_field "Repeater Call Sign" "^.{7}[A-Z]$" "DV requires 8 positions, last A-Z." "$rpt_call" 8) || return
            else
                rpt_call=$(read_field "Repeater Call Sign (Optional)" "" "" "$rpt_call" 8) || return
            fi
        else
            rpt_call=""
        fi

        if [[ -n "$rpt_call" ]]; then
            local conflict_res=""
            if [ -f "$CSV_FILE" ]; then
                conflict_res=$(awk -F';' -v call="$rpt_call" -v mode="$mode" -v band="$current_band" -v ln="${target_line:-0}" '
                NR!=ln && $5==call {
                    if ($10 == "DV" || mode == "DV") { print "DV"; exit }
                    f=$7; gsub(",", "", f); b="";
                    if (f >= 144000000 && f <= 148000000) b="VHF";
                    else if (f >= 430000000 && f <= 450000000) b="UHF";
                    if (b == band) { print "BAND"; exit }
                }' "$CSV_FILE")
            fi

            if [[ "$conflict_res" == "DV" ]]; then
                echo -e "  ${RED}Error: Callsign '$rpt_call' conflicts with DV rule (requires/has absolute exclusivity).${NC}" >&2
                continue
            elif [[ "$conflict_res" == "BAND" ]]; then
                echo -e "  ${RED}Error: Callsign '$rpt_call' already has an analog repeater operating on band $current_band.${NC}" >&2
                continue
            fi
        fi
        break
    done

    if [[ "$dup" != "OFF" && "$mode" == "DV" ]]; then
        local gw_def="${rpt_call:0:7}G"
        gw_call=$(read_field "Gateway Call Sign" "^.{7}G$" "Requires 8 positions, last G." "${gw_call:-$gw_def}" 8) || return
    else
        gw_call=""
    fi

    if [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
        tone=$(read_option "TONE" "$tone" "OFF" "TONE" "TSQL") || return
        if [[ "$tone" != "OFF" ]]; then
            rpt_tone=$(read_tone "Choose Repeater Tone" "${rpt_tone//Hz/}") || return
        else rpt_tone="88,5Hz"; fi
    elif [[ "$mode" == "DV" ]]; then
        tone="OFF"; rpt_tone="88,5Hz"
    fi

    rpt1use=$(read_option "RPT1USE" "$rpt1use" "YES" "NO") || return
    position=$(read_option "Position" "$position" "None" "Approximate" "Exact") || return

    if [[ "$position" != "None" ]]; then
        lat=$(read_field "Latitude (ex: -26,149167)" "^-?[0-9]{1,2},[0-9]{6}$" "Format -00,000000" "$lat" "") || return
        lon=$(read_field "Longitude (ex: -49,812167)" "^-?[0-9]{1,3},[0-9]{6}$" "Format -000,000000" "$lon" "") || return
    else lat="0,000000"; lon="0,000000"; fi

    utc_offset=$(read_field "UTC Offset (ex: -3:00)" "^([+-]?[0-9]{1,2}:[0-9]{2}|--:--)$" "Format -3:00 or --:--" "$utc_offset" "") || return

    local new_line="$group_no;$group_name;$name;$sub_name;$rpt_call;$gw_call;$freq;$dup;$offset;$mode;$tone;$rpt_tone;$rpt1use;$position;$lat;$lon;$utc_offset"

    echo
    if [[ "$action" == "edit" ]]; then
        local tmp_file
        tmp_file=$(mktemp)
        awk -F';' -v target="$target_line" -v newline="$new_line" 'NR==target {print newline; next} {print}' "$CSV_FILE" > "$tmp_file" && mv "$tmp_file" "$CSV_FILE"
        log_operation "EDIT" "Repeater '$name' updated in CSV (line $target_line)"
        echo -e "${GREEN2}Repeater updated successfully in CSV!${NC}"
    else
        if [ ! -f "$CSV_FILE" ]; then echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$CSV_FILE"; fi
        echo "$new_line" >> "$CSV_FILE"
        log_operation "ADD" "New repeater '$name' added to CSV"
        echo -e "${GREEN2}New repeater added to CSV!${NC}"
    fi
    sleep 2
}

# ==============================================================================
# OPTION 3: EDIT GROUP NAME
# ==============================================================================
edit_groups_menu() {
    clear
    show_header "EDIT GROUPS"
    if [ ! -f "$CSV_FILE" ]; then echo -e "${RED}Warning: Empty base.${NC}"; sleep 2; return; fi

    echo    "1. Rename Group"
    echo -e "2. Remove Group ${GRAY}(Move linked repeaters)${NC}"
    echo    "X. Back"
    separator "$GREEN2"
    read -p ">> Option: " sub_opt < /dev/tty

    case $sub_opt in
        1) rename_group ;;
        2) remove_group ;;
        *) return ;;
    esac
}

rename_group() {
    declare -A map_groups; local has_groups=0
    while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
        if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_groups["$g_no"]="$g_name"; has_groups=1; fi
    done < "$CSV_FILE"

    if [ $has_groups -eq 0 ]; then echo -e "${RED}No groups found.${NC}"; sleep 2; return; fi

    echo -e "\n${YELLOW}--- AVAILABLE GROUPS ---${NC}"
    for k in $(printf "%s\n" "${!map_groups[@]}" | sort -n); do printf " [%02d] - %s\n" "$k" "${map_groups[$k]}"; done

    read -p "Group number to rename (or X to cancel): " group_num < /dev/tty
    if [[ "${group_num,,}" == "x" || -z "$group_num" ]]; then return; fi
    if ! [[ "$group_num" =~ ^[0-9]+$ ]]; then echo -e "${RED}Error: Enter only numbers.${NC}"; sleep 2; return; fi
    group_num=$((10#$group_num))

    if [[ -z "${map_groups[$group_num]}" ]]; then echo -e "${RED}Invalid group.${NC}"; sleep 2; return; fi

    local current_name="${map_groups[$group_num]}"
    echo -e "\nCurrent name of Group $group_num: ${YELLOW}$current_name${NC}"

    local new_name
    new_name=$(read_field "New Group Name" "" "" "$current_name" 16) || return

    if [[ "$new_name" == "$current_name" ]]; then echo -e "\n${YELLOW}Cancelled.${NC}"; sleep 2; return; fi

    local tmp_file
    tmp_file=$(mktemp)
    awk -F';' -v tgt="$group_num" -v nname="$new_name" 'BEGIN {OFS=";"} NR==1 {print; next} $1==tgt {$2=nname; print; next} {print}' "$CSV_FILE" > "$tmp_file" && mv "$tmp_file" "$CSV_FILE"
    log_operation "RENAME_GROUP" "Group $group_num renamed from '$current_name' to '$new_name'"
    echo -e "\n${GREEN2}Name updated in all linked repeaters!${NC}"
    sleep 2
}

remove_group() {
    declare -A map_groups
    while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
        if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_groups["$g_no"]="$g_name"; fi
    done < "$CSV_FILE"

    echo -e "\n${YELLOW}--- AVAILABLE GROUPS ---${NC}"
    for k in $(printf "%s\n" "${!map_groups[@]}" | sort -n); do printf " [%02d] - %s\n" "$k" "${map_groups[$k]}"; done

    read -p "Group number to REMOVE (or X): " group_num < /dev/tty
    if [[ "${group_num,,}" == "x" || -z "$group_num" ]]; then return; fi
    if ! [[ "$group_num" =~ ^[0-9]+$ ]]; then echo -e "${RED}Error: Enter only numbers.${NC}"; sleep 2; return; fi
    group_num=$((10#$group_num))

    if [[ -z "${map_groups[$group_num]}" ]]; then echo -e "${RED}Invalid group.${NC}"; sleep 2; return; fi

    echo -e "\n${RED}What do you want to do with the repeaters in group ${map_groups[$group_num]}?${NC}"
    echo "1. Move all to another existing group"
    echo "2. Delete all repeaters in this group"
    echo "X. Cancel"
    read -p ">> Option: " action_group < /dev/tty

    if [[ "$action_group" == "2" ]]; then
        read -p "Are you absolutely sure you want to DELETE all repeaters in group ${map_groups[$group_num]}? (y/N): " conf_del < /dev/tty
        if [[ "${conf_del,,}" != "y" ]]; then
            echo -e "${CYAN}Operation cancelled. Group kept.${NC}"
            sleep 2; return
        fi
        cp "$CSV_FILE" "${CSV_FILE}.backup"
        local tmp_del
        tmp_del=$(mktemp)
        awk -F';' -v g="$group_num" 'NR==1 || $1 != g' "$CSV_FILE" > "$tmp_del" && mv "$tmp_del" "$CSV_FILE"
        log_operation "DELETE_GROUP" "Group $group_num and its repeaters removed"
        echo -e "${GREEN2}Group and respective repeaters removed successfully!${NC}"
    elif [[ "$action_group" == "1" ]]; then
        read -p "To which group number do you want to move? (1-50): " target_group < /dev/tty
        if ! [[ "$target_group" =~ ^([1-9]|[1-4][0-9]|50)$ ]]; then echo -e "${RED}Target group invalid.${NC}"; sleep 2; return; fi

        local target_name
        target_name=$(awk -F';' -v g="$target_group" '$1==g {print $2; exit}' "$CSV_FILE")
        if [[ -z "$target_name" ]]; then
            target_name=$(read_field "New Target Group Name" "" "" "" 16) || return
        fi
        cp "$CSV_FILE" "${CSV_FILE}.backup"
        local tmp_mv
        tmp_mv=$(mktemp)
        awk -F';' -v OFS=';' -v src="$group_num" -v dst="$target_group" -v dname="$target_name" \
            'NR==1 {print; next} $1==src {$1=dst; $2=dname} {print}' "$CSV_FILE" > "$tmp_mv" && mv "$tmp_mv" "$CSV_FILE"
        log_operation "MOVE_GROUP" "Records from group $group_num moved to group $target_group"
        echo -e "${GREEN2}Records moved to group $target_group successfully!${NC}"
    fi
    sleep 2
}

# ==============================================================================
# OPERATION LOG
# ==============================================================================
LOG_FILE="./dr_manager.log"

log_operation() {
    local operation="$1"; local detail="${2:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $operation: $detail" >> "$LOG_FILE"
}

clean_old_backups() {
    local retention_days="${1:-7}"
    local found=0
    for backup in "${CSV_FILE}".backup*; do
        [ -f "$backup" ] || continue
        local modified
        modified=$(find "$backup" -mtime +"$retention_days" 2>/dev/null)
        if [[ -n "$modified" ]]; then
            rm -f "$backup"
            ((found++))
        fi
    done
    [[ "$found" -gt 0 ]] && log_operation "CLEANUP" "$found old backup(s) removed"
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================
if ! acquire_lock; then exit 1; fi

log_operation "START" "System started with base: $CSV_FILE"

clean_old_backups 7

while true; do
    check_csv_integrity
    show_menu
    case $option in
        1) list_repeaters ;;
        2) repeater_form "add" ;;
        3) edit_groups_menu ;;
        4) general_query ;;
        5) manage_base_menu ;;
        x|X) log_operation "END" "System closed by user"; echo -e "\nClosing system. 73!\n"; exit 0 ;;
        *) echo -e "\n${RED}Invalid option! Try again.${NC}"; sleep 1 ;;
    esac
done