# shellcheck shell=bash
# =============================================================================
#  INSTALLER ENGINE (Package Managers & Batch Queue)
# =============================================================================

_is_file_locked() {
    local f="$1"
    [[ ! -f "$f" ]] && return 1

    # Check if file contains a numeric PID and whether that PID is alive
    if [[ -r "$f" ]]; then
        local pid_val=""
        pid_val="$(head -n 1 "$f" 2>/dev/null || true)"
        pid_val="${pid_val#"${pid_val%%[![:space:]]*}"}"; pid_val="${pid_val%"${pid_val##*[![:space:]]}"}"
        if [[ -n "$pid_val" && "$pid_val" =~ ^[0-9]+$ ]]; then
            if kill -0 "$pid_val" 2>/dev/null || { sudo -n true 2>/dev/null && sudo kill -0 "$pid_val" 2>/dev/null; }; then
                return 0
            else
                # Stale PID file left behind by crashed/abruptly killed process
                return 1
            fi
        fi
    fi

    # 2. Check fuser: verify non-empty PID output (BSD fuser returns 0 even on no match)
    if command -v fuser >/dev/null 2>&1; then
        local fuser_out=""
        fuser_out="$(fuser "$f" 2>/dev/null || true)"
        if [[ -z "$fuser_out" ]] && sudo -n true 2>/dev/null; then
            fuser_out="$(sudo -n fuser "$f" 2>/dev/null || true)"
        fi
        [[ -n "$fuser_out" ]] && return 0
        return 1
    fi

    # 3. Check flock (standard utility for flock/fcntl locks)
    if command -v flock >/dev/null 2>&1; then
        if ! flock -n "$f" -c true >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    return 1
}

_wait_for_pm_lock() {
    local pm="${1:-${_PM:-}}"
    local max_wait="${2:-30}"
    local waited=0
    [[ "$DRY_RUN" == true || -z "$pm" || "$pm" == "unknown" ]] && return 0

    local lock_files=()
    case "$pm" in
        apt|apt-get)
            lock_files=(
                "/var/lib/dpkg/lock-frontend"
                "/var/lib/dpkg/lock"
                "/var/lib/apt/lists/lock"
                "/var/cache/apt/archives/lock"
            ) ;;
        pacman)
            lock_files=("/var/lib/pacman/db.lck") ;;
        dnf)
            lock_files=("/var/run/dnf.pid" "/var/lib/dnf/lock") ;;
        apk)
            lock_files=("/lib/apk/db/lock") ;;
        zypper)
            lock_files=("/var/run/zypp.pid") ;;
        *) return 0 ;;
    esac

    while [[ $waited -lt $max_wait ]]; do
        local locked=false lf
        if [[ "$pm" == "pacman" && -f "/var/lib/pacman/db.lck" ]]; then
            if command -v pgrep >/dev/null 2>&1 && ! pgrep -x pacman >/dev/null 2>&1; then
                log_warn "Stale pacman lock file detected (/var/lib/pacman/db.lck with no active pacman process). Proceeding."
                return 0
            fi
            locked=true
        else
            for lf in "${lock_files[@]}"; do
                if _is_file_locked "$lf"; then
                    locked=true
                    break
                fi
            done
        fi

        [[ "$locked" == false ]] && return 0
        [[ $waited -eq 0 ]] && log_warn "Waiting for package manager lock to release (${pm})..."
        sleep 2
        waited=$(( waited + 2 ))
    done

    log_warn "Package manager lock still held after ${max_wait}s. Proceeding anyway."
    return 0
}

