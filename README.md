# smart-offload

Aplikacja na iPhone'a, która rozpoznaje obiekty i tekst (OCR) na obrazie z kamery
i dla każdej klatki sama decyduje, czy policzyć wynik lokalnie, czy wysłać klatkę
do jednego z MacBooków w tej samej sieci Wi-Fi i odebrać gotowy wynik.
MacBooki tworzą prywatną "chmurę obliczeniową": każdy uruchamia workera, który
rozgłasza się przez Bonjour, przyjmuje klatki i odsyła wykryte obiekty lub tekst.

## Co jest liczone

- detekcja obiektów na klatce z kamery (model YOLO przez Core ML),
- OCR, czyli rozpoznanie tekstu na zdjęciu (Vision).

To samo zadanie, ten sam model i ten sam format wyniku po obu stronach,
dzięki czemu decyzja "gdzie liczyć" nie zmienia tego, co widzi użytkownik,
tylko czas, zużycie baterii i obciążenie telefonu.

## Na jakiej podstawie podejmowana jest decyzja

Przed każdym zadaniem telefon zbiera cztery sygnały:

| sygnał | źródło na iOS | jak wpływa |
|---|---|---|
| poziom baterii i tryb oszczędzania | `UIDevice.batteryLevel`, `isLowPowerModeEnabled` | niska bateria przesuwa decyzję w stronę wysyłania |
| jakość sieci | `NWPathMonitor` (Wi-Fi/komórkowa, metered, przepustowość) | brak Wi-Fi lub słabe łącze wymusza liczenie lokalne |
| opóźnienie do workera | cykliczny ping do każdego znalezionego MacBooka | wysokie RTT zjada zysk z szybszego sprzętu |
| obciążenie CPU i stan termiczny | `host_processor_info`, `ProcessInfo.thermalState` | gorący lub zajęty telefon oddaje pracę |

Worker w odpowiedzi na ping zgłasza własne obciążenie, więc telefon może też
wybrać najmniej zajęty MacBook spośród kilku.

Decyzja sprowadza się do porównania szacowanego kosztu obu wariantów:

- **lokalnie**: przewidywany czas inferencji na telefonie (uczony z poprzednich pomiarów)
  plus kara za energię, rosnąca gdy bateria spada;
- **zdalnie**: czas przesłania klatki przy zmierzonej przepustowości, RTT,
  czas inferencji na workerze (z jego ostatnich raportów) plus kara za niepewność sieci.

Wygrywa tańszy wariant. Każda decyzja jest logowana razem z sygnałami wejściowymi
i rzeczywistym czasem wykonania, co pozwala kalibrować model kosztu i porównać
go później ze strategiami prostymi (zawsze lokalnie, zawsze zdalnie).

## Z czego się składa

- biblioteka `OffloadCore` w czystym Swifcie: silnik decyzji, protokół wiadomości,
  pomiary; wspólna dla iOS i macOS, testowana jednostkowo,
- `offload-worker`: program na macOS rozgłaszający się przez Bonjour i wykonujący zadania,
- aplikacja iOS z podglądem kamery, wynikami i panelem pokazującym, co zdecydował silnik i dlaczego.

## Budowanie

Wymagany Xcode 16 lub nowszy (Swift 6).

```sh
swift build                 # biblioteka i worker
swift test                  # testy silnika decyzji
swift run offload-worker    # uruchomienie workera na Macu
```

Aplikację iOS buduje się z Xcode po dodaniu projektu w katalogu `App/`.
