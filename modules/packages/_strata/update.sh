# Dokańcza to, czego nix-update nie odczyta z tagu: wersję silnika
# (SHA256SUMS.txt wydania) i LLAMA_CPP_COMMIT z setup.py wydania.
# Wersję, hash src i hashe engine/llamaCpp podmienia nix-update
# (`--custom-dep`), więc każda z tych wartości musi zostać atrybutem
# derywacji w default.nix.
repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "strata-update: run it inside the NixOS repository" >&2
  exit 1
}
cd "$repo"

file=modules/packages/_strata/default.nix
repo_url=https://github.com/Niko1221/Strata

tag=$(curl -fsSL https://api.github.com/repos/Niko1221/Strata/releases/latest | jq -r .tag_name)
sums=$(curl -fsSL "$repo_url/releases/download/$tag/SHA256SUMS.txt")

# Asset silnika CUDA 13 ma własną numerację (strata-engine-<wersja>-...).
asset=$(grep -oE 'strata-engine-[0-9.]+-linux-x86_64-cuda-cuda13\.tar\.gz' <<<"$sums" || true)
if [ -z "$asset" ]; then
  echo "strata-update: no cuda13 engine asset in SHA256SUMS.txt of $tag" >&2
  exit 1
fi
engine_version=${asset#strata-engine-}
engine_version=${engine_version%-linux-*}

sed -i -E "s/engineVersion = \"[^\"]+\";/engineVersion = \"$engine_version\";/" "$file"
grep -qF "engineVersion = \"$engine_version\";" "$file" || {
  echo "strata-update: engineVersion not found in $file" >&2
  exit 1
}

setup=$(curl -fsSL "https://raw.githubusercontent.com/Niko1221/Strata/$tag/setup.py")
commit=$(grep -m 1 -oE '^LLAMA_CPP_COMMIT = "[0-9a-f]{40}"' <<<"$setup" | cut -d '"' -f 2 || true)
if [ -z "$commit" ]; then
  echo "strata-update: LLAMA_CPP_COMMIT not found in setup.py of $tag" >&2
  exit 1
fi
if ! grep -qF "rev = \"$commit\";" "$file"; then
  sed -i -E "s/rev = \"[0-9a-f]{40}\";/rev = \"$commit\";/" "$file"
  nix-update -F strata --version skip --custom-dep llamaCpp
fi

nix-update -F strata --version "${tag#v}" --custom-dep engine
