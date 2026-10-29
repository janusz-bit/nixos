fail() {
  echo "$*" >&2
  exit 1
}

[[ $# -eq 1 && "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail "Usage: package-import <top-level nixpkgs attribute>"
name=$1
cd "$(git rev-parse --show-toplevel)"
registry=modules/packages/packages.nix
dest=modules/packages/_$name
[[ -f flake.nix && -f "$registry" ]] || fail "Run package-import from the NixOS configuration repository."
[[ ! -e "$dest" ]] || fail "$dest already exists."

# --inputs-from: nixpkgs przypięty w flake.lock (ten sam, którego
# używają hosty), nie wpis z rejestru. legacyPackages flake'a nixpkgs
# odmawia pakietów niewolnych (CUDA), więc ewaluacja idzie przez
# instancję z allowUnfree jak na hostach i w packages.<system>.
upstream() {
  nix eval --inputs-from . --raw nixpkgs#pkgs --apply "pkgs:
    (import pkgs.path {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    }).${name}.$1"
}
position=$(upstream meta.position)
upstream_drv=$(upstream drvPath)
file=${position%:*}
dir=$(dirname "$file")
entry=$(basename "$file")
relative_dir=${dir#"$(cut -d/ -f1-4 <<<"$file")"/}
[[ "$relative_dir" != pkgs/top-level ]] || fail "$name is defined inline in pkgs/top-level; there is no directory to copy."
[[ "$entry" == default.nix || ! -e "$dir/default.nix" ]] || fail "$relative_dir has both $entry and default.nix; copy it by hand."

# Wpis alfabetycznie w bloku localPackages; awk opiera się na jego
# wcięciach w packages.nix.
registered=$(awk -v name="$name" '
  /^  localPackages = pkgs: \{$/ { inside = 1; print; next }
  inside && !done && (/^  \};$/ || $1 > name) {
    printf "    %s = pkgs.callPackage ./_%s { };\n", name, name
    done = 1
  }
  /^  \};$/ { inside = 0 }
  { print }
  END { exit !done }
' "$registry") || fail "No localPackages block found in $registry."

cp -r "$dir" "$dest"
# Kopia ze store jest tylko do odczytu.
chmod -R u+w "$dest"
[[ "$entry" == default.nix ]] || mv "$dest/$entry" "$dest/default.nix"
printf '%s\n' "$registered" >"$registry"
# Flake widzi tylko pliki śledzone przez git.
git add -- "$dest"
echo "Copied $relative_dir to $dest and registered $name in $registry."

local_drv=$(nix eval --raw ".#$name.drvPath") ||
  fail "$dest does not evaluate. Fix it, or undo: git rm -rf -- $dest and remove $name from $registry."
if [[ "$local_drv" == "$upstream_drv" ]]; then
  echo "Same derivation as nixpkgs: $local_drv"
else
  echo "Warning: $local_drv differs from nixpkgs ($upstream_drv);" \
    "nixpkgs probably passes extra arguments to callPackage (pkgs/top-level/all-packages.nix)." >&2
fi
