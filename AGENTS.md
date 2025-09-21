# Repository Guidelines
## Project Structure & Module Organization
Core FastAPI app lives in `server.py`; it exposes `/webhook`, `/ws/{channel}`, `/ws`, `/health`, and the static status page. Shared helpers such as `parse_token_config`, in-memory queues, and middleware sit near the top of the module; keep related logic together to avoid hidden globals. `client.py` is a minimal WebSocket subscriber you can adapt for smoke tests. Tests live in `test_server.py` and rely on `pytest` fixtures to spin up the ASGI app. Deployment aids (`hooknsock.sh`, `hooknsock.service`, `webhookrelay.service`) automate provisioning; update them whenever you change startup expectations. Environment samples live in `.env`; never check in secrets beyond placeholders.

## Build, Test, and Development Commands
Create a virtualenv with `python -m venv venv` and install dependencies via `pip install -r requirements.txt` (or `requirements-dev.txt` for tooling). Run the API locally with `uvicorn server:app --reload --host 0.0.0.0 --port 8000`. Execute the sample client using `python client.py` after exporting `WEBSOCKET_URL` and `AUTH_TOKEN`. Automated setup for servers stays in `hooknsock.sh`; dry-run with `bash hooknsock.sh --help` before applying changes.

## Coding Style & Naming Conventions
Format code with `black` (88 columns) and lint with `flake8`; both targets expect 4-space indentation and idiomatic Python typing hints. Use snake_case for functions and variables, SCREAMING_SNAKE_CASE for settings, and short imperative docstrings when behaviour is non-obvious. Keep module-level constants grouped with their parsing helpers, and prefer async functions for I/O paths.

## Testing Guidelines
Use `pytest` with `pytest-asyncio` for coroutine tests. Mirror the `test_*.py` naming pattern and `async def test_*` functions to ensure discovery. Run the suite with `pytest` or `pytest -k channel` to focus on WebSocket routing scenarios. Aim to cover new branches (token parsing, channel filtering) and update fixtures if you change default env values.

## Commit & Pull Request Guidelines
Follow the existing concise style: short lowercase summaries such as `fix install script` or `add multi-channel support`. Reference related issues in the body and mention config changes explicitly. Pull requests should explain impact, note required env updates, and attach logs or curl/websocket transcripts when altering request flows.

## Security & Configuration Tips
- Use `python scripts/generate_tokens.py --service <channel> --env-file /etc/hooknsock/webhook.env --show` to mint or rotate secrets; the helper sets `chmod 600` automatically.
- Production tokens live in `/etc/hooknsock/webhook.env` and should never be checked into git; `.env` is for local overrides only.
- Leave `DISABLE_SYSTEM_INFO=true` on exposed deployments and document channel/domain mappings alongside any sensitive runbooks in `local_only.md`.

