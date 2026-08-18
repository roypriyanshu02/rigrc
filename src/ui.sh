# shellcheck shell=bash
# =============================================================================
#  UI COMPONENT SYSTEM (ANSI Themes, Widgets, Spinners & Summary)
# =============================================================================

# ---------------------------------------------------------------------------
# Colors & Theme Foundation (Tier 0)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m' ITALIC=$'\033[3m'
    CLR_PRIMARY=$'\033[38;5;39m'   # Sky Blue / Electric Cyan
    CLR_ACCENT=$'\033[38;5;213m'   # Soft Magenta
    CLR_SUCCESS=$'\033[38;5;82m'   # Bright Emerald Green
    CLR_WARN=$'\033[38;5;214m'      # Warm Amber Yellow
    CLR_ERROR=$'\033[38;5;196m'     # Vivid Crimson Red
    CLR_MUTED=$'\033[38;5;244m'     # Medium Slate Gray
    CLR_TEXT=$'\033[38;5;255m'      # High-contrast White
    CLR_CARD=$'\033[48;5;236m'      # Dark background card
    SYM_OK="✓" SYM_FAIL="✗" SYM_WARN="!" SYM_INFO="i" SYM_Q="?" SYM_DOT="●" SYM_CIRCLE="○" SYM_BLOCKED="⊘" SYM_ARROW="↳"
else
    RESET='' BOLD='' DIM='' ITALIC=''
    CLR_PRIMARY='' CLR_ACCENT='' CLR_SUCCESS='' CLR_WARN='' CLR_ERROR='' CLR_MUTED='' CLR_TEXT='' CLR_CARD=''
    SYM_OK="[OK]" SYM_FAIL="[ERR]" SYM_WARN="[!]" SYM_INFO="[i]" SYM_Q="[?]" SYM_DOT="*" SYM_CIRCLE="o" SYM_BLOCKED="[-]" SYM_ARROW="->"
fi

# Standardized indentation constants (2-space increments)
INDENT_1="  "
INDENT_2="    "
INDENT_3="      "

# ---------------------------------------------------------------------------
# UI Logging Primitives
# ---------------------------------------------------------------------------
log_info()    { local ind="${LOG_INDENT:-  }"; printf '%s%s %s\n' "$ind" "${CLR_MUTED}${SYM_INFO}${RESET}"   "$1" >&2; }
log_success() { local ind="${LOG_INDENT:-  }"; printf '%s%s %s\n' "$ind" "${CLR_SUCCESS}${SYM_OK}${RESET}"    "$1" >&2; }
log_warn()    { local ind="${LOG_INDENT:-  }"; printf '%s%s %s\n' "$ind" "${CLR_WARN}${SYM_WARN}${RESET}"     "$1" >&2; }
log_error()   { local ind="${LOG_INDENT:-  }"; printf '%s%s %s\n' "$ind" "${CLR_ERROR}${BOLD}${SYM_FAIL}${RESET}" "$1" >&2; }
log_action()  { local ind="${LOG_INDENT:-  }"; printf '%s%s\n' "$ind" "$1" >&2; }

_ui_header() {
    local title="$1"
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        printf '\n%s\n\n' "${BOLD}${title}${RESET}" >&2
    else
        printf '\n%s\n\n' "$title" >&2
    fi
}

_ui_bell() {
    [[ "${NON_INTERACTIVE:-false}" == true || "${DOTFILES_NO_BELL:-false}" == true ]] && return 0
    local bell_file="${TMPDIR:-/tmp}/.dotfiles_bell_$$"
    local now
    now="$(date +%s 2>/dev/null || printf '%s' "${SECONDS:-0}")"
    local last=0
    if [[ -f "$bell_file" ]]; then
        last="$(<"$bell_file")" 2>/dev/null || last=0
    fi
    local min_interval=45
    if [[ $(( now - last )) -ge $min_interval ]]; then
        printf '%s' "$now" > "$bell_file" 2>/dev/null || true
        if [[ -t 2 || -c /dev/tty ]]; then
            printf '\a' >&2
        fi
    fi
}

