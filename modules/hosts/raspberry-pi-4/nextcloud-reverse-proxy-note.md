# Wyjaśnienie konfiguracji Reverse Proxy (Cloudflare Tunnel) w Nextcloud

Poniższy fragment kodu z pliku `nextcloud.nix` odpowiada za poprawne działanie Nextcloud za tzw. *reverse proxy* – w tym przypadku jest to usługa `cloudflared` (Cloudflare Tunnel), która zajmuje się szyfrowaniem i zakończeniem połączenia HTTPS.

```nix
      services.nextcloud.settings = {
        overwriteprotocol = "https";
        "overwrite.cli.url" = "https://${custom.site.full}";
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
```

## Szczegółowe omówienie:

1. **`overwriteprotocol = "https";`**
   Z technicznego punktu widzenia aplikacja Nextcloud działa u Ciebie lokalnie na niezabezpieczonym porcie 80 (HTTP). Cloudflare Tunnel "zdejmuje" z zewnątrz szyfrowanie HTTPS i przesyła ruch po HTTP wewnątrz maszyny do usługi Nextcloud. Z tego powodu Nextcloud myśli, że domyślnym protokołem komunikacji jest HTTP i w takim też schemacie próbuje generować np. linki do logowania z aplikacji mobilnej (co powodowało błędy).
   Ta opcja wymusza (nadpisuje) informację protokołu, instruując Nextcloud: *"Bez względu na to, jakim protokołem otrzymałeś ruch wewnętrznie, wiedz, że po stronie klienta było to `https` i zawsze generuj wszystkie linki powrotne i zasoby w HTTPS"*.

2. **`"overwrite.cli.url" = "https://${custom.site.full}";`**
   Adres używany w narzędziu wiersza poleceń Nextcloud (tzw. `occ` - OwnCloud Console). 
   Gdy system wyzwala pewne zdarzenia działając całkowicie w tle (np. skrypty systemowe, zadania Cron, wysyłka e-maila o udostępnieniu pliku), brakuje mu żądania od przeglądarki z publicznym adresem URL.
   Ta flaga działa jak bezpiecznik i informuje środowisko tła Nextcloud, pod jakim publicznym adresem bazowym istnieje ta konkretna instancja. Bez tego linki rozsyłane np. w mailach wyglądałyby jak `http://localhost/index.php/...`.

3. **`trusted_proxies = [ "127.0.0.1" "::1" ];`**
   Pula adresów IP (tutaj pętla zwrotna: IPv4 i IPv6 maszyny lokalnej), którą Nextcloud traktuje jako *Zaufane Reverse Proxy*.
   Kiedy ruch idzie przez Cloudflare Tunnel, z perspektywy Nextcloud wszystkie zapytania i cały ruch pochodzą z `127.0.0.1` (od tunelu do serwera www).
   Ustawiając pętlę zwrotną jako zaufaną, Nextcloud zaczyna "ufać" zewnętrznym nagłówkom sieciowym doklejanym przez usługę Cloudflare. Najważniejszym z nich jest nagłówek `X-Forwarded-For`.
   Dzięki jego przetworzeniu, Twoje logi Nexcloud będą wyświetlały **prawdziwe adresy IP użytkowników** odwiedzających chmurę w internecie, a nie w kółko adres IP wewnętrznego localhosta. Jest to absolutnie krytyczne do prawidłowego działania ochrony przed *Brute Force* (np. banowanie IP po 5 nieudanych próbach wpisania hasła).