# Wrapper: eval a script-method install command with retry and timeout.
_run_script() {
    local raw_cmd="$1"
    local label="${2:-Script install}"
    local timeout_val="${3:-}"
    [[ -z "$timeout_val" || ! "$timeout_val" =~ ^[0-9]+$ ]] && timeout_val="${INSTALL_TIMEOUT:-300}"
    local SPINNER_INDENT="${SPINNER_INDENT:-      }"
    if [[ "$VERIFY_SCRIPTS" == true || "${REVIEW_INSTALL_SCRIPTS:-false}" == true ]]; then
        log_info "Script target: $label"
        log_info "Command: $raw_cmd"
        if [[ "$NON_INTERACTIVE" != true ]]; then
            _ui_bell
            local _confirm=""
            read -r -p "Run this installation script? [y/N] " _confirm < /dev/tty || _confirm="n"
            if [[ "$_confirm" != [yY]* ]]; then
                log_warn "Skipped $label script."
                return 0
            fi
        fi
    fi
    local runner=()
    command -v timeout >/dev/null 2>&1 && runner=(timeout "${timeout_val}")
    local s_rc=0
    _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "$label" "${runner[@]}" bash -c "set -o pipefail; $raw_cmd" || s_rc=$?
    if [[ $s_rc -eq 124 && -z "${_LAST_CMD_ERROR:-}" ]]; then
        _LAST_CMD_ERROR="Command timed out after ${timeout_val}s"
    fi
    return $s_rc
}



# ---------------------------------------------------------------------------
# Package installation
# Reads packages.conf; installs missing packages in batch per group.
# ---------------------------------------------------------------------------

# Update package manager index and upgrade installed packages.
_upgrade_system() {
    [[ "${SKIP_UPGRADE:-false}" == true ]] && { log_info "Skipping package upgrade (--skip-upgrade)."; return 0; }
    _PM="${_PM:-$(_detect_pm)}"
    [[ "$_PM" == unknown ]] && return 0

    if [[ "$DRY_RUN" == true ]]; then
        log_action "Would update, upgrade, and clean packages via ${_PM}"
        return 0
    fi

    _wait_for_pm_lock "$_PM"

    case "$_PM" in
        apt|apt-get)
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Updating package index (${_PM})" _sudo apt update -qq || true
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Upgrading packages (${_PM})" _sudo apt upgrade -y -qq
            _run_with_spinner "Removing unused packages (${_PM})" _sudo apt autoremove -y -qq || true
            ;;
        dnf)
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Upgrading packages (${_PM})" _sudo dnf upgrade -y
            _run_with_spinner "Removing unused packages (${_PM})" _sudo dnf autoremove -y || true
            ;;
        pacman)
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Updating package index (${_PM})" _sudo pacman -Sy --noconfirm || true
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Upgrading packages (${_PM})" _sudo pacman -Su --noconfirm
            ;;
        apk)
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Updating package index (${_PM})" _sudo apk update || true
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Upgrading packages (${_PM})" _sudo apk upgrade --no-cache
            ;;
        zypper)
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Updating package index (${_PM})" _sudo zypper ref || true
            _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "Upgrading packages (${_PM})" _sudo zypper dup -y
            ;;
    esac
}

_find_pkg_manifest() {
    local target="$1"
    local pdir="${PACKAGES_DIR:-$SCRIPT_DIR/packages}"
    local cand

    # Check custom packages directory first if configured
    if [[ -n "${CUSTOM_PACKAGES_DIR:-}" && -d "$CUSTOM_PACKAGES_DIR" ]]; then
        if [[ -f "$CUSTOM_PACKAGES_DIR/${target}.conf" ]]; then
            REPLY="$CUSTOM_PACKAGES_DIR/${target}.conf"
            printf '%s' "$REPLY"
            return 0
        fi
        for cand in "$CUSTOM_PACKAGES_DIR"/*/"${target}.conf"; do
            if [[ -f "$cand" ]]; then
                REPLY="$cand"
                printf '%s' "$cand"
                return 0
            fi
        done
    fi

    for cand in "$pdir"/*/"${target}.conf"; do
        if [[ -f "$cand" ]]; then
            REPLY="$cand"
            printf '%s' "$cand"
            return 0
        fi
    done
    REPLY=""
    return 1
}

