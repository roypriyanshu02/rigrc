# shellcheck shell=bash
# =============================================================================
#  UI COMPONENT SYSTEM (ANSI Themes, Widgets, Spinners & Summary)
# =============================================================================

# ---------------------------------------------------------------------------
# Colors & Theme Foundation (Tier 0)
# ---------------------------------------------------------------------------
_ui_init_theme() {
    local color_enabled=0
    if [[ -n "${FORCE_COLOR:-}" && "${FORCE_COLOR}" != "0" ]] || [[ -n "${CLICOLOR_FORCE:-}" && "${CLICOLOR_FORCE}" != "0" ]]; then
        color_enabled=1
    elif [[ ( -t 1 || -t 2 ) && -z "${NO_COLOR:-}" && "${CLICOLOR:-1}" != "0" && "${TERM:-}" != "dumb" ]]; then
        color_enabled=1
    fi

    if [[ "$color_enabled" -eq 1 && "${RIGRC_THEME:-}" != "mono" && "${RIGRC_THEME:-}" != "plain" && "${RIGRC_THEME:-}" != "none" ]]; then
        RESET=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m' ITALIC=$'\033[3m'

        case "${RIGRC_THEME:-default}" in
            amber|orange|warm)
                CLR_PRIMARY=$'\033[1;33m'   # Bold Amber
                CLR_ACCENT=$'\033[36m'      # Cyan
                ;;
            cyan|blue)
                CLR_PRIMARY=$'\033[1;36m'   # Bold Cyan
                CLR_ACCENT=$'\033[33m'      # Amber
                ;;
            *) # default / native: Adaptive Unix Native (Bold Blue + Amber)
                CLR_PRIMARY=$'\033[1;34m'   # Bold Blue
                CLR_ACCENT=$'\033[33m'      # Amber / Yellow
                ;;
        esac

        CLR_SUCCESS=$'\033[32m'         # Green
        CLR_WARN=$'\033[33m'            # Yellow / Amber
        CLR_ERROR=$'\033[1;31m'         # Bold Red
        CLR_MUTED=$'\033[90m'           # Slate Gray / Bright Black
        CLR_TEXT=''                     # Adaptive text (inherits terminal foreground)
    else
        RESET='' BOLD='' DIM='' ITALIC=''
        CLR_PRIMARY='' CLR_ACCENT='' CLR_SUCCESS='' CLR_WARN='' CLR_ERROR='' CLR_MUTED='' CLR_TEXT=''
    fi

    SYM_OK="✓" SYM_FAIL="✗" SYM_WARN="!" SYM_INFO="i" SYM_Q="?" SYM_DOT="●" SYM_CIRCLE="○" SYM_BLOCKED="⊘" SYM_ARROW="↳" SYM_BULLET="•" SYM_DASH="–"
}
_ui_init_theme

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

