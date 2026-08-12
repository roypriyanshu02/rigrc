<h1 align="center">mydotfiles</h1>
<p align="center">
  <em>A modular dotfiles manager and machine provisioner written in pure Bash.</em>
</p>
<p align="center">
  <a href="https://github.com/roypriyanshu02/mydotfiles"><img src="https://img.shields.io/github/stars/roypriyanshu02/mydotfiles?style=flat-square&color=dfb317" alt="Stars"></a>
  <a href="https://github.com/roypriyanshu02/mydotfiles/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/roypriyanshu02/mydotfiles/ci.yml?branch=main&style=flat-square" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-0284c7?style=flat-square" alt="License"></a>
</p>

---

A declarative machine provisioner and dotfiles manager. Decouples personal machine profiles from cross-distro package definitions with native package manager resolution, GNU Stow symlinking, and atomic backup rollbacks.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/roypriyanshu02/mydotfiles/main/setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh
```

## Custom Configurations

Write your packages, aliases, environment variables, and dotfile templates once into a `.conf` file and take them anywhere. See the **[User Guide](docs/USER_GUIDE.md)** to set up your personal repository and configure machine profiles.

## Contributing & Development

To add new package manifests or contribute upstream improvements, see the **[Contributing Guide](CONTRIBUTING.md)**.

## License

[MIT](LICENSE)
