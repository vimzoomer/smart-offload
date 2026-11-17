# smart-offload

An iPhone app that recognizes objects and text (OCR) from the camera and, for every frame,
decides whether to compute locally or send it to a MacBook on the same Wi-Fi network.
Each MacBook runs a worker that advertises itself via Bonjour and returns the result.

## Decision

The phone compares the estimated cost of both options and picks the cheaper one:

- local: predicted inference time on the phone + energy penalty when the battery is low,
- remote: frame transfer time + latency to the worker + inference time on the Mac.

Input signals: battery level and low power mode, network type and bandwidth,
RTT to each worker, CPU load and thermal state of the phone.
Every decision is logged together with its inputs and the measured execution time.

## Building

Requires Xcode 16+ (Swift 6).

    swift build                 # library and worker
    swift test
    swift run offload-worker    # run the worker on a Mac

The iPhone app lives in `App/SmartOffload.xcodeproj`. Open it in Xcode, pick your team under
Signing & Capabilities, and run it on a phone connected to the same Wi-Fi network as the worker.
The app asks for camera and local network access on first launch.

Decisions are appended to `decisions.jsonl` in the app's Documents folder; use the share link
in the app or the Files app to export it.
