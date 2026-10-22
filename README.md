# janusz-bit/nixos

Declarative NixOS configuration for three machines, as one flake
([flake-parts](https://flake.parts) + [import-tree](https://github.com/vic/import-tree),
no Home Manager, secrets with [agenix](https://github.com/ryantm/agenix)).

| Host | Machine | Role |
|---|---|---|
| `nixos` | Lenovo LOQ 15IRX10 laptop (x86_64, NVIDIA PRIME) | workstation: Plasma 6, development, AI tools, games |
| `raspberry-pi-4` | Raspberry Pi 4B (aarch64) | home server behind a Cloudflare Tunnel: Nextcloud, Gitea, Matrix, Hermes Agent |
| `wsl` | NixOS-WSL on Windows (x86_64) | command-line environment |

**Where to read next**

- [`docs/reference/hosts.md`](docs/reference/hosts.md) — each host's modules, with diagrams (generated).
- [`docs/reference/modules.md`](docs/reference/modules.md) — every module with its description (generated).
- [`docs/reference/options.md`](docs/reference/options.md) — host registry and `customBot` options (generated).
- [`AGENTS.md`](AGENTS.md) — rules, security invariants and verification steps for contributors and AI agents.
- [`temporary-fixes.md`](temporary-fixes.md) — upstream workarounds and when to remove them.

## Layout

```
flake.nix                 inputs, binary caches (nixConfig), outputs = import-tree ./modules
modules/
  hosts/registry.nix      host registry: hosts.<name> -> nixosConfigurations, CI
  hosts/base/             what every host gets (nix, shell, ssh, git, update aliases),
                          plus opt-in user secrets, fail2ban and LAN-only SSH
  hosts/<host>/           what makes a machine itself: identity, disk, boot, host-only services
  hosts/*.nix             features linking two hosts (laptop-run, claude-notify)
  desktop/  gaming/       workstation features any desktop host can import
  hardware/<machine>/     drivers, firmware quirks, facter report of one machine
  installer/              install-system, offline installer ISO, post-install
  packages/               local packages (overlay local-packages), maintenance scripts (_scripts/)
  skills/                 AI agent skills (Prime Agent, Claude Code)
  checks/                 NixOS VM tests
  _secrets/               agenix secrets and public keys
docs/reference/           generated documentation
```

Every `.nix` file under `modules/` is a flake-parts module (paths with a
`_`-prefixed segment are skipped). NixOS modules are exported as
`flake.modules.nixos.<group>-<name>` and imported explicitly by hosts.

## Everyday use

```sh
update              # switch to the latest commit on GitHub
update-local        # switch to /etc/nixos (local changes)
update-boot / update-reboot / update-local-boot
nix develop         # dev shell: formatter, linters and pre-commit hooks
flake-update        # update flake.lock and local packages, commit
```

Commits go through pre-commit hooks (gitleaks, nixfmt, statix, deadnix) that
also regenerate `.github/workflows` and `docs/reference`; when a hook changes
files, add them and commit again. CI evaluates every host on each push to
`master` and builds them on pull requests.

## Installing

- **Laptop (`nixos`)** from any NixOS live ISO, with network:
  `sudo nix --extra-experimental-features 'nix-command flakes' run github:janusz-bit/nixos -- [--disk /dev/disk/by-id/…]`.
  Fully offline: build the installer ISO with
  `nix build .#packages.x86_64-linux.nixos-iso`, boot it and run
  `install-system`. The whole target disk is wiped. After the first boot:
  `nix run /etc/nixos#post-install` (root SSH key for agenix, then Secure Boot
  enrollment). Details: `modules/installer/install.nix`.
- **Raspberry Pi**: `nix build .#raspberry-pi-4-sd-image`, write the image
  to the SSD/SD card and boot. Clone this repository to `/etc/nixos` (owned
  by the default user), register the keys as in step 4 of "Adding a host",
  and afterwards run `update` on the laptop as well: its `claude-notify`
  pins the RPi's SSH host key.
- **WSL**: install the NixOS-WSL distribution, clone this repository to
  `/etc/nixos` and run `sudo nixos-rebuild switch --flake /etc/nixos#wsl`.

## Adding a host

A host is a registry entry plus the modules that describe its machine.
Workstation features come from `desktop` and `gaming`; settings that depend
on the GPU (CUDA builds, NVIDIA PRIME variables) follow the hardware module
automatically.

1. **Hardware.** On the new machine, from any live ISO:
   `sudo nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-facter -- -o facter.json`.
   Create `modules/hardware/<machine>/default.nix` exporting
   `flake.modules.nixos.hardware-<machine>` with
   `hardware.facter.reportPath = ./facter.json;`, the GPU driver settings
   (see `modules/hardware/LOQ-15IRX10/`) and matching `nixos-hardware`
   profiles. `desktop-kernel` and Proton-CachyOS need an x86-64-v3 CPU
   (AVX2); import `hardware-x86-64-v3` on such machines.
2. **Host.** Create `modules/hosts/<name>/default.nix`:

   ```nix
   { self, customTop, ... }:
   {
     hosts.<name> = {
       system = "x86_64-linux";
       buildOnTags = false; # desktop + gaming: multi-hour build, CI only on PRs and by hand
       modules = [
         self.modules.nixos.base
         self.modules.nixos.<name>
         self.modules.nixos.hardware-<machine>
       ];
     };

     flake.modules.nixos.<name> = { config, ... }: {
       imports = [
         # hosts/<name>/disko.nix and boot.nix: copies of the laptop's,
         # with this disk and without the Windows boot entry
         self.modules.nixos.<name>-disko
         self.modules.nixos.<name>-boot
         self.modules.nixos.desktop
         self.modules.nixos.gaming
         # user secrets and their wrappers (decrypt once step 4 is done)
         self.modules.nixos.base-agenix
         # SSH only from the home LAN, with fail2ban
         self.modules.nixos.base-ssh-lan
         self.modules.nixos.base-fail2ban
       ];
       # networking.hostName comes from the registry (= <name>).
       system.stateVersion = "26.11"; # the release it is installed with; never change it later
       # add users.<name> to modules/args.nix, or omit the line to keep customTop.users.default
       customBot.defaultUser = customTop.users.<name>;
       users.users.${config.customBot.defaultUser} = {
         isNormalUser = true;
         extraGroups = [ "networkmanager" "wheel" ];
       };
     };
   }
   ```

   `git add` the new files, then `nix eval --raw .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath`.
   CI workflows and `docs/reference` pick the host up from the registry.
3. **Install** from a live ISO, in a clone of this repository with the new
   host committed (`git clone https://github.com/janusz-bit/nixos.git && cd nixos`):

   ```sh
   sudo nix --extra-experimental-features 'nix-command flakes' \
     run .#nixosConfigurations.<name>.config.system.build.destroyFormatMount   # wipes the disk
   sudo nixos-install --flake .#<name> --option accept-flake-config true      # binary caches from nixConfig
   sudo cp -a . /mnt/etc/nixos && sudo nixos-enter --root /mnt -- chown -R <user>: /etc/nixos
   sudo nixos-enter --root /mnt -- passwd <user>
   ```

   `install-system` and the ISO automate exactly this for the host named by
   `installHost` in `modules/installer/install.nix`.
4. **Secrets.** After the first boot, `nix run /etc/nixos#post-install ssh`
   creates the root key and prints the `hosts.<name>` / `sshHostKeys.<name>`
   lines for `modules/_secrets/keys.nix` (an existing, different entry is
   replaced only after you confirm). Add the host to the recipients in
   `modules/_secrets/secrets.nix`, re-encrypt on a host that can already
   decrypt (`cd modules/_secrets && sudo agenix -r -i /root/.ssh/id_ed25519`),
   commit, push and run `update` on the new host.

**Replacing the laptop** keeps the host name `nixos`: in `hosts.nixos`,
replace `hardware-LOQ-15IRX10` with the new `hardware-<machine>`, set the new disk
in `modules/hosts/nixos/disko.nix` (or choose it when `install-system` asks),
drop the Windows entry from `boot.nix` if there is none, install, then run
`post-install`. It replaces both the root key and the SSH host key in
`keys.nix` (after confirmation); re-encrypt the secrets on the RPi and run
`update` there so `laptop-run` trusts the new host key. Change `customTop.lan.laptop` in
`modules/args.nix` if the LAN address changes.
