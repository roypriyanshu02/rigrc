# shellcheck shell=bash
# =============================================================================
#  PARSER ENGINE (Condition Grammar & INI Manifests)
# =============================================================================

_in_cond_list() {
    local target="$1" list_str="$2"
    [[ -z "$list_str" ]] && return 1
    local item ret=1 old_f="$-"
    set -f
    for item in ${list_str//,/ }; do
        item="${item#"${item%%[![:space:]]*}"}"; item="${item%"${item##*[![:space:]]}"}"
        if [[ "$item" == "$target" ]]; then
            ret=0
            break
        fi
    done
    [[ "$old_f" != *f* ]] && set +f
    return "$ret"
}

_check_cond_match() {
    local target="$1" list_str="$2"
    [[ -z "$list_str" ]] && return 1
    local clean_target="${target#arch:}"
    clean_target="${clean_target#profile:}"
    _in_cond_list "$target" "$list_str" || _in_cond_list "$clean_target" "$list_str"
}

# Evaluate cond field or cond: option. Returns 0 = proceed, 1 = skip.
_eval_cond() {
    local cond="$1" opts="${2:-}"
    [[ -z "$cond" ]] && cond="$(_get_opt cond "$opts")"
    [[ -z "$cond" ]] && return 0

    if [[ "${_CONF_CASCADE_DONE:-0}" -eq 0 && -d "${PACKAGES_DIR:-}" ]]; then
        _preload_all_manifests "$PACKAGES_DIR"
    fi

    local cond_override="${_CONF_PKG_KEYS["global:COND"]:-${COND:-}}"
    local dis_cond_override="${_CONF_PKG_KEYS["global:DISABLE_COND"]:-${DISABLE_COND:-}}"

    local c sys_arch _conds not_c
    sys_arch="$(_get_arch)"
    IFS=',' read -ra _conds <<< "$cond"
    for c in "${_conds[@]}"; do
        c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
        [[ -z "$c" ]] && continue

        if [[ "$c" == *"!"* ]]; then
            not_c="${c//!/}"
        else
            if [[ "$c" == "arch:"* ]]; then
                not_c="arch:!${c#arch:}"
            elif [[ "$c" == "profile:"* ]]; then
                not_c="profile:!${c#profile:}"
            else
                not_c="!$c"
            fi
        fi

        if _check_cond_match "$c" "$dis_cond_override" || _check_cond_match "$not_c" "$cond_override"; then
            return 1
        fi

        if _check_cond_match "$c" "$cond_override"; then
            continue
        fi

        local bare_c="$c"
        bare_c="${bare_c#profile:}"
        bare_c="${bare_c/profile:/}"

        case "$bare_c" in
            desktop|linux)                        [[ "$(_get_profile)" == "desktop" || "$(uname -s)" == Linux ]] || return 1 ;;
            '!desktop'|'!linux')                  [[ "$(_get_profile)" != "desktop" && "$(uname -s)" != Linux ]] || return 1 ;;
            wsl)                                  _is_wsl || return 1 ;;
            '!wsl')                               _is_wsl && return 1 ;;
            vps)                                  [[ "$(_get_profile)" == "vps" ]] || return 1 ;;
            '!vps')                               [[ "$(_get_profile)" != "vps" ]] || return 1 ;;
            container)                            _is_container || return 1 ;;
            '!container')                         _is_container && return 1 ;;
            arch:x86_64|x86_64|arch:amd64|amd64)     [[ "$sys_arch" == x86_64 ]] || return 1 ;;
            arch:!x86_64|!x86_64|arch:!amd64|!amd64) [[ "$sys_arch" != x86_64 ]] || return 1 ;;
            arch:arm64|arm64|arch:aarch64|aarch64)   [[ "$sys_arch" == arm64 ]] || return 1 ;;
            arch:!arm64|!arm64|arch:!aarch64|!aarch64) [[ "$sys_arch" != arm64 ]] || return 1 ;;
            *)                                    log_warn "Unknown condition '$c'. Skipping package."; return 1 ;;
        esac
    done
    return 0
}

