[![Continuous integration](https://github.com/solectrus/power-splitter/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/power-splitter/actions/workflows/push.yml)
[![Maintainability](https://qlty.sh/badges/7146b60b-ca86-4b1d-9e59-c18856a36fbf/maintainability.svg)](https://qlty.sh/gh/solectrus/projects/power-splitter)
[![wakatime](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/018eb19e-5a00-49ae-966c-943dba618dc8.svg)](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/018eb19e-5a00-49ae-966c-943dba618dc8)
[![Code Coverage](https://qlty.sh/badges/7146b60b-ca86-4b1d-9e59-c18856a36fbf/coverage.svg)](https://qlty.sh/gh/solectrus/projects/power-splitter)

# Power Splitter

This tool retrieves power consumption data from an InfluxDB database. It then divides up the total power imported from the grid among various users, such as a heat pump, a wallbox, and the household.

This enables SOLECTRUS to accurately calculate the electricity usage and costs for each distinct consumer. This is especially useful in settings where multiple devices or systems are drawing power.

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
