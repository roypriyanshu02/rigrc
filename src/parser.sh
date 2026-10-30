# shellcheck shell=bash
# =============================================================================
#  PARSER ENGINE (Condition Grammar & INI Manifests)
# =============================================================================

_in_cond_list() {
    [[ -n "$2" && ",${2//[[:space:]]/}," == *",$1,"* ]]
}

_check_cond_match() {
    local target="$1" list_str="$2"
    [[ -z "$list_str" ]] && return 1
    local clean_target="${target#arch:}"
    clean_target="${clean_target#env:}"
    _in_cond_list "$target" "$list_str" || _in_cond_list "$clean_target" "$list_str"
}

_UNMET_COND=""

# Evaluate cond field or cond: option. Returns 0 = proceed, 1 = skip.
_eval_cond() {
    local cond="$1" opts="${2:-}"
    if [[ -z "$cond" && -n "$opts" ]]; then
        _get_opt cond "$opts" >/dev/null || true
        cond="$OPT_REPLY"
    fi
    [[ -z "$cond" ]] && return 0

    if [[ "${_CONF_CASCADE_DONE:-0}" -eq 0 && -d "${PACKAGES_DIR:-}" ]]; then
        _preload_all_manifests "$PACKAGES_DIR"
    fi

    local cond_override="${_CONF_PKG_KEYS["global:cond"]:-${_CONF_PKG_KEYS["global:COND"]:-${COND:-}}}"
    local dis_cond_override="${_CONF_PKG_KEYS["global:disable_cond"]:-${_CONF_PKG_KEYS["global:DISABLE_COND"]:-${DISABLE_COND:-}}}"

    [[ -z "${_SYS_ARCH_CACHE:-}" || -z "${_SYS_ENV_CACHE:-}" ]] && _init_sys_info

    local c sys_arch sys_env _conds not_c
    sys_arch="${_SYS_ARCH_CACHE:-unknown}"
    sys_env="${_SYS_ENV_CACHE:-default}"
    IFS=',' read -ra _conds <<< "$cond"
    for c in "${_conds[@]}"; do
        c="${c#"${c%%[![:space:]]*}"}"
        c="${c%"${c##*[![:space:]]}"}"
        [[ -z "$c" ]] && continue

        if [[ "$c" == *"!"* ]]; then
            not_c="${c//!/}"
        else
            if [[ "$c" == "arch:"* ]]; then
                not_c="arch:!${c#arch:}"
            elif [[ "$c" == "env:"* ]]; then
                not_c="env:!${c#env:}"
            else
                not_c="!$c"
            fi
        fi

        if _check_cond_match "$c" "$dis_cond_override" || _check_cond_match "$not_c" "$cond_override"; then
            _UNMET_COND="$c"
            return 1
        fi

        if _check_cond_match "$c" "$cond_override"; then
            continue
        fi

        local bare_c="$c"
        bare_c="${bare_c#env:}"
        bare_c="${bare_c/env:/}"

        local passed=0
        case "$bare_c" in
            desktop)                              [[ "$sys_env" == "desktop" ]] && passed=1 ;;
            '!desktop')                           [[ "$sys_env" != "desktop" ]] && passed=1 ;;
            linux)                                [[ "${_SYS_OS_CACHE:-Linux}" == Linux ]] && passed=1 ;;
            '!linux')                             [[ "${_SYS_OS_CACHE:-Linux}" != Linux ]] && passed=1 ;;
            wsl)                                  _is_wsl && passed=1 ;;
            '!wsl')                               ! _is_wsl && passed=1 ;;
            vps)                                  [[ "$sys_env" == "vps" ]] && passed=1 ;;
            '!vps')                               [[ "$sys_env" != "vps" ]] && passed=1 ;;
            container)                            _is_container && passed=1 ;;
            '!container')                         ! _is_container && passed=1 ;;
            arch:x86_64|x86_64|arch:amd64|amd64)     [[ "$sys_arch" == x86_64 ]] && passed=1 ;;
            arch:!x86_64|!x86_64|arch:!amd64|!amd64) [[ "$sys_arch" != x86_64 ]] && passed=1 ;;
            arch:arm64|arm64|arch:aarch64|aarch64)   [[ "$sys_arch" == arm64 ]] && passed=1 ;;
            arch:!arm64|!arm64|arch:!aarch64|!aarch64) [[ "$sys_arch" != arm64 ]] && passed=1 ;;
            *)                                    log_warn "Unknown condition '$c'. Skipping package." ;;
        esac

        if [[ $passed -eq 0 ]]; then
            _UNMET_COND="$c"
            return 1
        fi
    done
    _UNMET_COND=""
    return 0
}

