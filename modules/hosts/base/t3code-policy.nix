# T3 Code bez telemetrii na hostach z T3 (nixos: T3 desktop, raspberry-pi-4:
# `t3 serve`): systemowa polityka /etc/t3code/policy.json z
# limits.telemetry = false. Wyłącza analitykę produktu (PostHog na
# ingest.t3.codes, z serwera i zdarzenia klienta WWW przekazywane przez serwer)
# oraz ślady relay T3 Connect, w serwerze i w aplikacji desktop. W odróżnieniu
# od T3CODE_TELEMETRY_ENABLED plik należy do roota: konto agenta ani sesja T3
# nie włączą telemetrii z powrotem.
#
# T3 czyta politykę tylko przy starcie, a pliku, którego nie umie w pełni
# wyegzekwować (nieznany klucz, inna schemaVersion), nie przyjmuje i wtedy się
# nie uruchamia. Dlatego build sprawdza ją `t3 policy check` tej samej wersji
# T3 z llm-agents: niezgodność po aktualizacji wejścia psuje build, nie T3.
#
# Sprawdzenie: na RPi `t3code policy show` (polityka wczytana przez działający
# serwer); w T3 (desktop i WWW) Ustawienia pokazują „<organization> turned off
# anonymous usage data.”.
{ inputs, ... }:
{
  flake.modules.nixos.base-t3code-policy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      t3code = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code.unwrapped;
      policy = (pkgs.formats.json { }).generate "t3code-policy.json" {
        schemaVersion = 1;
        # T3 pokazuje ją jako „Managed by …”.
        organization = "github:${config.customTop.owner}/${config.customTop.repository.name}";
        limits.telemetry = false;
      };
    in
    {
      environment.etc."t3code/policy.json".source = pkgs.runCommand "t3code-policy.json" { } ''
        HOME=$TMPDIR ${lib.getExe' t3code "t3"} policy check ${policy}
        cp ${policy} $out
      '';
    };
}