# Resolve the human-readable detected condition that caused a failure
_get_failed_cond_reason() {
    local cond="$1" opts="${2:-}"
    [[ -z "$cond" ]] && cond="$(_get_opt cond "$opts")"
    [[ -z "$cond" ]] && { printf 'unmet'; return 0; }

    local cond_override="${_CONF_PKG_KEYS["global:COND"]:-${COND:-}}"
    local dis_cond_override="${_CONF_PKG_KEYS["global:DISABLE_COND"]:-${DISABLE_COND:-}}"
    local sys_arch="$(_get_arch)"

    local c _conds not_c
    IFS=',' read -ra _conds <<< "$cond"
    for c in "${_conds[@]}"; do
        c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
        [[ -z "$c" ]] && continue

        if [[ "$c" == *"!"* ]]; then
            not_c="${c//!/}"
        else
            if [[ "$c" == "arch:"* ]]; then
                not_c="arch:!${c#arch:}"
            elif [[ "$c" == "profile:"* ]]; then
                not_c="profile:!${c#profile:}"
            else
                not_c="!$c"
            fi
        fi

        if _check_cond_match "$c" "$dis_cond_override" || _check_cond_match "$not_c" "$cond_override"; then
            printf '%s' "${c}"
            return 0
        fi

        if _check_cond_match "$c" "$cond_override"; then
            continue
        fi

        local bare_c="$c"
        bare_c="${bare_c#profile:}"
        bare_c="${bare_c/profile:/}"

        case "$bare_c" in
            desktop|linux)
                if [[ "$(_get_profile)" != "desktop" && "$(uname -s)" != Linux ]]; then
                    printf '%s' "$(_get_profile)"
                    return 0
                fi
                ;;
            '!desktop'|'!linux')
                if [[ "$(_get_profile)" == "desktop" || "$(uname -s)" == Linux ]]; then
                    printf '%s' "$(_get_profile)"
                    return 0
                fi
                ;;
            wsl)
                if ! _is_wsl; then
                    printf 'non-wsl'
                    return 0
                fi
                ;;
            '!wsl')
                if _is_wsl; then
                    printf 'wsl'
                    return 0
                fi
                ;;
            vps)
                if [[ "$(_get_profile)" != "vps" ]]; then
                    printf '%s' "$(_get_profile)"
                    return 0
                fi
                ;;
            '!vps')
                if [[ "$(_get_profile)" == "vps" ]]; then
                    printf 'vps'
                    return 0
                fi
                ;;
            container)
                if ! _is_container; then
                    printf 'host'
                    return 0
                fi
                ;;
            '!container')
                if _is_container; then
                    printf 'container'
                    return 0
                fi
                ;;
            arch:x86_64|x86_64|arch:amd64|amd64)
                if [[ "$sys_arch" != x86_64 ]]; then
                    printf '%s' "$sys_arch"
                    return 0
                fi
                ;;
            arch:!x86_64|!x86_64|arch:!amd64|!amd64)
                if [[ "$sys_arch" == x86_64 ]]; then
                    printf '%s' "$sys_arch"
                    return 0
                fi
                ;;
            arch:arm64|arm64|arch:aarch64|aarch64)
                if [[ "$sys_arch" != arm64 ]]; then
                    printf '%s' "$sys_arch"
                    return 0
                fi
                ;;
            arch:!arm64|!arm64|arch:!aarch64|!aarch64)
                if [[ "$sys_arch" == arm64 ]]; then
                    printf '%s' "$sys_arch"
                    return 0
                fi
                ;;
            *)
                printf '%s' "$c"
                return 0
                ;;
        esac
    done
    printf 'unmet'
}

# Prompt user for confirmation during interactive execution.


