default:
    just --list

build mode="Debug":
    zig build -Doptimize={{mode}}

clean:
    rm -rf .zig-cache zig-out

generate-deps:
    nix run nixpkgs#zon2nix > deps.nix
    nixfmt deps.nix

lint:
    zig fmt --check .
    prettier --check .
    nixfmt --check flake.nix deps.nix

run *args:
    zig build run -- {{args}}

test *filters:
    zig build test --summary all -- {{filters}}

watch +recipes:
    watchexec -i .zig-cache -i zig-out -- just {{recipes}}