_resolve_missing_dependency() {
    local parent_pkg="$1"
    local dep="$2"

    if _check_bins_scoped "$dep" "any"; then
        return 0
    fi

    if [[ "${_DEP_RESOLVE_STACK["$dep"]:-0}" -eq 1 ]]; then
        log_warn "Circular dependency detected resolving '${dep}' for '${parent_pkg}'. Skipping."
        _CONF_PKG_DECLINED["$parent_pkg"]=1
        return 1
    fi

    local dep_conf
    dep_conf="$(_find_pkg_manifest "$dep")" || dep_conf=""

    if [[ -z "$dep_conf" ]]; then
        log_warn "Skipping '${parent_pkg}': required external dependency '${dep}' is not installed."
        _CONF_PKG_DECLINED["$parent_pkg"]=1
        return 1
    fi

    if [[ -n "${_CONF_PKG_OPTS["$dep_conf"]:-}" ]] && ! _eval_cond "" "${_CONF_PKG_OPTS["$dep_conf"]}"; then
        log_warn "Skipping '${parent_pkg}': required dependency '${dep}' is unavailable in current environment."
        _CONF_PKG_DECLINED["$parent_pkg"]=1
        return 1
    fi

    if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
        log_warn "Skipping '${parent_pkg}': required dependency '${dep}' is not installed."
        _CONF_PKG_DECLINED["$parent_pkg"]=1
        return 1
    fi

    _ui_bell
    if _prompt_confirm "'${parent_pkg}' requires '${dep}' (skipped). Install '${dep}' now?" true; then
        log_info "Installing missing prerequisite '${dep}' for '${parent_pkg}'..."
        _CONF_PKG_DECLINED["$dep"]=0
        _CONF_PKG_DISABLED["$dep"]=0
        _DEP_RESOLVE_STACK["$dep"]=1
        _install_single_package "$dep_conf" "$dep"
        _DEP_RESOLVE_STACK["$dep"]=0
        if _check_bins_scoped "$dep" "any"; then
            return 0
        else
            log_warn "Prerequisite '${dep}' installation failed. Skipping '${parent_pkg}'."
            _CONF_PKG_DECLINED["$parent_pkg"]=1
            return 1
        fi
    else
        log_warn "Skipping '${parent_pkg}' because prerequisite '${dep}' was declined."
        _CONF_PKG_DECLINED["$parent_pkg"]=1
        return 1
    fi
}

