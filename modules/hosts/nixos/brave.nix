{ ... }:
{
  flake.nixosModules."nixos/brave" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.brave ];

      environment.etc."brave/policies/managed/policies.json".text = builtins.toJSON {
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
    };
}