_ui_input() {
    local prompt="$1" default_val="${2:-}"
    local ind="${LOG_INDENT:-  }"
    if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
        printf '%s' "$default_val"
        return 0
    fi
    _ui_bell
    local val="" hint=""
    [[ -n "$default_val" ]] && hint=" ${CLR_MUTED}[${default_val}]${RESET}"
    printf '%s%s %s%s: ' "$ind" "${CLR_PRIMARY}${SYM_Q}${RESET}" "${BOLD}${prompt}${RESET}" "$hint" >&2
    if [[ ! -t 0 ]]; then
        read -r val 2>/dev/null || true
    elif [[ -c /dev/tty ]]; then
        read -r val < /dev/tty 2>/dev/null || read -r val 2>/dev/null || true
    else
        read -r val 2>/dev/null || true
    fi
    local res="${val:-$default_val}"
    if [[ -t 2 && -c /dev/tty ]]; then
        local display_res
        if [[ -z "$res" ]]; then
            display_res="${CLR_MUTED}↳ skipped${RESET}"
        else
            display_res="${CLR_TEXT}↳ ${res}${RESET}"
        fi
        printf '\033[1A\033[2K%s%-16s %s\n' "$ind" "${prompt}" "$display_res" >&2
    fi
    printf '%s' "$res"
}

_ui_password() {
    local prompt="$1"
    local ind="${LOG_INDENT:-  }"
    if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
        printf ''
        return 0
    fi
    _ui_bell
    local val=""
    printf '%s%s %s: ' "$ind" "${CLR_WARN}${SYM_Q}${RESET}" "${BOLD}${prompt}${RESET}" >&2
    if [[ ! -t 0 ]]; then
        read -r -s val 2>/dev/null || true
    elif [[ -c /dev/tty ]]; then
        read -r -s val < /dev/tty 2>/dev/null || read -r -s val 2>/dev/null || true
    else
        read -r -s val 2>/dev/null || true
    fi
    printf '\n' >&2
    if [[ -t 2 && -c /dev/tty ]]; then
        printf '\033[1A\033[2K%s%-16s %s\n' "$ind" "${prompt}" "${CLR_MUTED}••••••••${RESET}" >&2
    fi
    printf '%s' "$val"
}

_ui_select() {
    local prompt="$1"
    shift
    local opts=("$@")
    if [[ "${NON_INTERACTIVE:-false}" == true || ${#opts[@]} -eq 0 ]]; then
        printf '%s' "${opts[0]:-}"
        return 0
    fi
    _ui_bell

    if [[ -t 0 && -t 2 && -c /dev/tty ]]; then
        local selected=0
        local total=${#opts[@]}
        local key=""
        printf '\033[?25l' >&2 # Hide cursor

        _render_menu() {
            printf '  %s %s\n' "${CLR_PRIMARY}${SYM_Q}${RESET}" "${BOLD}${prompt}${RESET}" >&2
            local i
            for i in "${!opts[@]}"; do
                if [[ $i -eq $selected ]]; then
                    printf '    %s %s\n' "${CLR_PRIMARY}●${RESET}" "${BOLD}${CLR_PRIMARY}${opts[$i]}${RESET}" >&2
                else
                    printf '    %s %s\n' "${CLR_MUTED}○${RESET}" "${CLR_MUTED}${opts[$i]}${RESET}" >&2
                fi
            done
        }

        _render_menu

        while true; do
            IFS= read -rsn1 key < /dev/tty 2>/dev/null || break
            if [[ "$key" == $'\x1b' ]]; then
                read -rsn2 -t 0.1 rest < /dev/tty 2>/dev/null || rest=""
                key+="$rest"
            fi

            case "$key" in
                $'\x1b[A'|k|K)
                    selected=$(( (selected - 1 + total) % total ))
                    ;;
                $'\x1b[B'|j|J)
                    selected=$(( (selected + 1) % total ))
                    ;;
                "")
                    break
                    ;;
                [1-9])
                    local num=$((key - 1))
                    if [[ $num -ge 0 && $num -lt $total ]]; then
                        selected=$num
                        break
                    fi
                    ;;
                q|Q)
                    break
                    ;;
            esac

            printf '\033[%dA' "$((total + 1))" >&2
            _render_menu
        done

        printf '\033[?25h' >&2 # Restore cursor
        printf '\033[%dA\033[J' "$((total + 1))" >&2
        printf '  %s %s: %s\n' "${CLR_SUCCESS}${SYM_OK}${RESET}" "${prompt}" "${CLR_PRIMARY}${BOLD}${opts[$selected]}${RESET}" >&2
        printf '%s' "${opts[$selected]}"
        return 0
    fi

    printf '  %s %s\n' "${CLR_PRIMARY}${BOLD}${prompt}${RESET}" >&2
    local i
    for i in "${!opts[@]}"; do
        printf '    %s%2d)%s %s\n' "${CLR_ACCENT}" $((i + 1)) "${RESET}" "${opts[$i]}" >&2
    done
    local choice=""
    printf '  Select [1-%d]: ' "${#opts[@]}" >&2
    if [[ ! -t 0 ]]; then
        read -r choice 2>/dev/null || true
    elif [[ -c /dev/tty ]]; then
        read -r choice < /dev/tty 2>/dev/null || read -r choice 2>/dev/null || true
    else
        read -r choice 2>/dev/null || true
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$((choice - 1))
        if [[ "$idx" -ge 0 && "$idx" -lt "${#opts[@]}" ]]; then
            printf '%s' "${opts[$idx]}"
            return 0
        fi
    fi
    printf '%s' "${opts[0]}"
}

