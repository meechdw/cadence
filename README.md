# Cadence

<!-- prettier-ignore-start -->
> [!WARNING]
> This project is in early development and is not ready for use.
<!-- prettier-ignore-end -->

High-performance task orchestration system for any codebase

## Installation

### Linux and macOS

```sh
curl -fsSL https://github.com/meechdw/cadence/scripts/install.sh | bash
```

### NixOS

```nix
{
  inputs.cadence.url = "github:meechdw/cadence";

  outputs = { cadence }: {
    environment.systemPackages = [ cadence.packages.${pkgs.system}.default ];
  };
}
```

### Windows

```powershell
powershell -c "irm https://github.com/meechdw/encore/scripts/install.ps1 | iex"
```
