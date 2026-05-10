# paste.sh

A self-hosted pastebin with a terminal aesthetic, built with FastAPI and SQLite. Designed for homelabs and local networks.

![paste list](screenshots/main.png)

## Features

- Syntax highlighting via Pygments (Monokai theme)
- TTL-based expiration with automatic cleanup
- Archive/unarchive pastes
- Download pastes with correct file extension
- View counter
- REST API
- Terminal-style UI (green on dark, monospace font)
- CodeMirror 6 editor with language switching

## Screenshots

| List | Viewer |
|------|--------|
| ![list](screenshots/main.png) | ![viewer](screenshots/viewer.png) |

| Editor | New paste |
|--------|-----------|
| ![editor](screenshots/editor.png) | ![new](screenshots/new.png) |

## Stack

- **Backend**: FastAPI + SQLite
- **Editor**: CodeMirror 6 (bundled with esbuild)
- **Highlighting**: Pygments
- **Container**: Docker (multi-stage build)

## Quick Start

```yaml
# docker-compose.yml
services:
  paste-sh:
    build: .
    ports:
      - "8090:8090"
    volumes:
      - ./data:/app/data
      - ./exports:/app/exports
    networks:
      - GeneralNetwork

networks:
  GeneralNetwork:
    external: true
```

```bash
docker compose up -d --build
```

The server will be available at `http://localhost:8090`.

## API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/pastes` | List all active pastes |
| `POST` | `/api/pastes` | Create a paste |
| `PATCH` | `/api/pastes/{id}` | Update a paste |
| `DELETE` | `/api/pastes/{id}` | Delete a paste |
| `POST` | `/api/pastes/{id}/archive` | Archive a paste |
| `POST` | `/api/pastes/{id}/unarchive` | Unarchive a paste |

### Create a paste

```bash
curl -s -X POST http://localhost:8090/api/pastes \
  -H "Content-Type: application/json" \
  -d '{
    "title": "my script",
    "content": "echo hello world",
    "language": "bash",
    "ttl_seconds": 604800
  }'
```

### Response

```json
{
  "id": "a1b2c3d4",
  "title": "my script",
  "content": "echo hello world",
  "language": "bash",
  "ttl_seconds": 604800,
  "created_at": 1710000000,
  "archived": false,
  "views": 0
}
```

Set `ttl_seconds` to `null` for pastes that never expire.

## Supported Languages

`plaintext` `python` `bash` `javascript` `typescript` `json` `yaml` `toml` `html` `css` `sql` `go` `rust` `c` `cpp` `java` `kotlin` `ruby` `php` `markdown` `xml`

## Clients

### paste.sh CLI

A bash client for use from the terminal or from post-download automation scripts.

```bash
# Create
paste new -t "my script" -l bash -e 7d < script.sh

# List
paste ls

# View
paste cat <id>

# Download
paste dl <id> ~/Downloads/

# Delete
paste rm <id>
```

### PasteDrop (Android)

Offline-first Android app. Integrates with the system share menu — select text in any app, share to PasteDrop, and it will upload to the server or queue it locally if the server is unreachable.

- Offline queue with automatic sync when the server comes back online
- Pull-to-refresh to fetch pastes from the server
- Edit pastes by opening them in the browser
- Language and TTL selection

### PasteDrop (KDE Plasma plasmoid)

Panel widget for KDE Plasma 6. Drag text onto the widget to create a paste instantly. The URL is copied to the clipboard automatically.

- Configurable server URL, default TTL and default language
- Visual feedback (loading, success, error states)

## Project Structure

```
paste.sh/
├── app/
│   └── main.py          # FastAPI application
├── templates/
│   ├── base.html        # Base layout
│   ├── index.html       # Paste list
│   ├── view.html        # Paste viewer
│   └── edit.html        # CodeMirror editor
├── cm-build/
│   ├── editor.js        # CodeMirror 6 entry point
│   └── package.json     # esbuild + CM6 dependencies
├── Dockerfile           # Multi-stage: node (bundle) → python (serve)
├── docker-compose.yml
└── requirements.txt
```

## License

MIT