_format_env_name() {
    local raw="$1"
    raw="${raw#!}"
    raw="${raw#env:}"
    raw="${raw#arch:}"
    case "${raw,,}" in
        wsl) echo "WSL" ;;
        darwin|macos) echo "macOS" ;;
        linux) echo "Linux" ;;
        freebsd|bsd) echo "BSD" ;;
        windows) echo "Windows" ;;
        docker|container) echo "containers" ;;
        *) echo "$raw" ;;
    esac
}

_ui_multiselect() {
    local prompt="$1"
    local -n _ms_items="$2"
    local -n _ms_labels="$3"
    local -n _ms_descs="$4"
    local -n _ms_states="$5"
    local -n _ms_locks="$6"

    local total=${#_ms_items[@]}
    if [[ $total -eq 0 ]]; then
        return 0
    fi

    if [[ "${NON_INTERACTIVE:-false}" == true || ! -t 0 || ! -t 2 || ! -c /dev/tty ]]; then
        local out_items=()
        local i
        for i in "${!_ms_items[@]}"; do
            local lock="${_ms_locks[$i]:-}"
            local st="${_ms_states[$i]:-0}"
            if [[ "$lock" == "required" || "$st" -eq 1 ]]; then
                [[ "$lock" != "unsupported:"* && "$lock" != "disabled"* ]] && out_items+=("${_ms_items[$i]}")
            fi
        done
        printf '%s ' "${out_items[@]}"
        return 0
    fi

    _ui_bell
    local selected=0
    local key=""
    printf '\033[?25l' >&2

    local max_name_len=0
    local max_tag_len=0
    local _idx
    for _idx in "${!_ms_items[@]}"; do
        local _item="${_ms_items[$_idx]}"
        local _lbl="${_ms_labels[$_idx]:-$_item}"
        local _lock="${_ms_locks[$_idx]:-}"
        [[ ${#_lbl} -gt $max_name_len ]] && max_name_len=${#_lbl}

        local _rtag=""
        if [[ "$_lock" == "required" ]]; then
            _rtag="required"
        elif [[ "$_lock" == "installed:"* || "$_lock" == "installed" ]]; then
            _rtag="installed"
        elif [[ "$_lock" == "alt:"*" installed" ]]; then
            local _at="${_lock#alt:}"
            _at="${_at% installed}"
            _rtag="alternative to ${_at} (installed)"
        elif [[ "$_lock" == "alt:"* ]]; then
            local _at="${_lock#alt:}"
            _rtag="alternative to ${_at}"
        elif [[ "$_lock" == "unsupported:"* ]]; then
            local _r="${_lock#unsupported:}"
            local _env_label="$(_format_env_name "$_r")"
            _rtag="unavailable on ${_env_label}"
        elif [[ "$_lock" == "disabled:missing "* ]]; then
            local _r="${_lock#disabled:missing }"
            _rtag="requires ${_r}"
        elif [[ "$_lock" == "disabled"* ]]; then
            _rtag="disabled in config"
        fi
        [[ ${#_rtag} -gt $max_tag_len ]] && max_tag_len=${#_rtag}
    done
    local name_col_width=$(( max_name_len + 2 ))

    _render_ms_menu() {
        local cols=80
        if command -v tput >/dev/null 2>&1; then
            cols="$(tput cols 2>/dev/null || echo 80)"
        fi
        local ind="${LOG_INDENT:-  }"

        local display_prompt="$prompt"
        if [[ "$prompt" =~ ^Packages[[:space:]]+in[[:space:]]+\[(.*)\]$ ]]; then
            display_prompt="Select packages · ${BASH_REMATCH[1]}"
        elif [[ "$prompt" == "Select package groups" ]]; then
            display_prompt="Select package groups"
        fi

        printf '%s%s\n' "$ind" "${BOLD}${display_prompt}${RESET}" >&2
        printf '%s%s\n\n' "$ind" "${CLR_MUTED}Space toggle · A all · Enter continue${RESET}" >&2

        local avail_space=$(( cols - ${#ind} - 6 - name_col_width ))
        local desc_col_width
        if [[ $max_tag_len -gt 0 ]]; then
            desc_col_width=$(( avail_space - max_tag_len - 2 ))
        else
            desc_col_width=$(( avail_space - 2 ))
        fi
        [[ $desc_col_width -lt 16 ]] && desc_col_width=16

        local i
        for i in "${!_ms_items[@]}"; do
            local item="${_ms_items[$i]}"
            local lbl="${_ms_labels[$i]:-$item}"
            local desc="${_ms_descs[$i]:-}"
            local st="${_ms_states[$i]:-0}"
            local lock="${_ms_locks[$i]:-}"
            local radio_icon=""

            if [[ "$lock" == "disabled"* || "$lock" == "unsupported:"* ]]; then
                radio_icon="${CLR_MUTED}${SYM_BLOCKED}${RESET}"
            elif [[ "$lock" == "installed:"* || "$lock" == "installed" ]]; then
                radio_icon="${CLR_SUCCESS}${SYM_OK}${RESET}"
            elif [[ "$lock" == "required" ]]; then
                radio_icon="${CLR_PRIMARY}${SYM_DOT}${RESET}"
            elif [[ "$st" -eq 1 ]]; then
                radio_icon="${CLR_PRIMARY}${SYM_DOT}${RESET}"
            else
                radio_icon="${CLR_MUTED}${SYM_CIRCLE}${RESET}"
            fi

            local raw_tag="" tag_fmt=""
            if [[ "$lock" == "required" ]]; then
                raw_tag="required"
                tag_fmt="${CLR_ACCENT}${raw_tag}${RESET}"
            elif [[ "$lock" == "installed:"* || "$lock" == "installed" ]]; then
                raw_tag="installed"
                tag_fmt="${CLR_MUTED}${raw_tag}${RESET}"
            elif [[ "$lock" == "alt:"*" installed" ]]; then
                local alt_target="${lock#alt:}"
                alt_target="${alt_target% installed}"
                raw_tag="alternative to ${alt_target} (installed)"
                tag_fmt="${CLR_MUTED}${raw_tag}${RESET}"
            elif [[ "$lock" == "alt:"* ]]; then
                local alt_target="${lock#alt:}"
                raw_tag="alternative to ${alt_target}"
                tag_fmt="${CLR_MUTED}${raw_tag}${RESET}"
            elif [[ "$lock" == "unsupported:"* ]]; then
                local reason="${lock#unsupported:}"
                local env_label="$(_format_env_name "$reason")"
                raw_tag="unavailable on ${env_label}"
                tag_fmt="${CLR_WARN}${raw_tag}${RESET}"
            elif [[ "$lock" == "disabled:missing "* ]]; then
                local req_dep="${lock#disabled:missing }"
                raw_tag="requires ${req_dep}"
                tag_fmt="${CLR_MUTED}${raw_tag}${RESET}"
            elif [[ "$lock" == "disabled"* ]]; then
                raw_tag="disabled in config"
                tag_fmt="${CLR_MUTED}${raw_tag}${RESET}"
            fi

            local pad_len=$(( name_col_width - ${#lbl} ))
            [[ $pad_len -lt 1 ]] && pad_len=1
            local pad_spaces
            printf -v pad_spaces '%*s' "$pad_len" ""

            local cur_desc="$desc"
            if [[ -n "$cur_desc" ]]; then
                if [[ ${#cur_desc} -gt $desc_col_width ]]; then
                    cur_desc="${cur_desc:0:$((desc_col_width - 1))}…"
                fi
            fi

            local desc_spaces=""
            if [[ $max_tag_len -gt 0 ]]; then
                local desc_pad=$(( desc_col_width - ${#cur_desc} ))
                [[ $desc_pad -lt 1 ]] && desc_pad=1
                printf -v desc_spaces '%*s' "$desc_pad" ""
            fi

            if [[ $i -eq $selected ]]; then
                if [[ "$lock" == "disabled"* || "$lock" == "unsupported:"* ]]; then
                    local desc_fmt=""
                    [[ -n "$cur_desc" ]] && desc_fmt="${CLR_MUTED}${cur_desc}${RESET}"
                    printf '%s  %s  %s%s%s%s%s\n' "$ind" "$radio_icon" "${BOLD}${CLR_MUTED}${lbl}${RESET}" "$pad_spaces" "$desc_fmt" "$desc_spaces" "$tag_fmt" >&2
                else
                    local desc_fmt=""
                    [[ -n "$cur_desc" ]] && desc_fmt="${CLR_TEXT}${cur_desc}${RESET}"
                    printf '%s  %s  %s%s%s%s%s\n' "$ind" "$radio_icon" "${BOLD}${CLR_PRIMARY}${lbl}${RESET}" "$pad_spaces" "$desc_fmt" "$desc_spaces" "$tag_fmt" >&2
                fi
            else
                local desc_fmt=""
                [[ -n "$cur_desc" ]] && desc_fmt="${CLR_MUTED}${cur_desc}${RESET}"
                printf '%s  %s  %s%s%s%s%s\n' "$ind" "$radio_icon" "${CLR_MUTED}${lbl}${RESET}" "$pad_spaces" "$desc_fmt" "$desc_spaces" "$tag_fmt" >&2
            fi
        done
    }

    # WINCH signal trap for window resizing
    _on_winch() {
        printf '\033[%dA\033[J' "$((total + 3))" >&2
        _render_ms_menu
    }
    trap '_on_winch' WINCH

    _render_ms_menu

    while true; do
        IFS= read -rsn1 key < /dev/tty 2>/dev/null || break
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 rest < /dev/tty 2>/dev/null || rest=""
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A'|k|K)
                selected=$(( (selected - 1 + total) % total ))
                ;;
            $'\x1b[B'|j|J)
                selected=$(( (selected + 1) % total ))
                ;;
            " "|x|X)
                local cur_lock="${_ms_locks[$selected]:-}"
                if [[ "$cur_lock" != "required" && "$cur_lock" != "installed:"* && "$cur_lock" != "unsupported:"* && "$cur_lock" != "disabled"* ]]; then
                    if [[ "${_ms_states[$selected]:-0}" -eq 1 ]]; then
                        _ms_states[$selected]=0
                    else
                        _ms_states[$selected]=1
                    fi
                fi
                ;;
            a|A)
                local all_toggleable_checked=1
                local j
                for j in "${!_ms_items[@]}"; do
                    local j_lock="${_ms_locks[$j]:-}"
                    if [[ "$j_lock" != "required" && "$j_lock" != "installed:"* && "$j_lock" != "unsupported:"* && "$j_lock" != "disabled"* ]]; then
                        if [[ "${_ms_states[$j]:-0}" -ne 1 ]]; then
                            all_toggleable_checked=0
                            break
                        fi
                    fi
                done
                for j in "${!_ms_items[@]}"; do
                    local j_lock="${_ms_locks[$j]:-}"
                    if [[ "$j_lock" != "required" && "$j_lock" != "installed:"* && "$j_lock" != "unsupported:"* && "$j_lock" != "disabled"* ]]; then
                        if [[ $all_toggleable_checked -eq 1 ]]; then
                            _ms_states[$j]=0
                        else
                            _ms_states[$j]=1
                        fi
                    fi
                done
                ;;
            "")
                break
                ;;
        esac

        printf '\033[%dA' "$((total + 3))" >&2
        _render_ms_menu
    done

    trap - WINCH

    printf '\033[?25h' >&2
    printf '\033[%dA\033[J' "$((total + 3))" >&2

    local chosen_ids=()
    local chosen_lbls=()
    local k
    for k in "${!_ms_items[@]}"; do
        local lk="${_ms_locks[$k]:-}"
        local s="${_ms_states[$k]:-0}"
        if [[ "$lk" == "required" || "$s" -eq 1 ]]; then
            if [[ "$lk" != "unsupported:"* && "$lk" != "disabled:"* ]]; then
                chosen_ids+=("${_ms_items[$k]}")
                chosen_lbls+=("${_ms_labels[$k]:-${_ms_items[$k]}}")
            fi
        fi
    done

    local ind="${LOG_INDENT:-  }"
    local display_prompt="$prompt"
    if [[ "$prompt" =~ ^Packages[[:space:]]+in[[:space:]]+\[(.*)\]$ ]]; then
        display_prompt="Packages · ${BASH_REMATCH[1]}"
    fi
    printf '%s%s %s %s\n' "$ind" "${CLR_SUCCESS}${SYM_OK}${RESET}" "${display_prompt}" "${CLR_MUTED}(${#chosen_ids[@]} selected)${RESET}" >&2

    printf '%s ' "${chosen_ids[@]}"
}

_set_term_title() {
    [[ -t 2 && -z "${NO_COLOR:-}" ]] && printf '\033]0;%s\007' "$1" >&2 || true
}

_ui_phase() {
    local num="$1" total="$2" title="$3"
    _set_term_title "Dotfiles: ${title}"
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        printf '\n%s\n' "${CLR_TEXT}${BOLD}${title}${RESET}" >&2
    else
        printf '\n%s\n' "$title" >&2
    fi
}

_get_remediation_hint() {
    local err_text="$1"
    if [[ "$err_text" == *"lock"* || "$err_text" == *"Could not get lock"* ]]; then
        printf 'Package manager lock busy. Wait for background update or clear stale lock.'
    elif [[ "$err_text" == *"404"* || "$err_text" == *"Not Found"* ]]; then
        printf 'Asset not found on release server. Check release URL and target architecture.'
    elif [[ "$err_text" == *"403"* || "$err_text" == *"rate limit"* || "$err_text" == *"Rate limit"* ]]; then
        printf 'GitHub API rate limit exceeded. Set GITHUB_TOKEN to proceed.'
    elif [[ "$err_text" == *"Permission denied"* || "$err_text" == *"permission denied"* ]]; then
        printf 'Permission denied. Run with sudo or fix target path permissions.'
    elif [[ "$err_text" == *"checksum mismatch"* || "$err_text" == *"Checksum mismatch"* ]]; then
        printf 'Checksum mismatch. Downloaded archive is corrupted or modified.'
    elif [[ "$err_text" == *"No space left"* || "$err_text" == *"no space left"* ]]; then
        printf 'Disk space exhausted. Free up disk space on target filesystem.'
    elif [[ "$err_text" == *"timed out"* || "$err_text" == *"Timed out"* || "$err_text" == *"Operation timed out"* ]]; then
        printf 'Operation timed out. Check network connection or increase INSTALL_TIMEOUT.'
    elif [[ "$err_text" == *"SSL"* || "$err_text" == *"certificate"* || "$err_text" == *"TLS"* ]]; then
        printf 'SSL/TLS certificate error. Verify system time and CA certificates.'
    elif [[ "$err_text" == *"Connection refused"* || "$err_text" == *"Couldn't connect to server"* ]]; then
        printf 'Connection refused. Check internet connectivity and proxy settings.'
    fi
}

_extract_last_error() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return 0
    local line=""

    # 1. Prefer decisive error lines matching high-signal diagnostic patterns
    line="$(grep -E -i '(error:|fatal:|fail(ed|ure)?[: ]|denied|timed out|404 not found|rate limit|refused|cannot |unable to )' "$log_file" 2>/dev/null | tail -n 1 || true)"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # 2. Fall back to last non-empty line
    if [[ -z "$line" ]]; then
        line="$(grep -v '^[[:space:]]*$' "$log_file" 2>/dev/null | tail -n 1 || true)"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
    fi

    if [[ ${#line} -gt 120 ]]; then
        line="${line:0:117}..."
    fi
    printf '%s' "$line"
}

_run_with_spinner() {
    local label="$1"
    shift
    local ind="${SPINNER_INDENT:-  }"
    _LAST_CMD_ERROR=""

    if [[ "${VERBOSE:-false}" == true || ! -t 2 ]]; then
        log_info "$label"
        local rc=0
        local cmd_log
        cmd_log="$(mktemp "${TMPDIR:-/tmp}/dotfiles_cmd_XXXXXX.log" 2>/dev/null || mktemp)"
        _TRACKED_TMP_FILES+=("$cmd_log")
        if [[ "${VERBOSE:-false}" == true ]]; then
            "$@" 2>&1 | tee "$cmd_log" || rc=${PIPESTATUS[0]}
        else
            "$@" > "$cmd_log" 2>&1 || rc=$?
        fi
        if [[ $rc -ne 0 ]]; then
            _LAST_CMD_ERROR="$(_extract_last_error "$cmd_log")"
            if [[ -n "$_LAST_CMD_ERROR" && "${VERBOSE:-false}" != true ]]; then
                printf '%s  %s %s\n' "$ind" "${CLR_ERROR}↳${RESET}" "${CLR_MUTED}${_LAST_CMD_ERROR}${RESET}" >&2
                local rhint
                rhint="$(_get_remediation_hint "$_LAST_CMD_ERROR")"
                [[ -n "$rhint" ]] && printf '%s    %s %s\n' "$ind" "${CLR_WARN}hint:${RESET}" "${CLR_MUTED}${rhint}${RESET}" >&2
            fi
        fi
        rm -f "$cmd_log" 2>/dev/null || true
        return $rc
    fi

    printf '\033[?25l' >&2
    local spin_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local num_frames=${#spin_chars[@]}
    local i=0
    local pid

    local cmd_log
    cmd_log="$(mktemp "${TMPDIR:-/tmp}/dotfiles_cmd_XXXXXX.log" 2>/dev/null || mktemp)"
    _TRACKED_TMP_FILES+=("$cmd_log")

    "$@" > "$cmd_log" 2>&1 &
    pid=$!
    _TRACKED_CHILD_PIDS+=("$pid")

    local start_time=$SECONDS
    local cols=80
    if command -v tput >/dev/null 2>&1; then
        cols="$(tput cols 2>/dev/null || echo 80)"
    fi
    local max_lbl=$(( cols - 18 ))
    [[ $max_lbl -lt 20 ]] && max_lbl=20

    local base_label="$label"
    local meta_suffix=""
    local meta_regex='^(.*)[[:space:]]+\(([^)]+)\)$'
    if [[ "$label" =~ $meta_regex ]]; then
        base_label="${BASH_REMATCH[1]}"
        meta_suffix="${BASH_REMATCH[2]}"
    fi

    local display_base="$base_label"
    if [[ ${#display_base} -gt $max_lbl ]]; then
        display_base="${display_base:0:$((max_lbl - 3))}..."
    fi

    local last_elapsed=-1
    local elapsed_str=""
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start_time ))
        if [[ $elapsed -ne $last_elapsed ]]; then
            last_elapsed=$elapsed
            if [[ -n "$meta_suffix" ]]; then
                elapsed_str=" ${CLR_MUTED}(${meta_suffix}, ${elapsed}s)${RESET}"
            else
                elapsed_str=" ${CLR_MUTED}(${elapsed}s)${RESET}"
            fi
        fi
        local frame="${spin_chars[i % num_frames]}"
        printf '\r\033[2K%s%s %s%s' "$ind" "${CLR_PRIMARY}${frame}${RESET}" "${CLR_TEXT}${display_base}${RESET}" "$elapsed_str" >&2
        i=$((i + 1))
        sleep 0.08 2>/dev/null || sleep 1
    done

    local rc=0
    wait "$pid" || rc=$?

    # Remove pid from _TRACKED_CHILD_PIDS
    local new_cpids=() cp
    for cp in "${_TRACKED_CHILD_PIDS[@]}"; do
        [[ "$cp" != "$pid" ]] && new_cpids+=("$cp")
    done
    _TRACKED_CHILD_PIDS=("${new_cpids[@]}")

    local total_time=$(( SECONDS - start_time ))
    printf '\033[?25h' >&2

    local final_meta=""
    if [[ -n "$meta_suffix" ]]; then
        final_meta="${CLR_MUTED}(${meta_suffix}, ${total_time}s)${RESET}"
    else
        final_meta="${CLR_MUTED}(${total_time}s)${RESET}"
    fi

    if [[ $rc -eq 0 ]]; then
        printf '\r\033[2K%s%s %s %s\n' "$ind" "${CLR_SUCCESS}${SYM_OK}${RESET}" "${display_base}" "${final_meta}" >&2
    else
        printf '\r\033[2K%s%s %s %s\n' "$ind" "${CLR_ERROR}${BOLD}${SYM_FAIL}${RESET}" "${CLR_ERROR}${display_base} (failed)${RESET}" "${final_meta}" >&2
        _LAST_CMD_ERROR="$(_extract_last_error "$cmd_log")"
        if [[ -n "$_LAST_CMD_ERROR" ]]; then
            printf '%s  %s %s\n' "$ind" "${CLR_ERROR}↳${RESET}" "${CLR_MUTED}${_LAST_CMD_ERROR}${RESET}" >&2
            local rhint
            rhint="$(_get_remediation_hint "$_LAST_CMD_ERROR")"
            [[ -n "$rhint" ]] && printf '%s    %s %s\n' "$ind" "${CLR_WARN}hint:${RESET}" "${CLR_MUTED}${rhint}${RESET}" >&2
        fi
    fi
    rm -f "$cmd_log" 2>/dev/null || true
    return $rc
}

# Render final summary report card
_ui_render_summary() {
    local total_time="${1:-0}"
    local installed_count="${2:-0}"
    local backup_count="${3:-0}"
    local failed_count="${#_FAILED_PACKAGES[@]}"
    local warning_count="${#_WARNING_MESSAGES[@]}"

    local time_fmt=""
    if [[ $total_time -ge 60 ]]; then
        local mins=$(( total_time / 60 ))
        local secs=$(( total_time % 60 ))
        printf -v time_fmt '%dm %02ds' "$mins" "$secs"
    else
        time_fmt="${total_time}s"
    fi

    _set_term_title "Dotfiles: Complete"
    echo "" >&2
    if [[ $failed_count -eq 0 && $warning_count -eq 0 ]]; then
        printf '%s\n\n' "${BOLD}${CLR_SUCCESS}Setup complete${RESET}" >&2
    elif [[ $failed_count -eq 0 ]]; then
        printf '%s\n\n' "${BOLD}Setup complete with ${warning_count} warning(s)${RESET}" >&2
    else
        printf '%s\n\n' "${BOLD}${CLR_ERROR}Setup completed with ${failed_count} error(s)${RESET}" >&2
    fi

    printf '  %-22s %s\n' "Installed packages:" "${installed_count}" >&2
    if [[ $backup_count -gt 0 ]]; then
        printf '  %-22s %s\n' "Backed up files:" "${backup_count}" >&2
    fi
    printf '  %-22s %s\n' "Time elapsed:" "${time_fmt}" >&2

    if [[ -n "${BACKUP_DIR:-}" && $backup_count -gt 0 ]]; then
        echo "" >&2
        printf '%s\n' "${BOLD}Backup${RESET}" >&2
        printf '  %s\n' "${CLR_MUTED}${BACKUP_DIR}${RESET}" >&2
    fi

    if [[ $warning_count -gt 0 ]]; then
        echo "" >&2
        printf '%s\n' "${BOLD}${CLR_WARN}Warnings${RESET}" >&2
        local w
        for w in "${_WARNING_MESSAGES[@]}"; do
            printf '  %s %s\n' "${CLR_WARN}!${RESET}" "$w" >&2
        done
    fi

    if [[ $failed_count -gt 0 ]]; then
        echo "" >&2
        printf '%s\n' "${BOLD}${CLR_ERROR}Failures (${failed_count})${RESET}" >&2
        local fp
        for fp in "${_FAILED_PACKAGES[@]}"; do
            local r="${_FAILURE_REASONS["$fp"]:-unknown error}"
            printf '  %s %s\n' "${CLR_ERROR}✗${RESET}" "${BOLD}${fp}${RESET}" >&2
            printf '    %s %s\n' "${CLR_ERROR}↳${RESET}" "${CLR_MUTED}${r}${RESET}" >&2
            local rhint
            rhint="$(_get_remediation_hint "$r")"
            [[ -n "$rhint" ]] && printf '      %s %s\n' "${CLR_WARN}hint:${RESET}" "${CLR_MUTED}${rhint}${RESET}" >&2
        done
    fi
    echo "" >&2
}
