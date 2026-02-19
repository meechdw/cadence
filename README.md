<h1>
<p align="center">
  <img src="./cadence.svg" width="128" height="128" alt="Cadence logo">
  <br>Cadence
</h1>
  <p align="center">
    High-performance task orchestration system for any codebase
  </p>
</p>

<!-- prettier-ignore-start -->
> [!WARNING]
> This project is in early development and is not ready for use.
<!-- prettier-ignore-end -->

## Installation

### Linux and macOS

```sh
curl -fsSL https://github.com/meechdw/cadence/scripts/install.sh | bash
```

### Windows

```powershell
powershell -c "irm https://github.com/meechdw/encore/scripts/install.ps1 | iex"
```

### NixOS

```nix
# Add to your flake inputs
inputs.cadence.url = "github:meechdw/cadence";

# Add to your NixOS module
environment.systemPackages = [ inputs.cadence.packages.${pkgs.system}.default ];
```