_install_single_package() {
    local conf_file="$1"
    local cpkg="$2"
    [[ ! -f "$conf_file" ]] && return 0

    _parse_manifest_file "$conf_file" "$cpkg"

    local pkg_id="$pkg_name"
    local bin="${pkg_bin:-$pkg_id}"
    local scope="$pkg_scope"
    local rest="${pkg_install}${pkg_install:+ }${pkg_opts}"

    local pm_key="${_PM:-}"
    [[ "$pm_key" == "apt-get" ]] && pm_key="apt"
    local group="${conf_file%/*}"; group="${group##*/}"
    local target_key="${group}/${pkg_id}"
    local pm_cmd="${_CONF_PKG_KEYS["${target_key}:${pm_key}.cmd"]:-${_CONF_PKG_KEYS["${pkg_id}:${pm_key}.cmd"]:-${_CONF_PKG_KEYS["${cpkg}:${pm_key}.cmd"]:-}}}"
    [[ -z "$pm_cmd" ]] && pm_cmd="$(_get_opt "${pm_key}.cmd" "$rest")"
    local scmd="${pm_cmd:-${_CONF_PKG_KEYS["${target_key}:cmd"]:-${_CONF_PKG_KEYS["${pkg_id}:cmd"]:-${_CONF_PKG_KEYS["${cpkg}:cmd"]:-}}}}"
    [[ -z "$scmd" ]] && scmd="${pm_cmd:-$(_get_opt cmd "$rest")}"
    local mise_spec="$(_get_opt mise "$rest")"
    local uv_spec="$(_get_opt uv "$rest")"
    local cargo_spec="$(_get_opt cargo "$rest")"
    local go_spec="$(_get_opt go "$rest")"
    local bun_spec="$(_get_opt bun "$rest")"
    local npm_spec="$(_get_opt npm "$rest")"
    local flatpak_spec="$(_get_opt flatpak "$rest")"
    local brew_spec="$(_get_opt brew "$rest")"

    local provider="script"
    if [[ -z "$scmd" ]]; then
        if [[ -n "$mise_spec" ]]; then
            provider="mise"
            [[ "$mise_spec" != *":"* && "$mise_spec" == *"/"* ]] && mise_spec="github:${mise_spec}"
            scmd="command -v mise >/dev/null 2>&1 && mise use -g ${mise_spec} || \"\$HOME/.local/bin/mise\" use -g ${mise_spec}"
        elif [[ -n "$uv_spec" ]]; then
            provider="uv"
            scmd="\"${HOME}/.local/bin/uv\" tool install ${uv_spec} 2>/dev/null || uv tool install ${uv_spec}"
        elif [[ -n "$cargo_spec" ]]; then
            provider="cargo"
            scmd="if command -v cargo-binstall >/dev/null 2>&1; then cargo binstall --no-confirm ${cargo_spec}; else cargo install ${cargo_spec}; fi"
        elif [[ -n "$go_spec" ]]; then
            provider="go"
            [[ "$go_spec" != *"@"* ]] && go_spec="${go_spec}@latest"
            scmd="go install ${go_spec}"
        elif [[ -n "$bun_spec" ]]; then
            provider="bun"
            scmd="bun add -g ${bun_spec}"
        elif [[ -n "$npm_spec" ]]; then
            provider="npm"
            scmd="npm install -g ${npm_spec}"
        elif [[ -n "$flatpak_spec" ]]; then
            provider="flatpak"
            scmd="flatpak install --user -y ${flatpak_spec}"
        elif [[ -n "$brew_spec" ]]; then
            provider="brew"
            scmd="brew install ${brew_spec}"
        fi
    fi

    # Determine native vs script
    local is_native=false
    local resolved=""
    case "$scope" in
        system|native)
            if [[ -z "$pm_cmd" ]]; then
                local pm_pkg="$(_get_opt "$pm_key" "$rest")"
                if [[ -n "$pm_pkg" || -z "$scmd" ]]; then
                    resolved="$(_resolve_pkg "$pkg_id" "$rest" "$_PM")"
                    if [[ "$resolved" != "none" && "$resolved" != ":none" && "$resolved" != "skip" && "$resolved" != "!"* ]]; then
                        is_native=true
                    fi
                fi
            fi
            ;;
    esac

    # Check needs dependency prerequisites with forgiving interactive fallback
    local needs_spec="$(_get_opt needs "$rest")"
    if [[ -n "$needs_spec" ]]; then
        local need_item
        local saved_ifs="$IFS"
        IFS=','
        for need_item in $needs_spec; do
            need_item="${need_item#"${need_item%%[![:space:]]*}"}"
            need_item="${need_item%"${need_item##*[![:space:]]}"}"
            [[ -z "$need_item" ]] && continue
            if ! _resolve_missing_dependency "$pkg_id" "$need_item"; then
                IFS="$saved_ifs"
                return 0
            fi
        done
        IFS="$saved_ifs"
    fi

    # 1. Install package if binary is not present in declared scope
    if ! _check_bins_scoped "$bin" "$scope"; then
        # Run prep hook if present
        local prep_cmd="${_CONF_PKG_KEYS["${target_key}:${pm_key}.prep"]:-${_CONF_PKG_KEYS["${pkg_id}:${pm_key}.prep"]:-${_CONF_PKG_KEYS["${cpkg}:${pm_key}.prep"]:-${_CONF_PKG_KEYS["${target_key}:prep"]:-${_CONF_PKG_KEYS["${pkg_id}:prep"]:-${_CONF_PKG_KEYS["${cpkg}:prep"]:-}}}}}}"
        [[ -z "$prep_cmd" ]] && prep_cmd="$(_get_opt "${pm_key}.prep" "$rest")"
        [[ -z "$prep_cmd" ]] && prep_cmd="$(_get_opt prep "$rest")"
        if [[ -n "$prep_cmd" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                [[ "$VERBOSE" == true ]] && log_action "    prep: $prep_cmd"
            else
                if [[ "$VERBOSE" == true ]]; then
                    SPINNER_INDENT="      " _run_script "$prep_cmd" "prep: $prep_cmd" || log_warn "Prep hook failed for '$pkg_id'."
                else
                    bash -c "$prep_cmd" >/dev/null 2>&1 || log_warn "Prep hook failed for '$pkg_id'."
                fi
            fi
        fi

        local install_success=false
        if [[ "$is_native" == true ]]; then
            local -a install_cmd=()
            case "$_PM" in
                apt|apt-get) install_cmd=(_sudo apt install -y -qq) ;;
                dnf)         install_cmd=(_sudo dnf install -y) ;;
                pacman)      install_cmd=(_sudo pacman -Sy --noconfirm) ;;
                zypper)      install_cmd=(_sudo zypper install -y) ;;
                apk)         install_cmd=(_sudo apk add --no-cache) ;;
            esac
            if [[ "$DRY_RUN" == true ]]; then
                log_success "$pkg_id (${_PM})"
                install_success=true
            else
                if [[ ${#install_cmd[@]} -gt 0 ]]; then
                    _wait_for_pm_lock "$_PM"
                    if SPINNER_INDENT="  " _run_retry "$MAX_RETRIES" "$RETRY_DELAY" "${pkg_id} (${_PM})" "${install_cmd[@]}" "$resolved"; then
                        install_success=true
                    else
                        log_warn "Failed to install '${pkg_id}' via ${_PM}."
                    fi
                fi
            fi
        fi

        # Script or fallback installation
        if [[ "$install_success" == false && -n "$scmd" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_success "$pkg_id (${provider})"
            else
                local pkg_timeout="${_CONF_PKG_KEYS["${pkg_id}:timeout"]:-${_CONF_PKG_KEYS["${target_key}:timeout"]:-${_CONF_PKG_KEYS["${cpkg}:timeout"]:-$(_get_opt timeout "$rest")}}}"
                if SPINNER_INDENT="  " _run_script "$scmd" "${pkg_id} (${provider})" "${pkg_timeout:-$INSTALL_TIMEOUT}"; then
                    install_success=true
                else
                    log_warn "Failed to install '${pkg_id}' via ${provider}."
                fi
            fi
        fi

        local post_cmd="${_CONF_PKG_KEYS["${target_key}:${pm_key}.post"]:-${_CONF_PKG_KEYS["${pkg_id}:${pm_key}.post"]:-${_CONF_PKG_KEYS["${cpkg}:${pm_key}.post"]:-${_CONF_PKG_KEYS["${target_key}:post"]:-${_CONF_PKG_KEYS["${pkg_id}:post"]:-${_CONF_PKG_KEYS["${cpkg}:post"]:-}}}}}}"
        [[ -z "$post_cmd" ]] && post_cmd="$(_get_opt "${pm_key}.post" "$rest")"
        [[ -z "$post_cmd" ]] && post_cmd="$(_get_opt post "$rest")"

        local proceed_post=true
        if [[ "$install_success" == false ]]; then
            _FAILED_PACKAGES+=("$pkg_id")
            _FAILURE_REASONS["$pkg_id"]="${_LAST_CMD_ERROR:-Installation failed}"
            _CONF_PKG_DECLINED["$pkg_id"]=1

            local tmpl_check="${_CONF_TEMPLATES["$conf_file"]:-}"
            if [[ -n "$post_cmd" || -n "$tmpl_check" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    proceed_post=true
                elif [[ "${NON_INTERACTIVE:-false}" == true ]]; then
                    proceed_post=false
                    log_info "Skipping post-installation and configuration templates for failed package '$pkg_id'."
                else
                    _ui_bell
                    if _prompt_confirm "Installation of '${pkg_id}' failed. Proceed with post-installation hooks and configuration templates?" false; then
                        proceed_post=true
                    else
                        proceed_post=false
                        log_info "Skipped post-installation and configuration templates for '$pkg_id'."
                    fi
                fi
            else
                proceed_post=false
            fi
        fi

        if [[ "$proceed_post" == true ]]; then
            # Run post hook if present (before verification so symlinks/wrappers exist)
            if [[ -n "$post_cmd" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    [[ "$VERBOSE" == true ]] && log_action "    post: $post_cmd"
                else
                    if [[ "$VERBOSE" == true ]]; then
                        SPINNER_INDENT="      " _run_script "$post_cmd" "post: $post_cmd" || log_warn "Post hook failed for '$pkg_id'."
                    else
                        bash -c "$post_cmd" >/dev/null 2>&1 || log_warn "Post hook failed for '$pkg_id'."
                    fi
                fi
            fi

            # Deploy templates and configs for this package
            LOG_INDENT="      " SPINNER_INDENT="      " deploy_package_templates "$conf_file"
        fi

        # Post-install scope monitoring & verification
        if [[ "$install_success" == true ]]; then
            _INSTALLED_PACKAGES_COUNT=$((_INSTALLED_PACKAGES_COUNT + 1))
            if [[ "$DRY_RUN" != true ]]; then
                hash -r 2>/dev/null || true
                if ! _check_bins_scoped "$bin" "$scope" && [[ "$scope" != "script" ]]; then
                    log_warn "'${pkg_id}' binary not found in ${scope} PATH after installation."
                    _FAILED_PACKAGES+=("$pkg_id")
                    _FAILURE_REASONS["$pkg_id"]="Binary not found in ${scope} PATH"
                    _CONF_PKG_DECLINED["$pkg_id"]=1
                    _INSTALLED_PACKAGES_COUNT=$((_INSTALLED_PACKAGES_COUNT - 1))
                fi
            fi
        fi
    else
        _INSTALLED_PACKAGES_COUNT=$((_INSTALLED_PACKAGES_COUNT + 1))
        log_success "$pkg_id"
        # Deploy templates and configs for this package
        LOG_INDENT="      " SPINNER_INDENT="      " deploy_package_templates "$conf_file"
    fi
}

install_packages() {
    local pdir="${1:-$PACKAGES_DIR}"
    [[ ! -d "$pdir" ]] && { log_warn "Packages directory not found. Skipping package installation."; return 0; }
    _preload_all_manifests "$pdir"
    _PM="${_PM:-$(_detect_pm)}"

    # 1. Group Multi-Selector
    local grp_ids=() grp_labels=() grp_descs=() grp_states=() grp_locks=()
    local g
    while IFS= read -r g; do
        [[ -z "$g" ]] && continue
        local is_opt
        is_opt="$(_get_group_meta "$g" "optional")"
        local desc
        desc="$(_get_group_meta "$g" "description")"

        grp_ids+=("$g")
        grp_labels+=("$g")
        grp_descs+=("$desc")

        if [[ "$is_opt" == "false" || "$g" == "core" ]]; then
            grp_locks+=("required")
            grp_states+=(1)
        elif _group_selected "$g"; then
            grp_locks+=("config")
            grp_states+=(1)
        else
            grp_locks+=("optional")
            grp_states+=(0)
        fi
    done < <(_get_groups)

    local selected_groups_raw
    selected_groups_raw="$(_ui_multiselect "Select package groups" grp_ids grp_labels grp_descs grp_states grp_locks)"
    local -a active_groups=()
    read -ra active_groups <<< "$selected_groups_raw"
    INSTALL_GROUPS=("${active_groups[@]}")

    # Mark unselected groups as declined
    local ag
    for ag in "${grp_ids[@]}"; do
        local g_active=0
        for g in "${active_groups[@]}"; do
            [[ "$g" == "$ag" ]] && { g_active=1; break; }
        done
        if [[ $g_active -eq 0 ]]; then
            local unsel_pkg
            while IFS= read -r unsel_pkg; do
                [[ -n "$unsel_pkg" ]] && _CONF_PKG_DECLINED["$unsel_pkg"]=1
            done < <(_get_group_packages "$ag")
        fi
    done

    # 2. Iterate each selected group: Package Multi-Selector & Package-by-Package Lifecycle
    local current_group
    for current_group in "${active_groups[@]}"; do
        [[ -z "$current_group" ]] && continue

        local pkg_ids=() pkg_labels=() pkg_descs=() pkg_states=() pkg_locks=()
        local pkg
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local conf_file="$pdir/$current_group/$pkg.conf"
            [[ ! -f "$conf_file" ]] && continue

            _parse_manifest_file "$conf_file" "$pkg"

            local pkg_id="$pkg_name"
            local bin="${pkg_bin:-$pkg_id}"
            local scope="$pkg_scope"
            local desc="$pkg_desc"
            local rest="${pkg_install}${pkg_install:+ }${pkg_opts}"

            pkg_ids+=("$pkg")
            pkg_labels+=("$pkg_id")
            pkg_descs+=("$desc")

            local needs_spec="$(_get_opt needs "$rest")"
            local needs_missing=""
            if [[ -n "$needs_spec" ]]; then
                local need_item
                local saved_ifs="$IFS"
                IFS=','
                for need_item in $needs_spec; do
                    need_item="${need_item#"${need_item%%[![:space:]]*}"}"
                    need_item="${need_item%"${need_item##*[![:space:]]}"}"
                    [[ -z "$need_item" ]] && continue
                    if [[ "${_CONF_PKG_DISABLED["$need_item"]:-0}" -eq 1 || "${_CONF_PKG_DECLINED["$need_item"]:-0}" -eq 1 ]]; then
                        needs_missing="$need_item"
                        break
                    elif ! _check_bins_scoped "$need_item" "any"; then
                        local has_active_manifest=false
                        local cand_file
                        for cand_file in "$PACKAGES_DIR"/*/"${need_item}.conf"; do
                            if [[ -f "$cand_file" ]]; then
                                if _package_is_active "$cand_file" 2>/dev/null; then
                                    has_active_manifest=true
                                fi
                                break
                            fi
                        done
                        if [[ "$has_active_manifest" == false ]]; then
                            needs_missing="$need_item"
                            break
                        fi
                    fi
                done
                IFS="$saved_ifs"
            fi

            if [[ "${_CONF_PKG_DISABLED["$pkg"]:-0}" -eq 1 ]]; then
                pkg_locks+=("disabled:config")
                pkg_states+=(0)
            elif [[ "$(_get_opt disabled "$rest")" == true ]]; then
                pkg_locks+=("disabled")
                pkg_states+=(0)
            elif ! _eval_cond "" "$rest"; then
                local cond_reason
                cond_reason="$(_get_failed_cond_reason "" "$rest")"
                pkg_locks+=("unsupported:${cond_reason:-unmet}")
                pkg_states+=(0)
            elif [[ -n "$needs_missing" ]]; then
                if _find_pkg_manifest "$needs_missing" >/dev/null 2>&1; then
                    pkg_locks+=("alt:needs ${needs_missing}")
                    pkg_states+=(0)
                else
                    pkg_locks+=("disabled:missing ${needs_missing}")
                    pkg_states+=(0)
                fi
            elif _check_bins_scoped "$bin" "$scope"; then
                pkg_locks+=("installed:${REPLY_PATH:-$REPLY}")
                pkg_states+=(1)
            else
                local alt_target="$(_get_opt alt "$rest")"
                local alt_installed=false
                if [[ -n "$alt_target" ]] && _check_bins_scoped "$alt_target" "$scope"; then
                    alt_installed=true
                fi
                local is_opt="$(_get_opt optional "$rest")"
                local is_rec="$(_get_opt recommended "$rest")"

                local is_opt_explicit=0
                if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
                    local op
                    for op in "${OPTIONAL_PACKAGES[@]}"; do
                        [[ "$op" == "$pkg" || "$op" == "$pkg_id" ]] && is_opt_explicit=1 && break
                    done
                fi

                if [[ "$is_opt_explicit" -eq 1 ]]; then
                    pkg_locks+=("config")
                    pkg_states+=(1)
                elif [[ "$is_opt" != true && -z "$alt_target" ]]; then
                    pkg_locks+=("required")
                    pkg_states+=(1)
                elif [[ -n "$alt_target" ]]; then
                    if [[ "$alt_installed" == true ]]; then
                        pkg_locks+=("alt:${alt_target} installed")
                        pkg_states+=(0)
                    else
                        pkg_locks+=("alt:${alt_target}")
                        pkg_states+=(1)
                    fi
                elif [[ "$is_rec" == true ]]; then
                    pkg_locks+=("recommended")
                    pkg_states+=(1)
                else
                    pkg_locks+=("optional")
                    if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
                        pkg_states+=(0)
                    else
                        pkg_states+=(1)
                    fi
                fi
            fi
        done < <(_get_group_packages "$current_group")

        if [[ ${#pkg_ids[@]} -gt 0 ]]; then
            local chosen_pkgs_raw
            chosen_pkgs_raw="$(_ui_multiselect "Packages in [${current_group}]" pkg_ids pkg_labels pkg_descs pkg_states pkg_locks)"
            local -a chosen_pkgs=()
            read -ra chosen_pkgs <<< "$chosen_pkgs_raw"

            # Track declined packages in this group
            local pid
            for pid in "${pkg_ids[@]}"; do
                local is_chosen=0 c
                for c in "${chosen_pkgs[@]}"; do
                    [[ "$c" == "$pid" ]] && { is_chosen=1; break; }
                done
                if [[ $is_chosen -eq 0 ]]; then
                    _CONF_PKG_DECLINED["$pid"]=1
                fi
            done

            # Execute package-by-package lifecycle: install -> config/templates -> post hook -> next package
            local cpkg
            for cpkg in "${chosen_pkgs[@]}"; do
                [[ -z "$cpkg" ]] && continue
                local conf_file="$pdir/$current_group/$cpkg.conf"
                [[ ! -f "$conf_file" ]] && continue

                _install_single_package "$conf_file" "$cpkg"
            done
        fi
    done

    # 3. Custom packages from CUSTOM_PACKAGES_DIR
    if [[ -n "${CUSTOM_PACKAGES_DIR:-}" && -d "$CUSTOM_PACKAGES_DIR" ]]; then
        local custom_candidates=()
        if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
            local op
            for op in "${OPTIONAL_PACKAGES[@]}"; do
                [[ -z "$op" ]] && continue
                local cconf=""
                cconf="$(_find_pkg_manifest "$op")" || true
                if [[ -n "$cconf" && "$cconf" == "$CUSTOM_PACKAGES_DIR"* ]]; then
                    custom_candidates+=("$op")
                fi
            done
        else
            local f
            for f in "$CUSTOM_PACKAGES_DIR"/*.conf "$CUSTOM_PACKAGES_DIR"/*/*.conf; do
                if [[ -f "$f" && "${f##*/}" != _* ]]; then
                    local bname="${f##*/}"
                    custom_candidates+=("${bname%.conf}")
                fi
            done
        fi

        local c_pkg_ids=() c_pkg_labels=() c_pkg_descs=() c_pkg_states=() c_pkg_locks=()
        local c_pkg
        for c_pkg in "${custom_candidates[@]}"; do
            [[ -z "$c_pkg" ]] && continue
            local cconf=""
            cconf="$(_find_pkg_manifest "$c_pkg")" || continue
            [[ ! -f "$cconf" ]] && continue

            _parse_manifest_file "$cconf" "$c_pkg"
            local pkg_id="$pkg_name"
            local bin="${pkg_bin:-$pkg_id}"
            local scope="$pkg_scope"
            local desc="$pkg_desc"
            local rest="${pkg_install}${pkg_install:+ }${pkg_opts}"

            c_pkg_ids+=("$c_pkg")
            c_pkg_labels+=("$pkg_id")
            c_pkg_descs+=("$desc")

            if [[ "${_CONF_PKG_DISABLED["$c_pkg"]:-0}" -eq 1 || "${_CONF_PKG_DISABLED["$pkg_id"]:-0}" -eq 1 ]]; then
                c_pkg_locks+=("disabled:config")
                c_pkg_states+=(0)
            elif _check_bins_scoped "$bin" "$scope"; then
                c_pkg_locks+=("installed")
                c_pkg_states+=(0)
            else
                c_pkg_locks+=("optional")
                c_pkg_states+=(1)
            fi
        done

        if [[ ${#c_pkg_ids[@]} -gt 0 ]]; then
            local chosen_custom_raw
            chosen_custom_raw="$(_ui_multiselect "Custom Packages" c_pkg_ids c_pkg_labels c_pkg_descs c_pkg_states c_pkg_locks)"
            local -a chosen_custom=()
            read -ra chosen_custom <<< "$chosen_custom_raw"

            local c_item
            for c_item in "${chosen_custom[@]}"; do
                [[ -z "$c_item" ]] && continue
                local conf_file=""
                conf_file="$(_find_pkg_manifest "$c_item")" || continue
                [[ ! -f "$conf_file" ]] && continue

                _install_single_package "$conf_file" "$c_item"
            done
        fi
    fi

    return 0
}
