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
          BraveSyncUrl = "";
          SyncDisabled = true;
          PasswordManagerEnabled = false;
          PasswordSharingEnabled = false;
          PasswordLeakDetectionEnabled = false;
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;
          TranslateEnabled = false;
          DnsOverHttpsMode = "secure";
          DnsOverHttpsTemplates = "https://dns.adguard-dns.com/dns-query";
          MetricsReportingEnabled = false;
          SearchSuggestEnabled = false;
          BrowserSignin = 0;
          SpellcheckEnabled = false;
          SafeBrowsingExtendedReportingEnabled = false;
          SafeBrowsingSurveysEnabled = false;
          SafeBrowsingDeepScanningEnabled = false;
          PromotionalTabsEnabled = false;
          ShowCastIconInToolbar = false;
          AutoplayAllowed = false;
          BlockThirdPartyCookies = true;
          UrlKeyedAnonymizedDataCollectionEnabled = false;
          DefaultGeolocationSetting = 2;
          DefaultNotificationsSetting = 2;
          DefaultLocalFontsSetting = 2;
          DefaultSensorsSetting = 2;
          DefaultSerialGuardSetting = 2;
          CloudReportingEnabled = false;
          DriveDisabled = true;
          QuickAnswersEnabled = false;
          DeviceActivityHeartbeatEnabled = false;
          DeviceMetricsReportingEnabled = false;
          HeartbeatEnabled = false;
          LogUploadEnabled = false;
          ReportAppInventory = [ "" ];
          ReportDeviceActivityTimes = false;
          ReportDeviceAppInfo = false;
          ReportDeviceSystemInfo = false;
          ReportDeviceUsers = false;
          ReportWebsiteTelemetry = [ "" ];
          AlternateErrorPagesEnabled = false;
          BackgroundModeEnabled = false;
          BrowserGuestModeEnabled = false;
          BuiltInDnsClientEnabled = false;
          DefaultBrowserSettingEnabled = false;
          ParcelTrackingEnabled = false;
          RelatedWebsiteSetsEnabled = false;
          ShoppingListEnabled = false;
          ExtensionManifestV2Availability = 2;
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