# Resolve the human-readable detected condition that caused a failure
_get_failed_cond_reason() {
    local cond="$1" opts="${2:-}"
    [[ -z "$cond" ]] && cond="$(_get_opt cond "$opts")"
    if [[ -z "$_UNMET_COND" && -n "$cond" ]]; then
        _eval_cond "$cond"
    fi
    local r="${_UNMET_COND:-unmet}"
    r="${r#!}"
    r="${r#env:}"
    r="${r#arch:}"
    printf '%s' "${r:-unmet}"
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
            if [[ -d "$gdir" ]]; then
                local gbname="${gdir##*/}"
                _GROUPS_LIST+=("$gbname")
            fi
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
            k="${k#"${k%%[![:space:]]*}"}"
            k="${k%"${k##*[![:space:]]}"}"
            v="${v#"${v%%[![:space:]]*}"}"
            v="${v%"${v##*[![:space:]]}"}"
            case "$k" in
                description) _GROUP_DESCS["$current_grp"]="$v" ;;
                packages)    _GROUP_PACKAGES_MAP["$current_grp"]="$v" ;;
                optional)    _GROUP_OPTIONAL["$current_grp"]="$v" ;;
            esac
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
        for p in ${pkgs_str//,/ }; do
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

    # Collect snippets from custom packages if selected or installed
    if [[ -n "${CUSTOM_PACKAGES_DIR:-}" && -d "$CUSTOM_PACKAGES_DIR" ]]; then
        local cconf
        for cconf in "$CUSTOM_PACKAGES_DIR"/*.conf "$CUSTOM_PACKAGES_DIR"/*/*.conf; do
            if [[ -f "$cconf" && "${cconf##*/}" != _* ]]; then
                local cpkg_name="${cconf##*/}"; cpkg_name="${cpkg_name%.conf}"
                local is_wanted=false
                if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
                    local op
                    for op in "${OPTIONAL_PACKAGES[@]}"; do
                        [[ "$op" == "$cpkg_name" ]] && { is_wanted=true; break; }
                    done
                else
                    is_wanted=true
                fi
                if [[ "$is_wanted" == true ]] && _package_is_active "$cconf"; then
                    printf '%s' "${_CONF_BASHRC["$cconf"]:-}"
                fi
            fi
        done
    fi
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

_group_selected() {
    local gname="$1"
    if [[ ${#INSTALL_GROUPS[@]} -gt 0 ]]; then
        [[ " ${INSTALL_GROUPS[*]} " == *" $gname "* ]] && return 0
    fi

    if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
        local g_pkgs="$(_get_group_meta "$gname" "packages")"
        if [[ -n "$g_pkgs" ]]; then
            local op
            for op in "${OPTIONAL_PACKAGES[@]}"; do
                if _in_cond_list "$op" "$g_pkgs"; then
                    return 0
                fi
            done
        fi
    fi

    if [[ ${#INSTALL_GROUPS[@]} -gt 0 ]]; then
        return 1
    fi

    local is_opt="$(_get_group_meta "$gname" "optional")"
    if [[ "$is_opt" == "false" || "$gname" == "core" ]]; then
        return 0
    fi
    return 1
}

_parse_section_header() {
    local _psh_raw="$1"
    local -n _out_type="$2"
    local -n _out_ident="$3"
    local -n _out_mod="$4"
    local -n _out_valid="$5"

    local _psh_hdr="${_psh_raw#"${_psh_raw%%[![:space:]]*}"}"
    _psh_hdr="${_psh_hdr%"${_psh_hdr##*[![:space:]]}"}"
    if [[ -z "$_psh_hdr" ]]; then
        _out_type="" _out_ident="" _out_mod="append" _out_valid=1
        return 0
    fi

    local _psh_stype="${_psh_hdr%%:*}"
    case "$_psh_stype" in
        package|config|bashrc|template|group) ;;
        *) _out_type="" _out_ident="" _out_mod="append" _out_valid=1; return 0 ;;
    esac

    local _psh_rest="${_psh_hdr#*:}"
    if [[ "$_psh_rest" == "$_psh_hdr" ]]; then
        _out_type="$_psh_stype" _out_ident="" _out_mod="append" _out_valid=0
        return 0
    fi

    if [[ "$_psh_stype" == "template" ]]; then
        local _psh_tident="${_psh_rest%%:*}"
        local _psh_tflags="${_psh_rest#*:}"
        [[ "$_psh_tflags" == "$_psh_rest" ]] && _psh_tflags="append"
        _psh_tflags="${_psh_tflags//:/ }"
        _out_type="template" _out_ident="$_psh_tident" _out_mod="$_psh_tflags" _out_valid=0
        return 0
    fi

    local _psh_parts=()
    IFS=':' read -ra _psh_parts <<< "$_psh_rest"
    local _psh_n=${#_psh_parts[@]}
    local _psh_ident="" _psh_mod="append" _psh_valid=0

    if [[ $_psh_n -eq 1 ]]; then
        case "${_psh_parts[0]}" in
            append|override|disable|once) _psh_mod="${_psh_parts[0]}" ;;
            *) _psh_ident="${_psh_parts[0]}" ;;
        esac
    elif [[ $_psh_n -eq 2 ]]; then
        _psh_ident="${_psh_parts[0]}"
        case "${_psh_parts[1]}" in
            append|override|disable|once) _psh_mod="${_psh_parts[1]}" ;;
            *) _psh_mod="${_psh_parts[1]}"; _psh_valid=1 ;;
        esac
    else
        _psh_valid=1
    fi

    _psh_ident="${_psh_ident%.conf}"
    _psh_ident="${_psh_ident#.}"
    if [[ "$_psh_ident" == *config && "$_psh_ident" != "config" && "$_psh_ident" != */* && "$_psh_ident" != *"-"* ]]; then
        _psh_ident="${_psh_ident%config}"
    fi

    _out_type="$_psh_stype" _out_ident="$_psh_ident" _out_mod="$_psh_mod" _out_valid="$_psh_valid"
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
    local cur_tmpl_buf="" in_tmpl=false cur_last_key=""
    local raw_line line

    _flush_tmpl() {
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
    }

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            local header="${BASH_REMATCH[1]}"
            local sec_type="" sec_ident="" sec_mod="" is_valid=0
            _parse_section_header "$header" sec_type sec_ident sec_mod is_valid

            if [[ "$is_valid" -eq 0 ]]; then
                _flush_tmpl
                cur_type="$sec_type"
                cur_ident="${sec_ident:-$default_pkg}"
                cur_mod="$sec_mod"
                cur_last_key=""

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
                key="${key#"${key%%[![:space:]]*}"}"
                key="${key%"${key##*[![:space:]]}"}"
                key="${key,,}"
                val="${val#"${val%%[![:space:]]*}"}"
                val="${val%"${val##*[![:space:]]}"}"
                if [[ "$val" == "!delete" ]]; then
                    unset "_CONF_PKG_KEYS[${cur_ident}:${key}]"
                    cur_last_key=""
                else
                    _CONF_PKG_KEYS["${cur_ident}:${key}"]="$val"
                    cur_last_key="$key"
                fi
            elif [[ -n "${cur_last_key:-}" ]]; then
                local cont_val="${line#"${line%%[![:space:]]*}"}"
                cont_val="${cont_val%"${cont_val##*[![:space:]]}"}"
                if [[ -n "$cont_val" ]]; then
                    local existing="${_CONF_PKG_KEYS["${cur_ident}:${cur_last_key}"]:-}"
                    if [[ "$existing" == *"," ]]; then
                        _CONF_PKG_KEYS["${cur_ident}:${cur_last_key}"]="${existing} ${cont_val}"
                    else
                        _CONF_PKG_KEYS["${cur_ident}:${cur_last_key}"]="${existing}, ${cont_val}"
                    fi
                fi
            fi
        fi
    done < "$file"

    _flush_tmpl
}

_finalize_conf_caches() {
    local pdir="$1"
    [[ ! -d "$pdir" ]] && return 0

    local conf_file
    for conf_file in "$pdir"/*.conf "$pdir"/*/*.conf; do
        [[ ! -f "$conf_file" || "${conf_file##*/}" == _* ]] && continue
        local pkg group target_key
        pkg="${conf_file##*/}"; pkg="${pkg%.conf}"
        group="${conf_file%/*}"; group="${group##*/}"
        target_key="${group}/${pkg}"

        local p_name="${_CONF_PKG_KEYS["${pkg}:name"]:-${_CONF_PKG_KEYS["${target_key}:name"]:-$pkg}}"
        local p_bin="${_CONF_PKG_KEYS["${pkg}:binaries"]:-${_CONF_PKG_KEYS["${target_key}:binaries"]:-${_CONF_PKG_KEYS["${pkg}:bin"]:-${_CONF_PKG_KEYS["${target_key}:bin"]:-$pkg}}}}"
        local p_desc="${_CONF_PKG_KEYS["${pkg}:description"]:-${_CONF_PKG_KEYS["${target_key}:description"]:-${_CONF_PKG_KEYS["${pkg}:desc"]:-${_CONF_PKG_KEYS["${target_key}:desc"]:-}}}}"
        local p_scope="${_CONF_PKG_KEYS["${pkg}:system"]:-${_CONF_PKG_KEYS["${target_key}:system"]:-${_CONF_PKG_KEYS["${pkg}:scope"]:-${_CONF_PKG_KEYS["${target_key}:scope"]:-system}}}}"

        local inst_specs="" pm tool
        for pm in apt dnf pacman apk; do
            local val="${_CONF_PKG_KEYS["${pkg}:${pm}"]:-${_CONF_PKG_KEYS["${target_key}:${pm}"]:-}}"
            [[ -n "$val" ]] && inst_specs+="${pm}:${val} "
        done
        for tool in mise uv cargo go bun npm flatpak brew cmd; do
            local spec="${_CONF_PKG_KEYS["${pkg}:${tool}"]:-${_CONF_PKG_KEYS["${target_key}:${tool}"]:-}}"
            [[ -n "$spec" ]] && inst_specs+="${tool}:\"${spec}\" "
        done
        local p_install="${_CONF_PKG_KEYS["${pkg}:install"]:-${_CONF_PKG_KEYS["${target_key}:install"]:-}}"
        [[ -n "$p_install" ]] && inst_specs+="${p_install} "

        local cond_val="${_CONF_PKG_KEYS["${pkg}:cond"]:-${_CONF_PKG_KEYS["${target_key}:cond"]:-}}"
        local alt_val="${_CONF_PKG_KEYS["${pkg}:alt"]:-${_CONF_PKG_KEYS["${target_key}:alt"]:-}}"
        local needs_val="${_CONF_PKG_KEYS["${pkg}:needs"]:-${_CONF_PKG_KEYS["${target_key}:needs"]:-}}"
        local opt_val="${_CONF_PKG_KEYS["${pkg}:optional"]:-${_CONF_PKG_KEYS["${target_key}:optional"]:-}}"
        local rec_val="${_CONF_PKG_KEYS["${pkg}:recommended"]:-${_CONF_PKG_KEYS["${target_key}:recommended"]:-${_CONF_PKG_KEYS["${pkg}:rec"]:-${_CONF_PKG_KEYS["${target_key}:rec"]:-}}}}"
        local dis_val="${_CONF_PKG_KEYS["${pkg}:disabled"]:-${_CONF_PKG_KEYS["${target_key}:disabled"]:-}}"
        local p_opts="${_CONF_PKG_KEYS["${pkg}:options"]:-${_CONF_PKG_KEYS["${target_key}:options"]:-}}"

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

        inst_specs="${inst_specs#"${inst_specs%%[![:space:]]*}"}"
        inst_specs="${inst_specs%"${inst_specs##*[![:space:]]}"}"
        _CONF_PKG_INSTALL["$conf_file"]="$inst_specs"

        opt_specs="${opt_specs#"${opt_specs%%[![:space:]]*}"}"
        opt_specs="${opt_specs%"${opt_specs##*[![:space:]]}"}"
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
        local bname="${cfg##*/}"
        [[ "$bname" == "example.conf" ]] && continue
        available_configs+=("$bname")
    done

    if [[ ${#available_configs[@]} -eq 0 ]]; then
        CONFIG_FILE=""
    elif [[ ${#available_configs[@]} -eq 1 ]]; then
        CONFIG_FILE="$sdir/${available_configs[0]}"
    else
        if [[ "${NON_INTERACTIVE:-false}" == false ]]; then
            local choice
            choice="$(_ui_select "Multiple configuration files found. Select environment:" "${available_configs[@]}")"
            CONFIG_FILE="$sdir/${choice}"
        else
            CONFIG_FILE="$sdir/${available_configs[0]}"
        fi
    fi
}

_preload_all_manifests() {
    local pdir="${1:-$PACKAGES_DIR}"
    [[ "$_CONF_CASCADE_DONE" -eq 1 ]] && return 0
    _CONF_CASCADE_DONE=1

    _init_sys_info
    _select_config_file
    _preload_groups_conf

    _CONF_PKG_KEYS=()
    _CONF_PKG_DISABLED=()
    _CONF_PKG_DECLINED=()
    _CONF_BASHRC_BUF=()
    _CONF_BASHRC_DIS=()
    _CONF_TMPL_BUF=()
    _CONF_TMPL_DIS=()

    # Layer 1: Base configuration (src/base.conf)
    local layer1="$SCRIPT_DIR/src/base.conf"
    if [[ ! -f "$layer1" && -f "$SCRIPT_DIR/base.conf" ]]; then
        layer1="$SCRIPT_DIR/base.conf"
    fi
    if [[ -f "$layer1" ]]; then
        _parse_single_conf_file "$layer1" "global"
    fi

    # Layer 2: packages/*/*.conf
    if [[ -d "$pdir" ]]; then
        local conf_file
        for conf_file in "$pdir"/*/*.conf; do
            if [[ -f "$conf_file" ]]; then
                local pkg_default
                pkg_default="$(_get_default_pkg_name "$conf_file")"
                _parse_single_conf_file "$conf_file" "$pkg_default"
            fi
        done
    fi

    # Layer 3: $CONFIG_FILE (selected or custom user config)
    if [[ -n "${CONFIG_FILE:-}" && -f "${CONFIG_FILE:-}" && "$CONFIG_FILE" != "$layer1" ]]; then
        _parse_single_conf_file "$CONFIG_FILE" "global"
    fi

    # Resolve custom packages directory (from config if not overridden by CLI)
    if [[ -z "${CUSTOM_PACKAGES_DIR:-}" && -n "${_CONF_PKG_KEYS["global:custom_packages_dir"]:-}" ]]; then
        local raw_cpd="${_CONF_PKG_KEYS["global:custom_packages_dir"]}"
        raw_cpd="${raw_cpd%\"}"; raw_cpd="${raw_cpd#\"}"
        raw_cpd="${raw_cpd%\'}"; raw_cpd="${raw_cpd#\'}"
        if [[ "$raw_cpd" == /* || "$raw_cpd" == ~* ]]; then
            CUSTOM_PACKAGES_DIR="${raw_cpd/#\~/$HOME}"
        elif [[ -n "${CONFIG_FILE:-}" && -f "$CONFIG_FILE" ]]; then
            local cfg_dir
            cfg_dir="$(cd "$(dirname "$CONFIG_FILE")" 2>/dev/null && pwd)"
            CUSTOM_PACKAGES_DIR="${cfg_dir:-$PWD}/$raw_cpd"
        else
            CUSTOM_PACKAGES_DIR="$PWD/$raw_cpd"
        fi
    fi

    # Preload custom package manifests from CUSTOM_PACKAGES_DIR
    if [[ -n "${CUSTOM_PACKAGES_DIR:-}" && -d "$CUSTOM_PACKAGES_DIR" ]]; then
        local cconf
        for cconf in "$CUSTOM_PACKAGES_DIR"/*.conf "$CUSTOM_PACKAGES_DIR"/*/*.conf; do
            if [[ -f "$cconf" && "${cconf##*/}" != _* ]]; then
                local cpkg_default
                cpkg_default="$(_get_default_pkg_name "$cconf")"
                _parse_single_conf_file "$cconf" "$cpkg_default"
            fi
        done
    fi

    if [[ -n "${_CONF_PKG_KEYS["global:groups"]:-}" ]]; then
        local raw_ig="${_CONF_PKG_KEYS["global:groups"]//[()]/}"
        INSTALL_GROUPS=()
        read -ra INSTALL_GROUPS <<< "${raw_ig//,/ }"
    fi

    if [[ -n "${_CONF_PKG_KEYS["global:exclude"]:-}" ]]; then
        local raw_ep="${_CONF_PKG_KEYS["global:exclude"]//[()]/}"
        local ep
        for ep in ${raw_ep//,/ }; do
            [[ -n "$ep" ]] && _CONF_PKG_DISABLED["$ep"]=1
        done
    fi

    if [[ -n "${_CONF_PKG_KEYS["global:packages"]:-}" ]]; then
        local raw_ip="${_CONF_PKG_KEYS["global:packages"]//[()]/}"
        OPTIONAL_PACKAGES=()
        read -ra OPTIONAL_PACKAGES <<< "${raw_ip//,/ }"
    fi

    _finalize_conf_caches "$pdir"
    if [[ -n "${CUSTOM_PACKAGES_DIR:-}" && -d "$CUSTOM_PACKAGES_DIR" ]]; then
        _finalize_conf_caches "$CUSTOM_PACKAGES_DIR"
    fi
}

_get_default_pkg_name() {
    local mfile="$1"
    if [[ "$mfile" == "$PACKAGES_DIR"/*/*.conf ]]; then
        local rel="${mfile#"$PACKAGES_DIR/"}"
        printf '%s' "${rel%.conf}"
    else
        local b="${mfile##*/}"
        printf '%s' "${b%.conf}"
    fi
}

_preload_manifest_file() {
    local mfile="$1"
    local default_name="${2:-$(_get_default_pkg_name "$mfile")}"

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
    local default_name="${2:-$(_get_default_pkg_name "$mfile")}"

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
        local rel="${mfile#"$PACKAGES_DIR/"}"
        default_pkg="${rel%.conf}"
    else
        local b="${mfile##*/}"
        default_pkg="${b%.conf}"
    fi

    _parse_manifest_file "$mfile" "$default_pkg"
    local rest="${pkg_install}${pkg_install:+ }${pkg_opts}"

    [[ "${_CONF_PKG_DECLINED["$default_pkg"]:-0}" -eq 1 || "${_CONF_PKG_DECLINED["$pkg_name"]:-0}" -eq 1 ]] && return 1
    _get_opt disabled "$rest" >/dev/null || true
    [[ "$OPT_REPLY" == true ]] && return 1
    _eval_cond "" "$rest" || return 1

    _get_opt needs "$rest" >/dev/null || true
    local needs_spec="$OPT_REPLY"
    if [[ -n "$needs_spec" ]]; then
        local need_item
        local saved_ifs="$IFS"
        IFS=','
        for need_item in $needs_spec; do
            need_item="${need_item#"${need_item%%[![:space:]]*}"}"
            need_item="${need_item%"${need_item##*[![:space:]]}"}"
            [[ -z "$need_item" ]] && continue
            if [[ "${_CONF_PKG_DISABLED["$need_item"]:-0}" -eq 1 || "${_CONF_PKG_DECLINED["$need_item"]:-0}" -eq 1 ]]; then
                IFS="$saved_ifs"
                return 1
            fi
            if _find_pkg_manifest "$need_item" >/dev/null 2>&1; then
                local dep_conf="$REPLY"
                if [[ -n "$dep_conf" && -n "${_CONF_PKG_OPTS["$dep_conf"]:-}" ]]; then
                    if ! _eval_cond "" "${_CONF_PKG_OPTS["$dep_conf"]}"; then
                        IFS="$saved_ifs"
                        return 1
                    fi
                fi
            fi
        done
        IFS="$saved_ifs"
    fi
    return 0
}

_get_opt() {
    local key="$1" opts="$2"
    OPT_REPLY=""
    local re1="(^|[[:space:]])${key}:\"([^\"]+)\""
    local re2="(^|[[:space:]])${key}:'([^']+)'"
    local re3="(^|[[:space:]])${key}:([^[:space:]]+)"
    if [[ "$opts" =~ $re1 || "$opts" =~ $re2 || "$opts" =~ $re3 ]]; then
        OPT_REPLY="${BASH_REMATCH[2]}"
        printf '%s' "$OPT_REPLY"
    fi
    return 0
}

_prompt_confirm() {
    local msg="$1" default_yes="${2:-false}"
    if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
        [[ "$default_yes" == true ]] && return 0 || return 1
    fi
    local answer="" ind="${PROMPT_INDENT:-  }"
    local prompt_hint="${CLR_MUTED}[y/N]${RESET}"
    [[ "$default_yes" == true ]] && prompt_hint="${CLR_MUTED}[Y/n]${RESET}"
    _ui_bell
    printf '%s%s %s %s: ' "$ind" "${CLR_PRIMARY}${SYM_Q}${RESET}" "${msg}" "$prompt_hint" >&2
    if [[ ! -t 0 ]]; then
        read -r answer 2>/dev/null || true
    elif [[ -c /dev/tty ]]; then
        read -r answer < /dev/tty 2>/dev/null || read -r answer 2>/dev/null || true
    else
        read -r answer 2>/dev/null || true
    fi
    local res_code=1
    if [[ "$default_yes" == true ]]; then
        [[ "$answer" =~ ^[nN] ]] && res_code=1 || res_code=0
    else
        [[ "$answer" =~ ^[yY] ]] && res_code=0 || res_code=1
    fi
    if [[ -t 2 && -c /dev/tty ]]; then
        local disp_ans="${CLR_MUTED}${SYM_ARROW} no${RESET}"
        [[ $res_code -eq 0 ]] && disp_ans="${CLR_SUCCESS}${SYM_ARROW} yes${RESET}"
        printf '\033[1A\033[2K%s%-24s %s\n' "$ind" "${msg}" "$disp_ans" >&2
    fi
    return $res_code
}

# Return distro-specific package name, or the default name if none specified.
_resolve_pkg() {
    local default="$1" opts="$2" pm="$3"
    local key="$pm"
    [[ "$pm" == apt || "$pm" == apt-get ]] && key="apt"
    _get_opt "$key" "$opts" >/dev/null || true
    local override="$OPT_REPLY"
    printf '%s' "${override:-$default}"
}


