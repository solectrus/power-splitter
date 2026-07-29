[![Continuous integration](https://github.com/solectrus/power-splitter/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/power-splitter/actions/workflows/push.yml)
[![Maintainability](https://qlty.sh/badges/7146b60b-ca86-4b1d-9e59-c18856a36fbf/maintainability.svg)](https://qlty.sh/gh/solectrus/projects/power-splitter)
[![wakatime](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/018eb19e-5a00-49ae-966c-943dba618dc8.svg)](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/018eb19e-5a00-49ae-966c-943dba618dc8)
[![Code Coverage](https://qlty.sh/badges/7146b60b-ca86-4b1d-9e59-c18856a36fbf/coverage.svg)](https://qlty.sh/gh/solectrus/projects/power-splitter)

# Power Splitter

This tool retrieves power consumption data from an InfluxDB database. It then divides up the total power imported from the grid among various users, such as a heat pump, a wallbox, and the household.

This enables SOLECTRUS to accurately calculate the electricity usage and costs for each distinct consumer. This is especially useful in settings where multiple devices or systems are drawing power.

See [CALCULATION.md](CALCULATION.md) for how the split is calculated.

## Requirements

- InfluxDB 2 database with a bucket filled with values for:
  - Grid import power
  - House power
  - Heatpump/Wallbox/Custom power
- Linux machine with Docker installed

## Getting started

1. Make sure that your InfluxDB2 database is ready (not subject of this README)

2. Prepare an `.env` file (see `.env.example`)

3. Run the Docker container on your Linux box:

   ```bash
   docker compose up
   ```

The Docker image supports multiple platforms: `linux/amd64`, `linux/arm64`

To force a data rebuild, you can send USR1 signal to the container:

```bash
docker compose kill --signal USR1 power-splitter
```

## Batteries charged from the grid

A home battery can be charged from the grid, so the energy taken out of it later
is not necessarily PV. To tell the two apart, the Power Splitter needs to see
both directions of the battery:

| Variable                                  | Description                                                                                                                            |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `INFLUX_SENSOR_BATTERY_CHARGING_POWER`    | Sensor for the power flowing into the battery, as `measurement:field`                                                                  |
| `INFLUX_SENSOR_BATTERY_DISCHARGING_POWER` | Sensor for the power flowing out of it. Without it there is nothing to tell the two apart by, and what leaves the battery counts as PV |

The sensor names and their format are the same as in SOLECTRUS, so the lines can
be copied over from its `.env`.

Once both sensors are there, grid energy stored in the battery is attributed to
the consumers taking it out again. There is no switch for it.

> [!IMPORTANT]
> The attribution needs a SOLECTRUS version that knows about the battery as a
> second source of grid electricity. Older versions expect the grid shares of all
> consumers to add up to the power imported from the grid, and scale them until
> they do. That not only undoes the attribution, it also drags down
> `battery_charging_power_grid` - a value that was correct before.

This version calculates the grid shares differently than the one before it, with
or without the battery sensors. Existing data is only overwritten where the new
calculation writes something, so old and new numbers would otherwise sit side by
side. After updating:

1. Force a rebuild (see above)
2. Reset the daily summaries in SOLECTRUS

See [CALCULATION.md](CALCULATION.md) for what these variables do to the
calculation, which fields are written, and where the limits are.

## Development

For development you need a recent Ruby setup. On a Mac, I recommend [rbenv](https://github.com/rbenv/rbenv).

### Run the app

```bash
bundle exec app.rb
```

### Run tests

```bash
bundle exec rspec
```

### Run linter

```bash
bundle exec rubocop
```

## License

Copyright (c) 2024-2026 Georg Ledermann <georg@ledermann.dev>
