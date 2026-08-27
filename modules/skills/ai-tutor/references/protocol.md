# Protokół nauczania — pełna specyfikacja

## FAZA 0 — BRIEF (jeśli nieznany)

Zbierz od użytkownika:
1. Cel nauki — konkretnie, w stylu "rozumiem X na tyle, żeby umieć Y".
2. Kontekst — poziom, wykształcenie, czas dostępny (np. 2 h dziennie).
3. Motywacja — do czego to użytkownika (wpływa na dobór przykładów:
   fizyka ≠ programowanie ≠ "zrozumienie świata").

## NOTATNIK SESJI (plik `.md`)

Od fazy PROBE twórz i prowadź plik `~/nauka/ai-tutor/<temat>-<YYYY-MM-DD>.md`
(fallback: `<temat>.md` w cwd). Zapisuj w nim **na bieżąco**:
- wszystkie pytania (sonda + quizy) wraz z odpowiedziami ucznia i ocenami ✅/⚠️/❌,
- raport sondy, diagram Mermaid planu, podsumowania węzłów,
- wynik testu integracyjnego i plan powtórek.

Struktura: nagłówki per faza/węzeł, pytania jako listy numerowane, diagramy
w blokach ```mermaid. Aktualizuj plik po każdej rundzie pytań — nie zbieraj
wszystkiego na koniec. Na końcu sesji podaj uczniowi ścieżkę do pliku.

## FAZA 1 — PROBE (sonda diagnostyczna)

Cel: zlokalizować krawędź wiedzy (knowledge edge) — miejsce, gdzie pewna wiedza
kończy się, a luka zaczyna.

- 4–8 krótkich pytań o rosnącej trudności: od podstaw pod tematem do celu.
- Binary search: po każdej odpowiedzi zawężaj przedział "wiem na pewno / nie wiem".
- Mieszaj typy: konceptualne (intuicja), rachunkowe (umiejętność), metajęzykowe
  (notacja/terminologia).
- NIE tłumacz podczas sondowania — tylko diagnozuj. Na starcie powiedz, że
  błędne odpowiedzi to dane, nie porażka.
- Kończ raportem (format: references/templates.md):
  co ✅ opanowane, gdzie ⚠️ niepewne, gdzie ❌ luki, gdzie dokładnie krawędź.
- Treść pytań diagnostycznych i odpowiedzi ucznia zapisuj do notatnika `.md`
  (sekcja `## PROBE`).

## FAZA 2 — PLAN (graf zależności)

1. Zbuduj DAG od pojęć bazowych (potwierdzonych/odrzuconych przez sondę) do celu.
2. Wyrenderuj jako Mermaid `graph TD` z oznaczeniami: ✅ opanowane, 🎯 cel,
   bez oznaczenia = do nauki.
3. Zaproponuj kolejność i podział na sesje, jeśli graf duży.
4. Graf zmusza do pełnego rozplanowania — nie gomuj pojęć wymagających
   osobnych kroków, nie idź na skróty.
5. Fakty, wzory, jednostki użyte w planie zweryfikuj w tle; wątpliwe zaznacz.

## FAZA 3 — TEACH (pętla na węzeł)

1. **Dlaczego:** jedno zdanie o roli węzła w grafie (co odblokuje).
2. **Wyjaśnienie:** intuicja PRZED formalizmem, konkretny przykład PRZED
   definicją. Wizualizuj: Mermaid dla struktur/zależności, SVG dla pojęć
   geometrycznych (wygeneruj kod/render).
3. **QUIZ obowiązkowy (odblokowuje kolejny węzeł):** 2–4 pytania, co najmniej
   jedno aktywne (przelicz przykład / zastosuj / wyjaśnij własnymi słowami),
   nie tylko wyboru. Trzy funkcje quizu: (a) twarda weryfikacja — przeciwdziała
   złudzeniu kompetencji, (b) kalibracja — wyniki korygują tempo i głębokość,
   (c) active recall — utrwala pamięć długotrwałą.
4. **Reakcja na wynik:**
   - ✅ 100% — krótka pochwała, następny węzeł.
   - ⚠️ częściowe — micro-remediation: doprecyzuj dokładnie lukę, 1 pytanie
     kontrolne, potem dalej.
   - ❌ fundamentalna luka — nie idź dalej; wstaw do grafu dodatkowy węzeł
     naprawczy i wróć do kroku 2.
5. **Podsumowanie węzła:** 2–3 zdania gotowe do wklejenia do notatek.
6. **Zapis:** pytania quizu, odpowiedzi ucznia i oceny dopisuj do sekcji
   `## Węzeł: <nazwa>` w notatniku `.md`; tam samo trafia podsumowanie węzła.

## FAZA KOŃCOWA — DOMKNIĘCIE

- Test integracyjny łączący ≥3 węzły (im bliższe realnemu celowi, tym lepsze).
- Mapa: czego się nauczono vs. plan (odhaczone węzły).
- Spaced repetition: daty przypomnień (1 dzień / 1 tydzień / 1 miesiąc)
  z pytaniami do samodzielnego powtórzenia.
- Dopisz powyższe do notatnika `.md` (sekcja `## Domknięcie`) i podaj uczniowi
  pełną ścieżkę do pliku.
