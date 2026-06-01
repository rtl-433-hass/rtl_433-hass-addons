# Tests

Automated tests for the rtl_433 add-on. These run in CI on every push/PR and
can be run locally.

## Layout

- `tests/rtl_433/test_run.bats` — BATS unit tests for the `rtl_433/run.sh`
  helper functions.
- `tests/config/validate_configs.py` — config validator for the add-on
  `config.json` files.

## Running

```sh
bats -r tests/                          # BATS unit tests
python3 tests/config/validate_configs.py # config validation
```

The `-r` flag tells bats to recurse into `tests/rtl_433/`.

## Fixture convention

`run.sh` is `main()`-guarded, so the BATS tests source it to call its functions
directly. To exercise `enumerate_rtlsdr_devices` without real hardware, the
tests build a mock sysfs tree in a temp directory and point `SYSFS_USB_BASE` at
it.

## Prerequisites

- `bats` — install via `apt-get install -y bats`, or use
  [bats-core](https://github.com/bats-core/bats-core).
- Python 3 — standard library only, no extra packages required.
