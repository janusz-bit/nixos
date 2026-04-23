{ ... }:
{
  flake.overlays.brave-debloater = final: prev: {
    brave =
      let
        policies = {
          BraveAIChatEnabled = false;
          BraveRewardsDisabled = true;
          BraveWalletDisabled = true;
          BraveVPNDisabled = true;
          TorDisabled = true;
          BraveP3AEnabled = false;
          BraveStatsPingEnabled = false;
          BraveWebDiscoveryEnabled = false;
          BraveNewsDisabled = true;
          BraveTalkDisabled = true;
          BraveSpeedreaderEnabled = false;
          BraveWaybackMachineEnabled = false;
          BravePlaylistEnabled = false;
          SyncDisabled = false;
          PasswordManagerEnabled = false;
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;
          TranslateEnabled = false;
          DnsOverHttpsMode = "secure";
          DnsOverHttpsTemplates = "https://dns.adguard-dns.com/dns-query";
        };
      in
      prev.brave.overrideAttrs (oldAttrs: {
        postInstall = (oldAttrs.postInstall or "") + ''
          mkdir -p $out/etc/brave/policies/managed
          echo '${builtins.toJSON policies}' > $out/etc/brave/policies/managed/policies.json
        '';
      });
  };
}
