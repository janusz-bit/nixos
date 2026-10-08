{ self, ... }:
{
  _module.args.customTop = rec {
    repository = {
      name = "nixos";
      site = "github";
      user = "janusz-bit";
      linkFlake = "${repository.site}:${repository.user}/${repository.name}";
      url = "https://${repository.site}.com/${repository.user}/${repository.name}.git";
      place = "/etc/nixos";
    };
    email.full = "janusz-bit@proton.me";
    site = rec {
      name = "janusz-bit";
      end = "com";
      full = name + "." + end;
    };
    # Domowa sieć LAN (laptop: enp8s0 192.168.100.14, RPi: 192.168.100.x).
    # SSH laptopa jest otwarte tylko z tej podsieci; fail2ban na RPi jej nie banuje.
    # lan.laptop: adres, pod którym RPi łączy się z laptopem (`ssh laptop`,
    # remote-agent.nix); RPi nie ma mDNS. Zmiana adresu w routerze → popraw tutaj.
    lan = {
      subnet = "192.168.100.0/24";
      laptop = "192.168.100.14";
    };
    cache = {
      cachix = rec {
        name = "janusz-bit";
        url = "https://${name}.cachix.org";
        pubKey = "${name}.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=";
      };
      # Cache inputów flake'a (ich nixConfig nie jest dziedziczony). Trzymać
      # w zgodzie z nixConfig we flake.nix.
      inputs = [
        {
          # nix-cachyos-kernel (Hydra autora) — trafia przy overlays.pinned
          url = "https://attic.xuyh0120.win/lantian";
          pubKey = "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=";
        }
        {
          # llm-agents.nix (prime-agent, dsh, chatgpt)
          url = "https://cache.numtide.com";
          pubKey = "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=";
        }
      ];
    };
    secretsDir = self + "/modules/_secrets";
  };
}
