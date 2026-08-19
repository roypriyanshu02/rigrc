# shellcheck shell=bash
# =============================================================================
#  DEVELOPER & QA TOOLS (Fmt, Lint, Doctor, Symlinks)
# =============================================================================

_format_manifest() {
    local mode="format"
    local targets=()
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--check-only" ]]; then
            mode="--check-only"
        elif [[ -n "$arg" ]]; then
            targets+=("$arg")
        fi
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=("$SCRIPT_DIR/packages/"*/*.conf "$GROUPS_CONF" "$SCRIPT_DIR/"*.conf)
    fi
    local unformatted=0

    # Format packages/*/*.conf, _groups.conf and root *.conf files
    local cfg
    for cfg in "${targets[@]}"; do
        [[ -f "$cfg" ]] || continue
        local tmp_cfg
        tmp_cfg="$(umask 077 && mktemp "${cfg}.XXXXXX")"
        _TRACKED_TMP_FILES+=("$tmp_cfg")
        sed 's/[[:space:]]*$//' "$cfg" > "$tmp_cfg"
        [[ -n "$(tail -c 1 "$tmp_cfg" 2>/dev/null)" ]] && echo "" >> "$tmp_cfg"

        if ! cmp -s "$cfg" "$tmp_cfg"; then
            if [[ "$mode" == "--check-only" ]]; then
                unformatted=$((unformatted + 1))
            else
                chmod 644 "$tmp_cfg" 2>/dev/null || true
                mv "$tmp_cfg" "$cfg"
                log_success "Formatted $(basename "$cfg")"
            fi
        fi
        rm -f "$tmp_cfg"
    done

    if [[ "$mode" == "--check-only" ]]; then
        [[ "$unformatted" -gt 0 ]] && return 1 || return 0
    else
        log_success "Formatting complete."
        exit 0
    fi
}


_lint_manifest() {
    [[ ! -d "$PACKAGES_DIR" ]] && { log_error "Packages directory not found."; exit 1; }
    _ui_header "Running Static Lint Checks"
    local errors=0

    _preload_all_manifests "$PACKAGES_DIR"

    local valid_groups=() gdir conf_file
    for gdir in "$PACKAGES_DIR"/*; do
        [[ ! -d "$gdir" ]] && continue
        valid_groups+=("$(basename "$gdir")")
    done

    for gdir in "$PACKAGES_DIR"/*; do
        [[ ! -d "$gdir" ]] && continue
        for conf_file in "$gdir"/*.conf; do
            [[ ! -f "$conf_file" ]] && continue
            local rel_file="${conf_file#"$SCRIPT_DIR/"}"
            
            local in_tmpl=false
            while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
                line="${raw_line#"${raw_line%%[![:space:]]*}"}"
                line="${line%"${line##*[![:space:]]}"}"
                if [[ "$line" =~ ^\[(.*)\]$ ]]; then
                    local header="${BASH_REMATCH[1]}"
                    local sec_type="" sec_ident="" sec_mod="" is_valid=0
                    _parse_section_header "$header" sec_type sec_ident sec_mod is_valid
                    if [[ "$is_valid" -eq 0 ]]; then
                        if [[ "$sec_type" == "template" ]]; then
                            in_tmpl=true
                        else
                            in_tmpl=false
                        fi
                    elif [[ "$in_tmpl" == false ]]; then
                        log_error "$rel_file: Invalid section header or modifier syntax: '[$header]'"
                        errors=$((errors + 1))
                    fi
                fi
            done < "$conf_file"

            local bashrc_content="${_CONF_BASHRC["$conf_file"]:-}"
            if [[ -n "$bashrc_content" ]]; then
                if ! bash -n <<< "$bashrc_content" 2>/dev/null; then
                    log_error "$rel_file: [bashrc] block contains syntax errors."
                    errors=$((errors + 1))
                fi
            fi

            local p_scope="${_CONF_PKG_SCOPE["$conf_file"]:-system}"
            case "$p_scope" in
                system|user|script) ;;
                *)
                    log_error "$rel_file: Invalid scope '$p_scope'. Allowed scopes: system, user, script."
                    errors=$((errors + 1))
                    ;;
            esac
        done
    done

    local cfg
    for cfg in "$SCRIPT_DIR/"*.conf; do
        [[ ! -f "$cfg" ]] && continue
        local fname
        fname="$(basename "$cfg")"

        local raw_line line
        while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
            line="${raw_line#"${raw_line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            if [[ "$line" =~ ^\[(.*)\]$ ]]; then
                local header="${BASH_REMATCH[1]}"
                local sec_type="" sec_ident="" sec_mod="" is_valid=0
                _parse_section_header "$header" sec_type sec_ident sec_mod is_valid
                if [[ "$is_valid" -ne 0 ]]; then
                    log_error "Config $fname: Invalid section header or modifier syntax: '[$header]'"
                    errors=$((errors + 1))
                fi
            fi
        done < "$cfg"
    done

    if [[ -n "${_CONF_PKG_KEYS["global:INSTALL_GROUPS"]:-}" ]]; then
        local raw_ig="${_CONF_PKG_KEYS["global:INSTALL_GROUPS"]}"
        raw_ig="${raw_ig//[()]/}"
        raw_ig="${raw_ig//,/ }"
        local g
        for g in $raw_ig; do
            [[ -z "$g" ]] && continue
            local found=false vg
            for vg in "${valid_groups[@]}"; do
                if [[ "$g" == "$vg" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == false ]]; then
                log_error "Configuration references unknown package group: '$g'"
                errors=$((errors + 1))
            fi
        done
    fi

    if ! _format_manifest "$GROUPS_CONF" --check-only; then
        log_warn "Configuration files need formatting. Run './rigrc.sh --format' to fix."
        errors=$((errors + 1))
    fi

    if [[ "$errors" -eq 0 ]]; then
        log_success "Lint passed with 0 errors."
        exit 0
    else
        log_error "Lint found ${errors} error(s)."
        exit 1
    fi
}


_doctor_check() {
    _ui_header "System Diagnostics"
    local warnings=0 errors=0

    # 1. Shell & Prerequisites
    printf "\n  %s[1/6]%s %s\n" "${CLR_MUTED}" "${RESET}" "${BOLD}Shell and Core Tools${RESET}"
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        log_success "Bash version: ${BASH_VERSION}"
    else
        log_error "Bash version ${BASH_VERSION} is not supported. Bash 4.0 or newer is required."
        errors=$((errors + 1))
    fi

    local tool
    for tool in git curl stow awk tar gzip; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "Available: $tool (${CLR_MUTED}$(command -v "$tool")${RESET})"
        else
            log_warn "Missing: $tool"
            warnings=$((warnings + 1))
        fi
    done

    # 2. Package Managers & Lock State
    printf "\n  %s[2/6]%s %s\n" "${CLR_MUTED}" "${RESET}" "${BOLD}Package Managers & Lock State${RESET}"
    local pm_found=0 pm
    for pm in apt dnf pacman apk brew mise; do
        if command -v "$pm" >/dev/null 2>&1; then
            log_success "Package manager found: ${BOLD}$pm${RESET}"
            pm_found=$((pm_found + 1))
        fi
    done
    [[ $pm_found -eq 0 ]] && { log_warn "No supported package manager found (apt/dnf/pacman/apk/brew/mise)."; warnings=$((warnings + 1)); }

    # 3. Network & GitHub API Reachability
    printf "\n  %s[3/6]%s %s\n" "${CLR_MUTED}" "${RESET}" "${BOLD}Network & Rate-Limit Diagnostics${RESET}"
    if _check_network; then
        log_success "Internet connectivity: reachable"
    else
        log_warn "Internet connectivity: unreachable or restricted"
        warnings=$((warnings + 1))
    fi

    if command -v curl >/dev/null 2>&1; then
        local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
        local -a gh_auth=()
        [[ -n "$token" ]] && gh_auth=(-H "Authorization: Bearer $token")
        local gh_resp
        gh_resp="$(curl --proto '=https' --tlsv1.2 -sSL -i --connect-timeout 3 --max-time 5 "${gh_auth[@]}" https://api.github.com/rate_limit 2>/dev/null || true)"
        if [[ -n "$gh_resp" ]]; then
            local rem_limit="" total_limit=""
            if [[ "$gh_resp" =~ [Xx]-[Rr]atelimit-[Rr]emaining:[[:space:]]*([0-9]+) ]]; then
                rem_limit="${BASH_REMATCH[1]}"
            fi
            if [[ "$gh_resp" =~ [Xx]-[Rr]atelimit-[Ll]imit:[[:space:]]*([0-9]+) ]]; then
                total_limit="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$rem_limit" ]]; then
                local limit_info="${rem_limit}"
                [[ -n "$total_limit" ]] && limit_info="${rem_limit}/${total_limit}"
                if [[ "$rem_limit" -gt 0 ]]; then
                    log_success "GitHub API reachable (Rate limit remaining: ${limit_info})"
                else
                    log_warn "GitHub API rate limit exhausted (0 remaining). Set GITHUB_TOKEN to resolve."
                    warnings=$((warnings + 1))
                fi
            else
                log_success "GitHub API reachable"
            fi
        else
            log_warn "GitHub API unreachable or timed out."
            warnings=$((warnings + 1))
        fi
    fi

    # 4. Environment & Directories
    printf "\n  %s[4/6]%s %s\n" "${CLR_MUTED}" "${RESET}" "${BOLD}Environment and Directories${RESET}"
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        log_success "PATH contains $HOME/.local/bin"
    else
        log_warn "PATH does not include $HOME/.local/bin"
        warnings=$((warnings + 1))
    fi

    local d
    for d in "$HOME/.local/bin" "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_DATA_HOME:-$HOME/.local/share}" "${XDG_CACHE_HOME:-$HOME/.cache}" "${XDG_STATE_HOME:-$HOME/.local/state}"; do
        if [[ -d "$d" ]]; then
            log_success "Directory exists: ${d}"
        else
            if [[ "${1:-}" == "--fix" || "${2:-}" == "--fix" ]]; then
                mkdir -p "$d"
                log_success "Created missing directory: ${d}"
            else
                log_warn "Directory missing: ${d}"
                warnings=$((warnings + 1))
            fi
        fi
    done

    # 5. Broken Symlink Check
    printf "\n  %s[5/6]%s %s\n" "${CLR_MUTED}" "${RESET}" "${BOLD}Symlink Integrity${RESET}"
    local broken_links=()
    while IFS= read -r -d '' link; do
        if [[ ! -e "$link" ]]; then
            broken_links+=("$link")
        fi
    done < <(find "$HOME" "$HOME/.config" -maxdepth 1 -type l -print0 2>/dev/null)

    if [[ ${#broken_links[@]} -eq 0 ]]; then
        log_success "No broken symlinks found."
    else
        if [[ "${1:-}" == "--fix" || "${2:-}" == "--fix" ]]; then
            for link in "${broken_links[@]}"; do
                rm -f "$link"
                log_success "Removed broken symlink: $link"
            done
        else
            log_warn "Found ${#broken_links[@]} broken symlink(s):"
            for link in "${broken_links[@]}"; do
                printf "    %s %s\n" "${CLR_MUTED}•${RESET}" "$link"
            done
            log_info "Run './rigrc.sh --doctor --fix' or './rigrc.sh --clean-symlinks' to remove them."
            warnings=$((warnings + 1))
        fi
    fi

    # 6. Manifest Inventory Audit
    printf "\n  %s[6/6]%s %s\n" "${CLR_MUTED}" "${RESET}" "${BOLD}Package Inventory Audit${RESET}"
    if [[ -d "$PACKAGES_DIR" ]]; then
        local total_pkgs=0 installed_pkgs=0 sys_total=0 sys_inst=0 usr_total=0 usr_inst=0
        local gdir conf_file pkg bin scope
        for gdir in "$PACKAGES_DIR"/*; do
            [[ ! -d "$gdir" ]] && continue
            for conf_file in "$gdir"/*.conf; do
                [[ ! -f "$conf_file" ]] && continue
                total_pkgs=$((total_pkgs + 1))
                pkg="$(basename "$conf_file" .conf)"
                _parse_manifest_file "$conf_file" "$pkg"
                bin="${pkg_bin:-$pkg}"
                scope="$pkg_scope"
                if [[ "$scope" == "user" ]]; then
                    usr_total=$((usr_total + 1))
                    if _check_bins_scoped "$bin" "user"; then
                        usr_inst=$((usr_inst + 1))
                        installed_pkgs=$((installed_pkgs + 1))
                    fi
                elif [[ "$scope" == "system" ]]; then
                    sys_total=$((sys_total + 1))
                    if _check_bins_scoped "$bin" "system"; then
                        sys_inst=$((sys_inst + 1))
                        installed_pkgs=$((installed_pkgs + 1))
                    fi
                else
                    if _check_bins "$bin"; then
                        installed_pkgs=$((installed_pkgs + 1))
                    fi
                fi
            done
        done
        log_info "Package inventory: ${installed_pkgs}/${total_pkgs} installed (system: ${sys_inst}/${sys_total}, user: ${usr_inst}/${usr_total})."
    else
        log_warn "Packages directory not found. Skipping inventory audit."
        warnings=$((warnings + 1))
    fi

    _ui_header "Diagnostic Results"
    if [[ $errors -eq 0 ]]; then
        log_success "Diagnostics passed: ${warnings} warning(s), 0 error(s)."
        exit 0
    else
        log_error "Diagnostics failed: ${errors} error(s), ${warnings} warning(s)."
        exit 1
    fi
}

_clean_broken_symlinks() {
    log_info "Scanning for broken symlinks..."
    local link count=0
    while IFS= read -r -d '' link; do
        if [[ ! -e "$link" ]]; then
            log_info "Removing broken symlink: ${link}"
            rm -f "$link"
            count=$((count + 1))
        fi
    done < <(find "$HOME" "$HOME/.config" -maxdepth 1 -type l -print0 2>/dev/null)
    log_success "Removed ${count} broken symlink(s)."
    exit 0
}

_export_diagnostics() {
    local outfile="${1:-dotfiles-diagnostics.json}"
    local distro arch pm conds
    distro="$(_get_distro_name)"
    arch="$(_get_arch)"
    pm="$(_detect_pm)"
    conds="$(_get_detected_conds)"

    cat << EOF > "$outfile"
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)",
  "distro": "${distro}",
  "arch": "${arch}",
  "package_manager": "${pm}",
  "conditions": "${conds}",
  "environment": "$(_get_env)",
  "bash_version": "${BASH_VERSION}",
  "failed_packages": [
$(local i=0; for fp in "${_FAILED_PACKAGES[@]}"; do
    local r="${_FAILURE_REASONS["$fp"]:-unknown}"
    r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\n'/ }"
    local fp_esc="${fp//\\/\\\\}"; fp_esc="${fp_esc//\"/\\\"}"
    [[ $i -gt 0 ]] && printf ',\n'
    printf '    {"package": "%s", "reason": "%s"}' "$fp_esc" "$r"
    i=$((i+1))
  done)
  ]
}
EOF
    log_success "Exported diagnostics to ${outfile}"
    exit 0
}
