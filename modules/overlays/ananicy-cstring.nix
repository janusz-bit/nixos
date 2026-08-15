_: {
  # Patch dla ananicy-cpp 1.2.0: glibc 2.42 przestał tranzytywnie
  # dołączać <cstring>, więc std::memset nie znajduje się bez
  # jawnego #include <cstring> (argument.cpp, singleton_process.cpp).
  # Upstream (gitlab.com/ananicy-cpp/ananicy-cpp) jeszcze bez fixa.
  # Podpięty do hosta nixos (modules/hosts/nixos/configuration.nix).
  flake.overlays.ananicy-cstring = _final: prev: {
    ananicy-cpp = prev.ananicy-cpp.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./cstring.patch ];
    });
  };
}
