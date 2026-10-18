# smart-offload

Inteligentny offloading obliczeń. Aplikacja iOS wykonuje ciężkie zadania, takie jak detekcja
obiektów z kamery albo OCR, i sama decyduje, czy liczyć lokalnie na telefonie, czy wysłać
do MacBooka w sieci lokalnej. O decyzji przesądzają poziom baterii, jakość sieci, opóźnienie
i obciążenie CPU.

## Budowanie

```sh
swift build
swift test
swift run offload-worker
```
