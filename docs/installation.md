# Installation

## Linux and macOS

```sh
curl -fsSL https://github.com/meechdw/cadence/scripts/install.sh | bash
```

## Windows

```powershell
powershell -c "irm https://github.com/meechdw/cadence/scripts/install.ps1 | iex"
```

## NixOS

```nix
# Add to your flake inputs
inputs.cadence.url = "github:meechdw/cadence";

# Add to your NixOS module
environment.systemPackages = [ inputs.cadence.packages.${pkgs.system}.default ];
```
