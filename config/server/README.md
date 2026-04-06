# Headless Server Mode

Run PAI-OpenCode as a headless server for programmatic control and batch processing.

## Start Server

```bash
# Inside the container
opencode serve --port 4096 --hostname 0.0.0.0

# From host (via Docker)
docker compose exec -d opencode-pai opencode serve --port 4096 --hostname 0.0.0.0
```

## Expose Port

Add to docker-compose.yml if needed:

```yaml
ports:
  - "4096:4096"
```

## API Usage

### Send a message

```bash
curl -X POST http://localhost:4096/sessions \
  -H "Content-Type: application/json" \
  -d '{"message": "Analyze the codebase structure"}'
```

### List sessions

```bash
curl http://localhost:4096/sessions
```

### Web Interface

```bash
opencode web --port 4096
# Opens browser-based PAI interface
```

## Batch Processing

For overnight/unattended work:

```bash
# Start headless
docker compose exec -d opencode-pai opencode serve

# Submit batch tasks
for task in "task1" "task2" "task3"; do
  curl -X POST http://localhost:4096/sessions \
    -d "{\"message\": \"$task\"}"
done
```

## Authentication

Set `OPENCODE_SERVER_PASSWORD` in .env for HTTP basic auth:

```
OPENCODE_SERVER_PASSWORD=your-secure-password
```
