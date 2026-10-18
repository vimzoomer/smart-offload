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
    swift test                  # decision engine tests
    swift run offload-worker    # run the worker on a Mac