# ---------------------------------------------------------------------------
# _collect_bashrc_snippets CONF
# Pass 2 of packages.conf: collect [bashrc]...[/bashrc] blocks
# only for groups that are in INSTALL_GROUPS (or all if empty).
# ---------------------------------------------------------------------------
_preload_groups_conf() {
    [[ "$_GROUPS_LOADED" -eq 1 ]] && return 0
    _GROUPS_LOADED=1
    local groups_conf="$PACKAGES_DIR/_groups.conf"
    if [[ ! -f "$groups_conf" ]]; then
        local gdir
        for gdir in "$PACKAGES_DIR"/*; do
            [[ -d "$gdir" ]] && _GROUPS_LIST+=("$(basename "$gdir")")
        done
        return 0
    fi

    local current_grp="" raw_line line
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == '#'* ]] && continue
        if [[ "$line" =~ ^\[group:([a-zA-Z0-9_.-]+) ]]; then
            current_grp="${BASH_REMATCH[1]}"
            _GROUPS_LIST+=("$current_grp")
            continue
        fi
        if [[ -n "$current_grp" && "$line" == *"="* ]]; then
            local k="${line%%=*}" v="${line#*=}"
            k="${k#"${k%%[![:space:]]*}"}"; k="${k%"${k##*[![:space:]]}"}"
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            if [[ "$k" == "description" ]]; then
                _GROUP_DESCS["$current_grp"]="$v"
            elif [[ "$k" == "packages" ]]; then
                _GROUP_PACKAGES_MAP["$current_grp"]="$v"
            elif [[ "$k" == "optional" ]]; then
                _GROUP_OPTIONAL["$current_grp"]="$v"
            fi
        fi
    done < "$groups_conf"
}

_get_groups() {
    _preload_groups_conf
    if [[ ${#_GROUPS_LIST[@]} -gt 0 ]]; then
        printf '%s\n' "${_GROUPS_LIST[@]}"
    fi
}

_get_group_meta() {
    _preload_groups_conf
    case "$2" in
        description) printf '%s' "${_GROUP_DESCS["$1"]:-}" ;;
        packages)    printf '%s' "${_GROUP_PACKAGES_MAP["$1"]:-}" ;;
        optional)    printf '%s' "${_GROUP_OPTIONAL["$1"]:-true}" ;;
    esac
}

_get_group_packages() {
    local gname="$1"
    local pkgs_str="$(_get_group_meta "$gname" "packages")"
    if [[ -n "$pkgs_str" ]]; then
        local p
        IFS=',' read -ra p_arr <<< "$pkgs_str"
        for p in "${p_arr[@]}"; do
            p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
            [[ -n "$p" ]] && printf '%s\n' "$p"
        done
    else
        local conf_file
        for conf_file in "$PACKAGES_DIR/$gname"/*.conf; do
            [[ -f "$conf_file" ]] && basename "$conf_file" .conf
        done
    fi
}

_collect_bashrc_snippets() {
    local pdir="${1:-$PACKAGES_DIR}"
    [[ ! -d "$pdir" ]] && return 0
    _preload_all_manifests "$pdir"

    if [[ "${_CONF_BASHRC_DIS["global"]:-0}" -ne 1 && -n "${_CONF_BASHRC_BUF["global"]:-}" ]]; then
        printf '%s\n' "${_CONF_BASHRC_BUF["global"]}"
    fi

    local group pkg
    while IFS= read -r group; do
        [[ -z "$group" ]] && continue
        _group_selected "$group" || continue

        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local conf_file="$pdir/$group/$pkg.conf"
            [[ ! -f "$conf_file" ]] && continue

            if _package_is_active "$conf_file"; then
                printf '%s' "${_CONF_BASHRC["$conf_file"]:-}"
            fi
        done < <(_get_group_packages "$group")
    done < <(_get_groups)
}



# ---------------------------------------------------------------------------
# Config-driven optional package resolution
# ---------------------------------------------------------------------------
_should_install_optional() {
    local pkg="$1" desc="$2" is_rec="${3:-false}" is_alt="${4:-false}" alt_target="${5:-}"

    # 1. Explicit package allow-list
    local p
    for p in "${OPTIONAL_PACKAGES[@]:-}"; do
        [[ "$p" == "$pkg" ]] && return 0
    done

    # 2. Unanswered: check TTY for interactive prompt
    if [[ -t 0 || -t 1 || -t 2 || -c /dev/tty ]] && [[ "$DRY_RUN" == false && "${NON_INTERACTIVE:-false}" == false ]]; then
        local msg="Install optional package '${pkg}'?"
        if [[ "$is_alt" == true ]]; then
            msg="Install alternative package '${pkg}' ('${alt_target}' is installed)?"
        fi
        local PROMPT_INDENT="    "
        _prompt_confirm "$msg" "$is_rec"
        return $?
    fi

    # 3. Unanswered headless default: recommended packages install automatically
    [[ "$is_rec" == true ]] && return 0 || return 1
}

_group_selected() {
    local gname="$1"
    if [[ ${#INSTALL_GROUPS[@]} -gt 0 ]]; then
        local g
        for g in "${INSTALL_GROUPS[@]}"; do
            [[ "$g" == "$gname" ]] && return 0
        done
        return 1
    fi

    local is_opt="$(_get_group_meta "$gname" "optional")"
    if [[ "$is_opt" == "false" || "$gname" == "core" ]]; then
        return 0
    fi
    return 1
}

_parse_section_header() {
    local raw_header="$1"
    local -n _out_type="$2"
    local -n _out_ident="$3"
    local -n _out_mod="$4"
    local -n _out_valid="$5"

    local l_type="" l_ident="" l_mod="append" l_valid=0

    local header="${raw_header#"${raw_header%%[![:space:]]*}"}"
    header="${header%"${header##*[![:space:]]}"}"
    if [[ -z "$header" ]]; then
        _out_type=""
        _out_ident=""
        _out_mod="append"
        _out_valid=1
        return 0
    fi

    local parts=()
    IFS=':' read -ra parts <<< "$header"
    local n=${#parts[@]}

    if [[ $n -eq 0 ]]; then
        _out_type=""
        _out_ident=""
        _out_mod="append"
        _out_valid=1
        return 0
    fi

    case "${parts[0]}" in
        package|config|bashrc|template|group) l_type="${parts[0]}" ;;
        *)
            _out_type=""
            _out_ident=""
            _out_mod="append"
            _out_valid=1
            return 0
            ;;
    esac

    if [[ "$l_type" == "template" ]]; then
        if [[ $n -eq 1 ]]; then
            l_ident=""
            l_mod="append"
        elif [[ $n -eq 2 ]]; then
            l_ident="${parts[1]}"
            l_mod="append"
        else
            l_ident="${parts[1]}"
            l_mod="${parts[*]:2}"
            l_valid=0
        fi
    else
        if [[ $n -eq 1 ]]; then
            l_ident=""
            l_mod="append"
        elif [[ $n -eq 2 ]]; then
            local p1="${parts[1]}"
            case "$p1" in
                append|override|disable|once)
                    l_ident=""
                    l_mod="$p1"
                    ;;
                *)
                    l_ident="$p1"
                    l_mod="append"
                    ;;
            esac
        elif [[ $n -eq 3 ]]; then
            local p1="${parts[1]}"
            local p2="${parts[2]}"
            case "$p2" in
                append|override|disable|once)
                    l_ident="$p1"
                    l_mod="$p2"
                    ;;
                *)
                    l_ident="$p1"
                    l_mod="$p2"
                    l_valid=1
                    ;;
            esac
        else
            l_valid=1
        fi
        l_ident="${l_ident%.conf}"
        l_ident="${l_ident#.}"
        if [[ "$l_ident" == *config && "$l_ident" != "config" && "$l_ident" != */* ]]; then
            l_ident="${l_ident%config}"
        fi
    fi

    _out_type="$l_type"
    _out_ident="$l_ident"
    _out_mod="$l_mod"
    _out_valid="$l_valid"
}


