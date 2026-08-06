# Nix packaging

The repository flake builds iDescriptor for `x86_64-linux` and
`aarch64-linux` with the current Cargo/qmetaobject-rs stack.

From the repository root:

```bash
nix build
nix run
nix develop
```

The package enables the Cargo `package_manager` feature and embeds a Nix-specific
update message. Updates remain owned by the Nix profile, Home Manager, or NixOS
configuration that installed the application.

The root `flake.nix` and `flake.lock` remain at the repository root because Nix
uses them as its standard flake entrypoint. The package and module implementations
live in this directory. Git submodule fetching is declared through
`inputs.self.submodules`, which requires Nix 2.27 or newer.

The obsolete `default.nix` and `shell.nix` flake-compat entrypoints were removed.
Use the native flake commands above.

Cargo vendoring uses `allowBuiltinFetchGit` because the shared lockfile contains
pinned, Windows-only `winfsp-rs` Git dependencies even though the Nix package is
Linux-only.