_LAST_BELL_TIME=-999
_ui_bell() {
    [[ "${NON_INTERACTIVE:-false}" == true || "${DOTFILES_NO_BELL:-false}" == true ]] && return 0
    local min_interval=45
    if [[ $(( SECONDS - _LAST_BELL_TIME )) -ge $min_interval ]]; then
        _LAST_BELL_TIME=$SECONDS
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
            display_res="${CLR_MUTED}${SYM_ARROW} skipped${RESET}"
        else
            display_res="${CLR_TEXT}${SYM_ARROW} ${res}${RESET}"
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
        local menu_height=$(( total + 1 ))
        local key=""
        printf '\033[?25l' >&2 # Hide cursor

        _render_menu() {
            local out_buf=""
            out_buf+=$'\r\033[2K'"  ${CLR_PRIMARY}${SYM_Q}${RESET} ${BOLD}${prompt}${RESET}"$'\n'
            local i
            for i in "${!opts[@]}"; do
                if [[ $i -eq $selected ]]; then
                    out_buf+=$'\r\033[2K'"    ${CLR_PRIMARY}${SYM_DOT}${RESET} ${BOLD}${CLR_PRIMARY}${opts[$i]}${RESET}"$'\n'
                else
                    out_buf+=$'\r\033[2K'"    ${CLR_MUTED}${SYM_CIRCLE}${RESET} ${CLR_MUTED}${opts[$i]}${RESET}"$'\n'
                fi
            done
            printf '%s' "$out_buf" >&2
        }

        local _pre
        for (( _pre=0; _pre < menu_height; _pre++ )); do
            printf '\n' >&2
        done
        printf '\r\033[%dA' "$menu_height" >&2

        _render_menu

        while true; do
            IFS= read -rsn1 key < /dev/tty 2>/dev/null || break
            if [[ "$key" == $'\x1b' ]]; then
                read -rsn2 -t 0.1 rest < /dev/tty 2>/dev/null || rest=""
                key+="$rest"
            fi

            case "$key" in
                $'\x1b[A'|$'\x1bOA'|k|K)
                    selected=$(( (selected - 1 + total) % total ))
                    ;;
                $'\x1b[B'|$'\x1bOB'|j|J)
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

            printf '\r\033[%dA' "$menu_height" >&2
            _render_menu
        done

        printf '\033[?25h' >&2 # Restore cursor
        printf '\r\033[%dA\033[J' "$menu_height" >&2
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
    local -a _ms_raw_tags=() _ms_tag_fmts=()
    local _idx
    for _idx in "${!_ms_items[@]}"; do
        local _item="${_ms_items[_idx]}"
        local _lbl="${_ms_labels[_idx]:-$_item}"
        local _lock="${_ms_locks[_idx]:-}"
        [[ ${#_lbl} -gt $max_name_len ]] && max_name_len=${#_lbl}

        local _rtag="" _tfmt=""
        if [[ "$_lock" == "config" ]]; then
            _rtag="selected in config"
            _tfmt="${CLR_PRIMARY}${_rtag}${RESET}"
        elif [[ "$_lock" == "required" ]]; then
            _rtag="core system"
            _tfmt="${CLR_ACCENT}${_rtag}${RESET}"
        elif [[ "$_lock" == "installed"* ]]; then
            _rtag="already installed"
            _tfmt="${CLR_MUTED}${_rtag}${RESET}"
        elif [[ "$_lock" == "alt:"* ]]; then
            local _at="${_lock#alt:}"
            _at="${_at% installed}"
            _rtag="alternative to ${_at}"
            _tfmt="${CLR_MUTED}${_rtag}${RESET}"
        elif [[ "$_lock" == "unsupported:"* ]]; then
            local _r="${_lock#unsupported:}"
            local _env_label="$(_format_env_name "$_r")"
            _rtag="unavailable on ${_env_label}"
            _tfmt="${CLR_WARN}${_rtag}${RESET}"
        elif [[ "$_lock" == "disabled"* ]]; then
            _rtag="disabled"
            _tfmt="${CLR_MUTED}${_rtag}${RESET}"
        fi
        _ms_raw_tags[$_idx]="$_rtag"
        _ms_tag_fmts[$_idx]="$_tfmt"
        [[ ${#_rtag} -gt $max_tag_len ]] && max_tag_len=${#_rtag}
    done
    local name_col_width=$(( max_name_len + 2 ))

    local term_lines=24
    if command -v tput >/dev/null 2>&1; then
        term_lines="$(tput lines 2>/dev/null || echo 24)"
    fi
    local max_visible=$(( term_lines - 6 ))
    [[ $max_visible -lt 5 ]] && max_visible=5
    [[ $max_visible -gt $total ]] && max_visible=$total
    local menu_height=$(( max_visible + 3 ))

    _render_ms_menu() {
        local cols=80
        if command -v tput >/dev/null 2>&1; then
            cols="$(tput cols 2>/dev/null || echo 80)"
        fi
        local ind="${LOG_INDENT:-  }"
        local max_line_width=$(( cols - 1 ))
        [[ $max_line_width -lt 20 ]] && max_line_width=20

        local display_prompt="$prompt"
        if [[ "$prompt" =~ ^Packages[[:space:]]+in[[:space:]]+\[(.*)\]$ ]]; then
            display_prompt="Select packages · ${BASH_REMATCH[1]}"
        elif [[ "$prompt" == "Select package groups" ]]; then
            display_prompt="Select package groups"
        fi

        local hint_text="Space toggle · A all · Enter continue"
        if [[ $total -gt $max_visible ]]; then
            hint_text="Space toggle · A all · Enter continue ($(( selected + 1 ))/${total})"
        fi

        local out_buf=""
        out_buf+=$'\r\033[2K'"${ind}${BOLD}${display_prompt}${RESET}"$'\n'
        out_buf+=$'\r\033[2K'"${ind}${CLR_MUTED}${hint_text}${RESET}"$'\n\r\033[2K\n'

        local eff_name_width=$name_col_width
        local max_allowed_name=$(( max_line_width / 3 ))
        [[ $max_allowed_name -lt 12 ]] && max_allowed_name=12
        [[ $eff_name_width -gt $max_allowed_name ]] && eff_name_width=$max_allowed_name

        local prefix_len=$(( ${#ind} + 5 + eff_name_width ))
        local avail_space=$(( max_line_width - prefix_len ))

        local desc_col_width=0
        if [[ $max_tag_len -gt 0 ]]; then
            if [[ $avail_space -ge $(( max_tag_len + 10 )) ]]; then
                desc_col_width=$(( avail_space - max_tag_len - 2 ))
            else
                desc_col_width=0
            fi
        else
            desc_col_width=$(( avail_space > 0 ? avail_space : 0 ))
        fi

        local win_start=0
        local win_end=$total
        if [[ $total -gt $max_visible ]]; then
            local half=$(( max_visible / 2 ))
            win_start=$(( selected - half ))
            [[ $win_start -lt 0 ]] && win_start=0
            win_end=$(( win_start + max_visible ))
            if [[ $win_end -gt $total ]]; then
                win_end=$total
                win_start=$(( total - max_visible ))
                [[ $win_start -lt 0 ]] && win_start=0
            fi
        fi

        local i
        for (( i = win_start; i < win_end; i++ )); do
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
                radio_icon="${CLR_ACCENT}${SYM_DOT}${RESET}"
            elif [[ "$lock" == "config" ]]; then
                radio_icon="${CLR_PRIMARY}${SYM_DOT}${RESET}"
            elif [[ "$st" -eq 1 ]]; then
                radio_icon="${CLR_PRIMARY}${SYM_DOT}${RESET}"
            else
                radio_icon="${CLR_MUTED}${SYM_CIRCLE}${RESET}"
            fi

            local raw_tag="${_ms_raw_tags[$i]:-}" tag_fmt="${_ms_tag_fmts[$i]:-}"

            local cur_lbl="$lbl"
            if [[ ${#cur_lbl} -gt $eff_name_width ]]; then
                cur_lbl="${cur_lbl:0:$((eff_name_width - 1))}…"
            fi
            local pad_len=$(( eff_name_width - ${#cur_lbl} ))
            [[ $pad_len -lt 1 ]] && pad_len=1
            local pad_spaces
            printf -v pad_spaces '%*s' "$pad_len" ""

            local cur_desc="$desc"
            local desc_fmt=""
            local desc_spaces=""
            if [[ $desc_col_width -gt 0 && -n "$cur_desc" ]]; then
                if [[ ${#cur_desc} -gt $desc_col_width ]]; then
                    cur_desc="${cur_desc:0:$((desc_col_width - 1))}…"
                fi
                local desc_pad=$(( desc_col_width - ${#cur_desc} ))
                [[ $desc_pad -lt 1 ]] && desc_pad=1
                printf -v desc_spaces '%*s' "$desc_pad" ""
                if [[ $i -eq $selected && "$lock" != "disabled"* && "$lock" != "unsupported:"* ]]; then
                    desc_fmt="${CLR_TEXT}${cur_desc}${RESET}"
                else
                    desc_fmt="${CLR_MUTED}${cur_desc}${RESET}"
                fi
            fi

            local cur_tag="$raw_tag"
            local cur_tag_fmt="$tag_fmt"
            if [[ -n "$cur_tag" ]]; then
                local used_len=$(( ${#ind} + 5 + ${#cur_lbl} + pad_len + ${#cur_desc} + ${#desc_spaces} ))
                local tag_space=$(( max_line_width - used_len ))
                if [[ $tag_space -gt 0 && ${#cur_tag} -gt $tag_space ]]; then
                    cur_tag="${cur_tag:0:$((tag_space - 1))}…"
                    if [[ "$lock" == "required" ]]; then
                        cur_tag_fmt="${CLR_ACCENT}${cur_tag}${RESET}"
                    elif [[ "$lock" == "unsupported:"* ]]; then
                        cur_tag_fmt="${CLR_WARN}${cur_tag}${RESET}"
                    else
                        cur_tag_fmt="${CLR_MUTED}${cur_tag}${RESET}"
                    fi
                elif [[ $tag_space -le 0 ]]; then
                    cur_tag_fmt=""
                fi
            fi

            local lbl_color
            if [[ $i -eq $selected ]]; then
                if [[ "$lock" == "disabled"* || "$lock" == "unsupported:"* ]]; then
                    lbl_color="${BOLD}${CLR_MUTED}"
                else
                    lbl_color="${BOLD}${CLR_PRIMARY}"
                fi
            else
                lbl_color="${CLR_MUTED}"
            fi

            out_buf+=$'\r\033[2K'"${ind}  ${radio_icon}  ${lbl_color}${cur_lbl}${RESET}${pad_spaces}${desc_fmt}${desc_spaces}${cur_tag_fmt}"$'\n'
        done

        printf '%s' "$out_buf" >&2
    }

    # WINCH signal trap for window resizing
    _on_winch() {
        if command -v tput >/dev/null 2>&1; then
            term_lines="$(tput lines 2>/dev/null || echo 24)"
        fi
        max_visible=$(( term_lines - 6 ))
        [[ $max_visible -lt 5 ]] && max_visible=5
        [[ $max_visible -gt $total ]] && max_visible=$total
        menu_height=$(( max_visible + 3 ))
        printf '\r\033[%dA\033[J' "$menu_height" >&2
        _render_ms_menu
    }
    trap '_on_winch' WINCH

    local _pre
    for (( _pre=0; _pre < menu_height; _pre++ )); do
        printf '\n' >&2
    done
    printf '\r\033[%dA' "$menu_height" >&2

    _render_ms_menu

    while true; do
        IFS= read -rsn1 key < /dev/tty 2>/dev/null || break
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 rest < /dev/tty 2>/dev/null || rest=""
            key+="$rest"
            while read -rsn1 -t 0.01 extra < /dev/tty 2>/dev/null; do
                key+="$extra"
            done
        fi

        case "$key" in
            $'\x1b[A'|$'\x1bOA'|k|K)
                selected=$(( (selected - 1 + total) % total ))
                ;;
            $'\x1b[B'|$'\x1bOB'|j|J)
                selected=$(( (selected + 1) % total ))
                ;;
            $'\x1b[5~') # Page Up
                selected=$(( selected - max_visible ))
                [[ $selected -lt 0 ]] && selected=0
                ;;
            $'\x1b[6~') # Page Down
                selected=$(( selected + max_visible ))
                [[ $selected -ge $total ]] && selected=$(( total - 1 ))
                ;;
            $'\x1b[H'|$'\x1b[1~') # Home
                selected=0
                ;;
            $'\x1b[F'|$'\x1b[4~') # End
                selected=$(( total - 1 ))
                ;;
            " "|x|X)
                local cur_lock="${_ms_locks[$selected]:-}"
                if [[ "$cur_lock" != "required" && "$cur_lock" != "config" && "$cur_lock" != "installed:"* && "$cur_lock" != "unsupported:"* && "$cur_lock" != "disabled"* ]]; then
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
                    if [[ "$j_lock" != "required" && "$j_lock" != "config" && "$j_lock" != "installed:"* && "$j_lock" != "unsupported:"* && "$j_lock" != "disabled"* ]]; then
                        if [[ "${_ms_states[$j]:-0}" -ne 1 ]]; then
                            all_toggleable_checked=0
                            break
                        fi
                    fi
                done
                for j in "${!_ms_items[@]}"; do
                    local j_lock="${_ms_locks[$j]:-}"
                    if [[ "$j_lock" != "required" && "$j_lock" != "config" && "$j_lock" != "installed:"* && "$j_lock" != "unsupported:"* && "$j_lock" != "disabled"* ]]; then
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

        printf '\r\033[%dA' "$menu_height" >&2
        _render_ms_menu
    done

    trap - WINCH

    printf '\033[?25h' >&2
    printf '\r\033[%dA\033[J' "$menu_height" >&2

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
    local title="${3:-$1}"
    _set_term_title "Dotfiles: ${title}"
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        printf '\n%s\n' "${CLR_TEXT}${BOLD}${title}${RESET}" >&2
    else
        printf '\n%s\n' "$title" >&2
    fi
}

_get_remediation_hint() {
    case "${1,,}" in
        *lock*|*"could not get lock"*)
            printf 'Package manager lock busy. Wait for background update or clear stale lock.' ;;
        *404*|*"not found"*)
            printf 'Asset not found on release server. Check release URL and target architecture.' ;;
        *403*|*"rate limit"*)
            printf 'GitHub API rate limit exceeded. Set GITHUB_TOKEN to proceed.' ;;
        *"permission denied"*)
            printf 'Permission denied. Run with sudo or fix target path permissions.' ;;
        *"checksum mismatch"*)
            printf 'Checksum mismatch. Downloaded archive is corrupted or modified.' ;;
        *"no space left"*)
            printf 'Disk space exhausted. Free up disk space on target filesystem.' ;;
        *"timed out"*)
            printf 'Operation timed out. Check network connection or increase INSTALL_TIMEOUT.' ;;
        *ssl*|*certificate*|*tls*)
            printf 'SSL/TLS certificate error. Verify system time and CA certificates.' ;;
        *"connection refused"*|*"couldn't connect to server"*)
            printf 'Connection refused. Check internet connectivity and proxy settings.' ;;
    esac
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
            printf '%s  %s %s\n' "$ind" "${CLR_ERROR}${SYM_ARROW}${RESET}" "${CLR_MUTED}${_LAST_CMD_ERROR}${RESET}" >&2
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
            printf '  %s %s\n' "${CLR_WARN}${SYM_WARN}${RESET}" "$w" >&2
        done
    fi

    if [[ $failed_count -gt 0 ]]; then
        echo "" >&2
        printf '%s\n' "${BOLD}${CLR_ERROR}Failures (${failed_count})${RESET}" >&2
        local fp
        for fp in "${_FAILED_PACKAGES[@]}"; do
            local r="${_FAILURE_REASONS["$fp"]:-unknown error}"
            printf '  %s %s\n' "${CLR_ERROR}${BOLD}${SYM_FAIL}${RESET}" "${BOLD}${fp}${RESET}" >&2
            printf '    %s %s\n' "${CLR_ERROR}${SYM_ARROW}${RESET}" "${CLR_MUTED}${r}${RESET}" >&2
            local rhint
            rhint="$(_get_remediation_hint "$r")"
            [[ -n "$rhint" ]] && printf '      %s %s\n' "${CLR_WARN}hint:${RESET}" "${CLR_MUTED}${rhint}${RESET}" >&2
        done
    fi
    echo "" >&2
}
