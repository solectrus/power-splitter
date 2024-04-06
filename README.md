[![Continuous integration](https://github.com/solectrus/power-splitter/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/power-splitter/actions/workflows/push.yml)

# Power Splitter

Reads grid_import_power and splits it to various consumers.

## Requirements

- InfluxDB 2
- Linux machine with Docker installed

## Getting started

1. Make sure that your InfluxDB2 database is ready (not subject of this README)

2. Prepare an `.env` file (see `.env.example`)

3. Run the Docker container on your Linux box:

   ```bash
   docker compose up
   ```

The Docker image supports multiple platforms: `linux/amd64`, `linux/arm64`

## Development

For development you need a recent Ruby setup. On a Mac, I recommend [rbenv](https://github.com/rbenv/rbenv).

### Run the app

```bash
bundle exec app.rb
```

### Run tests

```bash
bundle exec rake
```

### Run linter

```bash
bundle exec rubocop
```

## License

Copyright (c) 2024 Georg Ledermann <georg@ledermann.dev>
