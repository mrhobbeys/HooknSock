# Contributing

Thanks for your interest! This project is intended to be simple and easy to maintain. Please follow these guidelines:

## Development

- Use Python 3.10+.
- Prefer `venv` or `pipenv` for environment management.
- Run `gunicorn` with `uvicorn` worker class for production.
- Use `systemd` for service management (see README).

## Issues & PRs

- Please include reproduction steps or a clear description for bugs.
- For new features, explain the use case and keep the code simple.
- All code should be formatted with `black` and checked with `flake8`.

## Tests

- Use `pytest` for unit and integration tests.
- Add tests for new features.

## Security

- Never commit secrets or tokens!
- Use environment variables for sensitive data.

## License

MIT
