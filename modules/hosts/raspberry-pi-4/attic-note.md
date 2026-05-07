# Uruchomienie i konfiguracja Attic (Nix Binary Cache)

Ten dokument opisuje kroki potrzebne do skonfigurowania Attic po pierwszym wdrożeniu na Raspberry Pi oraz jak podłączyć do niego własny komputer (klienta).

Ponieważ moduł NixOS instaluje `atticd` jako usługę i korzysta z mechanizmu `DynamicUser`, nie mamy bezpośredniego dostępu do konta `atticd`. Moduł dostarcza jednak specjalny wrapper `atticd-atticadm`, który wie, jak załadować pliki konfiguracyjne i sekrety usługi.

## Krok 1: Wygenerowanie tokena administracyjnego (Na serwerze - RPi)

Zaloguj się na swoje Raspberry Pi przez SSH i wykonaj polecenie generujące token:

```bash
sudo atticd-atticadm make-token \
  --sub "admin" \
  --validity "1 year" \
  --pull "*" \
  --push "*" \
  --create-cache "*" \
  --configure-cache "*"
```

Wynikiem działania tego polecenia będzie długi ciąg znaków (JWT). Zapisz go bezpiecznie – to klucz dostępu do Twojego serwera Attic.

## Krok 2: Instalacja i logowanie na kliencie (Twój komputer)

Na maszynie deweloperskiej (z której będziesz wysyłać i pobierać paczki) musisz mieć narzędzie `attic` (dostępne w `nixpkgs`).

Zaloguj się używając wygenerowanego tokena:

```bash
# Schemat: attic login <nazwa_skrótowa> <adres_api> <token>
attic login rpi-cache https://cache.twojadomena.pl/ <TWÓJ_TOKEN_JWT>
```

> **Uwaga:** `<nazwa_skrótowa>` (tutaj `rpi-cache`) to tylko alias używany lokalnie na Twoim komputerze do identyfikacji serwera, na wypadek gdybyś korzystał z kilku serwerów Attic.

## Krok 3: Utworzenie pierwszego obszaru cache'a

Attic obsługuje wielodostępność (multi-tenancy) poprzez podział na oddzielne cache'e. Utwórz główny cache na swoje pakiety:

```bash
attic cache create rpi-cache:nixos-builds
```

## Krok 4: Wypychanie i używanie Cache'a

Aby wysłać własnoręcznie zbudowany wynik (np. konfigurację systemu) do cache'a:

```bash
attic push rpi-cache:nixos-builds result
```

Alternatywnie, możesz nasłuchiwać zmian w Nix store, aby Attic automatycznie wrzucał w tło to, co budujesz:

```bash
attic watch-store rpi-cache:nixos-builds
```

## Krok 5: Konfiguracja Nix na kliencie

Aby podczas kompilacji na Twoim komputerze lub innej maszynie Nix pobierał gotowe pakiety z RPi, pobierz klucz publiczny cache'a:

```bash
attic cache info rpi-cache:nixos-builds
# Poszukaj w wyjściu linii: Public key: nixos-builds:XXXXXXXXXXXXXXXXXXXXXXXXXX
```

Skonfiguruj system (np. w pliku `flake.nix` lub module ustawień Nixa), by korzystał z serwera:

```nix
nix.settings = {
  extra-substituters = [
    "https://cache.twojadomena.pl/nixos-builds"
  ];
  extra-trusted-public-keys = [
    "nixos-builds:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  ];
};
```