_clear_pkg_keys() {
    local target="$1"
    local k
    if [[ ${#_CONF_PKG_KEYS[@]} -gt 0 ]]; then
        for k in "${!_CONF_PKG_KEYS[@]}"; do
            if [[ "$k" == "${target}:"* ]]; then
                unset "_CONF_PKG_KEYS[$k]"
            fi
        done
    fi
}

_parse_single_conf_file() {
    local file="$1"
    local default_pkg="$2"
    [[ ! -f "$file" ]] && return 0

    local cur_type="" cur_ident="" cur_mod="append"
    local cur_tmpl_buf="" in_tmpl=false
    local raw_line line

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            local header="${BASH_REMATCH[1]}"
            local sec_type="" sec_ident="" sec_mod="" is_valid=0
            _parse_section_header "$header" sec_type sec_ident sec_mod is_valid

            if [[ "$is_valid" -eq 0 ]]; then
                if [[ "$in_tmpl" == true ]]; then
                    local t_target="${cur_ident:-$default_pkg}"
                    local formatted_tmpl="$cur_tmpl_buf"
                    if [[ "$formatted_tmpl" != *"# target:"* && "$formatted_tmpl" != "#target:"* ]]; then
                        formatted_tmpl="# target: ${cur_ident:-$default_pkg} flags: ${cur_mod:-append}"$'\n'"$formatted_tmpl"
                    fi
                    if [[ "${_CONF_TMPL_DIS["$t_target"]:-0}" -ne 1 && "${_CONF_TMPL_DIS["$default_pkg"]:-0}" -ne 1 ]]; then
                        _CONF_TMPL_BUF["$t_target"]+="${formatted_tmpl}__TMPL_SEP__"
                        if [[ "$t_target" != "$default_pkg" && -n "$default_pkg" ]]; then
                            _CONF_TMPL_BUF["$default_pkg"]+="${formatted_tmpl}__TMPL_SEP__"
                        fi
                    fi
                    cur_tmpl_buf=""
                    in_tmpl=false
                fi

                cur_type="$sec_type"
                cur_ident="${sec_ident:-$default_pkg}"
                cur_mod="$sec_mod"

                if [[ "$cur_type" == "template" ]]; then
                    in_tmpl=true
                    if [[ "$cur_mod" == *"override"* ]]; then
                        _CONF_TMPL_BUF["$cur_ident"]=""
                        _CONF_TMPL_DIS["$cur_ident"]=0
                    elif [[ "$cur_mod" == *"disable"* ]]; then
                        _CONF_TMPL_BUF["$cur_ident"]=""
                        _CONF_TMPL_DIS["$cur_ident"]=1
                    else
                        _CONF_TMPL_DIS["$cur_ident"]=0
                    fi
                elif [[ "$cur_type" == "package" || "$cur_type" == "config" ]]; then
                    if [[ "$cur_mod" == "override" ]]; then
                        _clear_pkg_keys "$cur_ident"
                        _CONF_PKG_DISABLED["$cur_ident"]=0
                    elif [[ "$cur_mod" == "disable" ]]; then
                        _clear_pkg_keys "$cur_ident"
                        _CONF_PKG_DISABLED["$cur_ident"]=1
                    elif [[ "$cur_mod" == "append" ]]; then
                        _CONF_PKG_DISABLED["$cur_ident"]=0
                    fi
                elif [[ "$cur_type" == "bashrc" ]]; then
                    if [[ "$cur_mod" == "override" ]]; then
                        _CONF_BASHRC_BUF["$cur_ident"]=""
                        _CONF_BASHRC_DIS["$cur_ident"]=0
                    elif [[ "$cur_mod" == "disable" ]]; then
                        _CONF_BASHRC_BUF["$cur_ident"]=""
                        _CONF_BASHRC_DIS["$cur_ident"]=1
                    elif [[ "$cur_mod" == "append" ]]; then
                        _CONF_BASHRC_DIS["$cur_ident"]=0
                    fi
                fi
                continue
            fi
        fi

        if [[ "$in_tmpl" == true ]]; then
            cur_tmpl_buf+="${raw_line}"$'\n'
            continue
        fi

        if [[ "$cur_type" == "bashrc" ]]; then
            if [[ "${_CONF_BASHRC_DIS["$cur_ident"]:-0}" -ne 1 ]]; then
                _CONF_BASHRC_BUF["$cur_ident"]+="${raw_line}"$'\n'
            fi
            continue
        fi

        if [[ "$cur_type" == "package" || "$cur_type" == "config" ]]; then
            [[ -z "$line" || "$line" == '#'* ]] && continue
            if [[ "$line" == *"="* ]]; then
                local key="${line%%=*}" val="${line#*=}"
                key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
                val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
                if [[ "$val" == "!delete" ]]; then
                    unset "_CONF_PKG_KEYS[${cur_ident}:${key}]"
                else
                    _CONF_PKG_KEYS["${cur_ident}:${key}"]="$val"
                fi
            fi
        fi
    done < "$file"

    if [[ "$in_tmpl" == true ]]; then
        local t_target="${cur_ident:-$default_pkg}"
        local formatted_tmpl="$cur_tmpl_buf"
        if [[ "$formatted_tmpl" != *"# target:"* && "$formatted_tmpl" != "#target:"* ]]; then
            formatted_tmpl="# target: ${cur_ident:-$default_pkg} flags: ${cur_mod:-append}"$'\n'"$formatted_tmpl"
        fi
        if [[ "${_CONF_TMPL_DIS["$t_target"]:-0}" -ne 1 && "${_CONF_TMPL_DIS["$default_pkg"]:-0}" -ne 1 ]]; then
            _CONF_TMPL_BUF["$t_target"]+="${formatted_tmpl}__TMPL_SEP__"
            if [[ "$t_target" != "$default_pkg" && -n "$default_pkg" ]]; then
                _CONF_TMPL_BUF["$default_pkg"]+="${formatted_tmpl}__TMPL_SEP__"
            fi
        fi
    fi
}

_get_pkg_prop() {
    local pkg="$1" target_key="$2" default_val="$3"
    shift 3
    local key
    for key in "$@"; do
        if [[ -n "${_CONF_PKG_KEYS["${pkg}:${key}"]+x}" ]]; then
            printf '%s' "${_CONF_PKG_KEYS["${pkg}:${key}"]}"
            return 0
        elif [[ -n "${_CONF_PKG_KEYS["${target_key}:${key}"]+x}" ]]; then
            printf '%s' "${_CONF_PKG_KEYS["${target_key}:${key}"]}"
            return 0
        fi
    done
    printf '%s' "$default_val"
}

_finalize_conf_caches() {
    local pdir="$1"
    [[ ! -d "$pdir" ]] && return 0

    # Pre-index extra hook keys once across all packages instead of O(N*K) scan per package
    declare -A _pkg_hooks=()
    local k
    if [[ ${#_CONF_PKG_KEYS[@]} -gt 0 ]]; then
        for k in "${!_CONF_PKG_KEYS[@]}"; do
            if [[ "$k" == *":cmd."* || "$k" == *":cmd" ]]; then
                local prefix="${k%:*}"
                local prop_name="${k#*:}"
                local prop_val="${_CONF_PKG_KEYS["$k"]}"
                _pkg_hooks["$prefix"]+="${prop_name}:\"${prop_val//\"/\\\"}\" "
            fi
        done
    fi

    local conf_file
    for conf_file in "$pdir"/*/*.conf; do
        [[ ! -f "$conf_file" ]] && continue
        local pkg group target_key
        pkg="$(basename "$conf_file" .conf)"
        group="$(basename "$(dirname "$conf_file")")"
        target_key="${group}/${pkg}"

        local p_name="${_CONF_PKG_KEYS["${pkg}:name"]:-${_CONF_PKG_KEYS["${target_key}:name"]:-$pkg}}"
        local p_bin="${_CONF_PKG_KEYS["${pkg}:binaries"]:-${_CONF_PKG_KEYS["${target_key}:binaries"]:-${_CONF_PKG_KEYS["${pkg}:bin"]:-${_CONF_PKG_KEYS["${target_key}:bin"]:-$pkg}}}}"
        local p_desc="${_CONF_PKG_KEYS["${pkg}:description"]:-${_CONF_PKG_KEYS["${target_key}:description"]:-${_CONF_PKG_KEYS["${pkg}:desc"]:-${_CONF_PKG_KEYS["${target_key}:desc"]:-}}}}"
        local p_scope="${_CONF_PKG_KEYS["${pkg}:system"]:-${_CONF_PKG_KEYS["${target_key}:system"]:-${_CONF_PKG_KEYS["${pkg}:scope"]:-${_CONF_PKG_KEYS["${target_key}:scope"]:-system}}}}"

        local apt_pkg="${_CONF_PKG_KEYS["${pkg}:apt"]:-${_CONF_PKG_KEYS["${target_key}:apt"]:-}}"
        local dnf_pkg="${_CONF_PKG_KEYS["${pkg}:dnf"]:-${_CONF_PKG_KEYS["${target_key}:dnf"]:-}}"
        local pacman_pkg="${_CONF_PKG_KEYS["${pkg}:pacman"]:-${_CONF_PKG_KEYS["${target_key}:pacman"]:-}}"
        local apk_pkg="${_CONF_PKG_KEYS["${pkg}:apk"]:-${_CONF_PKG_KEYS["${target_key}:apk"]:-}}"
        local mise_spec="${_CONF_PKG_KEYS["${pkg}:mise"]:-${_CONF_PKG_KEYS["${target_key}:mise"]:-}}"
        local uv_spec="${_CONF_PKG_KEYS["${pkg}:uv"]:-${_CONF_PKG_KEYS["${target_key}:uv"]:-}}"
        local cargo_spec="${_CONF_PKG_KEYS["${pkg}:cargo"]:-${_CONF_PKG_KEYS["${target_key}:cargo"]:-}}"
        local go_spec="${_CONF_PKG_KEYS["${pkg}:go"]:-${_CONF_PKG_KEYS["${target_key}:go"]:-}}"
        local bun_spec="${_CONF_PKG_KEYS["${pkg}:bun"]:-${_CONF_PKG_KEYS["${target_key}:bun"]:-}}"
        local npm_spec="${_CONF_PKG_KEYS["${pkg}:npm"]:-${_CONF_PKG_KEYS["${target_key}:npm"]:-}}"
        local flatpak_spec="${_CONF_PKG_KEYS["${pkg}:flatpak"]:-${_CONF_PKG_KEYS["${target_key}:flatpak"]:-}}"
        local brew_spec="${_CONF_PKG_KEYS["${pkg}:brew"]:-${_CONF_PKG_KEYS["${target_key}:brew"]:-}}"
        local cmd_val="${_CONF_PKG_KEYS["${pkg}:cmd"]:-${_CONF_PKG_KEYS["${target_key}:cmd"]:-}}"
        local cond_val="${_CONF_PKG_KEYS["${pkg}:cond"]:-${_CONF_PKG_KEYS["${target_key}:cond"]:-}}"
        local rec_val="${_CONF_PKG_KEYS["${pkg}:recommended"]:-${_CONF_PKG_KEYS["${target_key}:recommended"]:-${_CONF_PKG_KEYS["${pkg}:rec"]:-${_CONF_PKG_KEYS["${target_key}:rec"]:-}}}}"
        local alt_val="${_CONF_PKG_KEYS["${pkg}:alt"]:-${_CONF_PKG_KEYS["${target_key}:alt"]:-}}"
        local needs_val="${_CONF_PKG_KEYS["${pkg}:needs"]:-${_CONF_PKG_KEYS["${target_key}:needs"]:-}}"
        local opt_val="${_CONF_PKG_KEYS["${pkg}:optional"]:-${_CONF_PKG_KEYS["${target_key}:optional"]:-}}"
        local dis_val="${_CONF_PKG_KEYS["${pkg}:disabled"]:-${_CONF_PKG_KEYS["${target_key}:disabled"]:-}}"
        local p_install="${_CONF_PKG_KEYS["${pkg}:install"]:-${_CONF_PKG_KEYS["${target_key}:install"]:-}}"
        local p_opts="${_CONF_PKG_KEYS["${pkg}:options"]:-${_CONF_PKG_KEYS["${target_key}:options"]:-}}"

        local extra_inst_specs="${_pkg_hooks["$target_key"]:-}${_pkg_hooks["$pkg"]:-}"

        local inst_specs=""
        [[ -n "$apt_pkg" ]] && inst_specs+="apt:${apt_pkg} "
        [[ -n "$dnf_pkg" ]] && inst_specs+="dnf:${dnf_pkg} "
        [[ -n "$pacman_pkg" ]] && inst_specs+="pacman:${pacman_pkg} "
        [[ -n "$apk_pkg" ]] && inst_specs+="apk:${apk_pkg} "
        [[ -n "$mise_spec" ]] && inst_specs+="mise:\"${mise_spec}\" "
        [[ -n "$uv_spec" ]] && inst_specs+="uv:\"${uv_spec}\" "
        [[ -n "$cargo_spec" ]] && inst_specs+="cargo:\"${cargo_spec}\" "
        [[ -n "$go_spec" ]] && inst_specs+="go:\"${go_spec}\" "
        [[ -n "$bun_spec" ]] && inst_specs+="bun:\"${bun_spec}\" "
        [[ -n "$npm_spec" ]] && inst_specs+="npm:\"${npm_spec}\" "
        [[ -n "$flatpak_spec" ]] && inst_specs+="flatpak:\"${flatpak_spec}\" "
        [[ -n "$brew_spec" ]] && inst_specs+="brew:\"${brew_spec}\" "
        [[ -n "$cmd_val" ]] && inst_specs+="cmd:\"${cmd_val}\" "
        [[ -n "$extra_inst_specs" ]] && inst_specs+="${extra_inst_specs}"
        [[ -n "$p_install" ]] && inst_specs+="${p_install} "

        local opt_specs=""
        [[ -n "$cond_val" ]] && opt_specs+="cond:${cond_val} "
        [[ -n "$alt_val" ]] && opt_specs+="alt:${alt_val} "
        [[ -n "$needs_val" ]] && opt_specs+="needs:${needs_val} "
        [[ "$opt_val" == true ]] && opt_specs+="optional:true "
        if [[ "$rec_val" == true ]]; then
            opt_specs+="recommended:true "
        elif [[ -n "$rec_val" && "$rec_val" != false ]]; then
            if _eval_cond "$rec_val"; then
                opt_specs+="recommended:true "
            fi
        fi
        [[ "$dis_val" == true || "${_CONF_PKG_DISABLED["$pkg"]:-0}" -eq 1 || "${_CONF_PKG_DISABLED["$target_key"]:-0}" -eq 1 ]] && opt_specs+="disabled:true "
        [[ -n "$p_opts" ]] && opt_specs+="${p_opts} "

        _CONF_PKG_NAME["$conf_file"]="$p_name"
        _CONF_PKG_BIN["$conf_file"]="$p_bin"
        _CONF_PKG_DESC["$conf_file"]="$p_desc"
        _CONF_PKG_SCOPE["$conf_file"]="$p_scope"
        inst_specs="${inst_specs#"${inst_specs%%[![:space:]]*}"}"; inst_specs="${inst_specs%"${inst_specs##*[![:space:]]}"}"
        opt_specs="${opt_specs#"${opt_specs%%[![:space:]]*}"}"; opt_specs="${opt_specs%"${opt_specs##*[![:space:]]}"}"
        _CONF_PKG_INSTALL["$conf_file"]="$inst_specs"
        _CONF_PKG_OPTS["$conf_file"]="$opt_specs"

        if [[ "${_CONF_BASHRC_DIS["$pkg"]:-${_CONF_BASHRC_DIS["$target_key"]:-0}}" -ne 1 ]]; then
            _CONF_BASHRC["$conf_file"]="${_CONF_BASHRC_BUF["$pkg"]:-${_CONF_BASHRC_BUF["$target_key"]:-}}"
        else
            _CONF_BASHRC["$conf_file"]=""
        fi

        if [[ "${_CONF_TMPL_DIS["$pkg"]:-${_CONF_TMPL_DIS["$target_key"]:-0}}" -ne 1 ]]; then
            _CONF_TEMPLATES["$conf_file"]="${_CONF_TMPL_BUF["$pkg"]:-${_CONF_TMPL_BUF["$target_key"]:-}}"
        else
            _CONF_TEMPLATES["$conf_file"]=""
        fi

        _CONF_PARSED["$conf_file"]=1
    done
}

# Discover and resolve configuration file. If multiple configurations exist, prompt user.
_select_config_file() {
    local sdir="${1:-$SCRIPT_DIR}"
    if [[ -n "${CONFIG_FILE:-}" && -f "$CONFIG_FILE" ]]; then
        return 0
    fi

    local available_configs=()
    local cfg
    for cfg in "$sdir"/*.conf; do
        [[ ! -f "$cfg" ]] && continue
        local bname
        bname="$(basename "$cfg")"
        [[ "$bname" == "example.conf" ]] && continue
        available_configs+=("$bname")
    done

    if [[ ${#available_configs[@]} -eq 0 ]]; then
        CONFIG_FILE="$sdir/default.conf"
    elif [[ ${#available_configs[@]} -eq 1 ]]; then
        CONFIG_FILE="$sdir/${available_configs[0]}"
    else
        # Multiple configurations found
        if [[ "${NON_INTERACTIVE:-false}" == false ]]; then
            local choice
            choice="$(_ui_select "Multiple configuration files found. Select profile:" "${available_configs[@]}")"
            CONFIG_FILE="$sdir/${choice}"
        else
            if [[ -f "$sdir/default.conf" ]]; then
                CONFIG_FILE="$sdir/default.conf"
            else
                CONFIG_FILE="$sdir/${available_configs[0]}"
            fi
        fi
    fi
}

_preload_all_manifests() {
    local pdir="${1:-$PACKAGES_DIR}"
    [[ "$_CONF_CASCADE_DONE" -eq 1 ]] && return 0
    _CONF_CASCADE_DONE=1

    _select_config_file
    _preload_groups_conf

    _CONF_PKG_KEYS=()
    _CONF_PKG_DISABLED=()
    _CONF_PKG_DECLINED=()
    _CONF_BASHRC_BUF=()
    _CONF_BASHRC_DIS=()
    _CONF_TMPL_BUF=()
    _CONF_TMPL_DIS=()

    # Layer 1: default.conf
    local layer1="$SCRIPT_DIR/default.conf"
    if [[ -f "$layer1" ]]; then
        _parse_single_conf_file "$layer1" "global"
    fi

    # Layer 2: packages/*/*.conf
    if [[ -d "$pdir" ]]; then
        local conf_file
        for conf_file in "$pdir"/*/*.conf; do
            if [[ -f "$conf_file" ]]; then
                local pkg_default
                pkg_default="${conf_file#"$pdir/"}"
                pkg_default="${pkg_default%.conf}"
                _parse_single_conf_file "$conf_file" "$pkg_default"
            fi
        done
    fi

    # Layer 3: $CONFIG_FILE (selected or custom user config)
    if [[ -n "${CONFIG_FILE:-}" && -f "${CONFIG_FILE:-}" && "$CONFIG_FILE" != "$SCRIPT_DIR/default.conf" ]]; then
        _parse_single_conf_file "$CONFIG_FILE" "global"
    fi

    if [[ -n "${_CONF_PKG_KEYS["global:INSTALL_GROUPS"]:-}" ]]; then
        local raw_ig="${_CONF_PKG_KEYS["global:INSTALL_GROUPS"]}"
        raw_ig="${raw_ig//[()]/}"
        raw_ig="${raw_ig//,/ }"
        INSTALL_GROUPS=()
        local g
        for g in $raw_ig; do
            [[ -n "$g" ]] && INSTALL_GROUPS+=("$g")
        done
    fi

    _finalize_conf_caches "$pdir"
}

_preload_manifest_file() {
    local mfile="$1"
    local default_name="${2:-}"
    if [[ -z "$default_name" ]]; then
        if [[ "$mfile" == "$PACKAGES_DIR"/*/*.conf ]]; then
            default_name="${mfile#"$PACKAGES_DIR/"}"
            default_name="${default_name%.conf}"
        else
            default_name="$(basename "$mfile" .conf)"
        fi
    fi

    if [[ "$_CONF_CASCADE_DONE" -eq 0 ]]; then
        _preload_all_manifests "$PACKAGES_DIR"
    fi

    if [[ -z "${_CONF_PARSED["$mfile"]:-}" ]]; then
        _parse_single_conf_file "$mfile" "$default_name"
        _finalize_conf_caches "$PACKAGES_DIR"
    fi
}

_parse_manifest_file() {
    local mfile="$1"
    local default_name="${2:-}"
    if [[ -z "$default_name" ]]; then
        if [[ "$mfile" == "$PACKAGES_DIR"/*/*.conf ]]; then
            default_name="${mfile#"$PACKAGES_DIR/"}"
            default_name="${default_name%.conf}"
        else
            default_name="$(basename "$mfile" .conf)"
        fi
    fi

    _preload_manifest_file "$mfile" "$default_name"

    pkg_name="${_CONF_PKG_NAME["$mfile"]:-$default_name}"
    pkg_bin="${_CONF_PKG_BIN["$mfile"]:-}"
    pkg_desc="${_CONF_PKG_DESC["$mfile"]:-}"
    pkg_scope="${_CONF_PKG_SCOPE["$mfile"]:-system}"
    pkg_install="${_CONF_PKG_INSTALL["$mfile"]:-}"
    pkg_opts="${_CONF_PKG_OPTS["$mfile"]:-}"
}

_package_is_active() {
    local mfile="$1"
    local default_pkg
    if [[ "$mfile" == "$PACKAGES_DIR"/*/*.conf ]]; then
        default_pkg="${mfile#"$PACKAGES_DIR/"}"
        default_pkg="${default_pkg%.conf}"
    else
        default_pkg="$(basename "$mfile" .conf)"
    fi

    _parse_manifest_file "$mfile" "$default_pkg"
    local rest="${pkg_install}${pkg_install:+ }${pkg_opts}"

    [[ "${_CONF_PKG_DECLINED["$default_pkg"]:-0}" -eq 1 || "${_CONF_PKG_DECLINED["$pkg_name"]:-0}" -eq 1 ]] && return 1
    [[ "$(_get_opt disabled "$rest")" == true ]] && return 1
    _eval_cond "" "$rest" || return 1

    local needs_spec="$(_get_opt needs "$rest")"
    if [[ -n "$needs_spec" ]]; then
        local need_item
        local saved_ifs="$IFS"
        IFS=','
        for need_item in $needs_spec; do
            need_item="$(_trim "$need_item")"
            [[ -z "$need_item" ]] && continue
            if [[ "${_CONF_PKG_DISABLED["$need_item"]:-0}" -eq 1 || "${_CONF_PKG_DECLINED["$need_item"]:-0}" -eq 1 ]]; then
                IFS="$saved_ifs"
                return 1
            fi
            local dep_conf
            dep_conf="$(_find_pkg_manifest "$need_item" 2>/dev/null)" || dep_conf=""
            if [[ -n "$dep_conf" && -n "${_CONF_PKG_OPTS["$dep_conf"]:-}" ]] && ! _eval_cond "" "${_CONF_PKG_OPTS["$dep_conf"]}"; then
                IFS="$saved_ifs"
                return 1
            fi
        done
        IFS="$saved_ifs"
    fi
    return 0
}


_get_opt() {
    local key="$1" opts="$2"
    if [[ "$opts" =~ (^|[[:space:]])"$key":\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
    elif [[ "$opts" =~ (^|[[:space:]])"$key":\'([^\']+)\' ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
    elif [[ "$opts" =~ (^|[[:space:]])"$key":([^[:space:]]+) ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
    fi
}


_prompt_confirm() {
    local msg="$1" default_yes="${2:-false}"
    if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
        [[ "$default_yes" == true ]] && return 0 || return 1
    fi
    local answer="" prompt_hint="" ind="${PROMPT_INDENT:-  }"
    if [[ "$default_yes" == true ]]; then
        prompt_hint="${CLR_MUTED}(${CLR_SUCCESS}${BOLD}Y${RESET}${CLR_MUTED}/n)${RESET}"
    else
        prompt_hint="${CLR_MUTED}(y/${CLR_WARN}${BOLD}N${RESET}${CLR_MUTED})${RESET}"
    fi
    _ui_bell
    printf '%s%s %s %s ' "$ind" "${CLR_PRIMARY}${SYM_Q}${RESET}" "${BOLD}${msg}${RESET}" "$prompt_hint" >&2
    if [[ ! -t 0 ]]; then
        read -r answer 2>/dev/null || true
    elif [[ -c /dev/tty ]]; then
        read -r answer < /dev/tty 2>/dev/null || read -r answer 2>/dev/null || true
    else
        read -r answer 2>/dev/null || true
    fi
    if [[ "$default_yes" == true ]]; then
        case "$answer" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    else
        case "$answer" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Return distro-specific package name, or the default name if none specified.
_resolve_pkg() {
    local default="$1" opts="$2" pm="$3"
    local key="$pm"
    [[ "$pm" == apt || "$pm" == apt-get ]] && key="apt"
    local override
    override="$(_get_opt "$key" "$opts")"
    printf '%s' "${override:-$default}"
}


