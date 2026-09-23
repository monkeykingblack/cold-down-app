# Flydigi BS3 Pro HID Contract

## Device match

- Vendor ID: `0x37D7`
- Product ID: `0x1004`
- Corroborating vendor usage page: `0xFFA0`
- Corroborating usage: `0x00FF`
- Product/firmware strings may refine capabilities but cannot override a vendor/product mismatch.

The controller registers native HID attach and removal callbacks. A removed device remains represented as disconnected. When automatic reconnect is enabled, a matching attachment starts only read-only `0x22` and `0x25` state queries. Mutating mode-entry and speed reports remain blocked until speed capabilities are verified.

## Output report

Fixed length: 25 bytes.

| Offset | Length | Meaning |
|--------|--------|---------|
| 0 | 1 | Report ID `0x02` |
| 1 | 2 | Marker `0x5A 0xA5` |
| 3 | 1 | Allowed command ID |
| 4 | 1 | Length: payload byte count + 2 |
| 5 | N | Typed payload |
| 5 + N | 1 | Low byte of additive sum from command through payload |
| remaining | variable | Zero padding to 25 bytes |

The decoder accepts input with or without a leading report ID, validates marker, declared length, bounds, and checksum, and preserves the command and typed payload.

## Allowed MVP commands

| Command | Direction | Payload | Accepted response |
|---------|-----------|---------|-------------------|
| `0x22` query RPM | Host → device | Empty | Matching valid frame containing readable current/target RPM |
| `0x25` query work mode | Host → device | Empty | Matching valid frame containing readable mode when supported |
| `0x23` enter real-time RPM | Host → device | Empty | Status `0x01` success or `0x03` already active |
| `0x21` set real-time RPM | Host → device | Little-endian UInt16 target | Status `0x01` success |

Commands `0x05` and `0x06` are explicitly forbidden. No raw send, RGB, firmware, reset, factory initialization, power, zero-speed stop, or exit-real-time API is exposed in production MVP.

## Transaction rules

1. Validate typed command and capability.
2. Register the expected response before writing.
3. Write one complete 25-byte report.
4. Ignore unrelated periodic frames and responses with invalid checksums.
5. Complete only on the matching command with an accepted status/payload.
6. Time out an attempt after 900 ms.
7. Retry at most twice, for three total attempts.
8. Cancel immediately on detach.

The transport serializes whole transactions, not just output writes. A reconnect never replays the last mutating command automatically; policy reevaluates current fresh state first.

## Speed capability rule

Every speed capability contains minimum, maximum, positive step, unit, and provenance: `unverified`, `deviceVerified`, `auditedModel`, or `deterministicMock`.

- `deviceVerified` is accepted only when the device/firmware capability exchange is itself documented and validated.
- `auditedModel` is keyed by VID, PID, and firmware/capability identity and cites a physical-validation record.
- `deterministicMock` is accepted only by the mock transport.
- `unverified`, missing, stale, inverted, non-positive-step, or otherwise malformed ranges expose connection/read state but set write availability to `capabilityLimited` or invalid capabilities.

The real transport may send mutating `0x23` or `0x21` reports only for `deviceVerified` or `auditedModel` capabilities. Until then, controls remain disabled with one concise capability-limited message and no mutating report is emitted. A target is rounded to the supported step and clamped before encoding, but neither rounding nor clamping can make unverified evidence safe. Reconnect never replays a previous target.
