from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel
from typing import Optional
import sqlite3
import uuid
import time
import threading
from pathlib import Path
from pygments import highlight
from pygments.lexers import get_lexer_by_name, TextLexer
from pygments.formatters import HtmlFormatter

PYGMENTS_CSS = HtmlFormatter(style="monokai", linenos="table").get_style_defs(".highlight")

def render_highlight(content: str, language: str) -> str:
    try:
        lexer = get_lexer_by_name(language, stripall=True)
    except Exception:
        lexer = TextLexer()
    formatter = HtmlFormatter(style="monokai", linenos="table", cssclass="highlight")
    return highlight(content, lexer, formatter)

BASE_DIR = Path(__file__).parent.parent

app = FastAPI(title="PasteBin", description="Self-hosted minimal pastebin")
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=BASE_DIR / "templates")

DB_PATH = BASE_DIR / "data" / "paste.db"

def get_db():
    DB_PATH.parent.mkdir(exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS pastes (
            id TEXT PRIMARY KEY,
            title TEXT,
            content TEXT NOT NULL,
            language TEXT DEFAULT 'plaintext',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            expires_at INTEGER,
            archived INTEGER DEFAULT 0,
            views INTEGER DEFAULT 0
        )
    """)
    conn.commit()
    conn.close()

init_db()

# --- Background TTL cleanup ---
def ttl_cleanup():
    while True:
        try:
            now = int(time.time())
            conn = get_db()
            conn.execute(
                "UPDATE pastes SET archived=1 WHERE expires_at IS NOT NULL AND expires_at <= ? AND archived=0",
                (now,)
            )
            conn.commit()
            conn.close()
        except Exception:
            pass
        time.sleep(60)

t = threading.Thread(target=ttl_cleanup, daemon=True)
t.start()

# --- Models ---
class PasteCreate(BaseModel):
    title: Optional[str] = None
    content: str
    language: Optional[str] = "plaintext"
    ttl_seconds: Optional[int] = None  # None = never expires

class PasteUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    language: Optional[str] = None
    ttl_seconds: Optional[int] = None

# --- Helpers ---
def row_to_dict(row):
    if row is None:
        return None
    d = dict(row)
    d["expired"] = bool(d.get("expires_at") and d["expires_at"] <= int(time.time()))
    return d

# --- Web UI routes ---
@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    conn = get_db()
    pastes = conn.execute(
        "SELECT * FROM pastes WHERE archived=0 ORDER BY created_at DESC"
    ).fetchall()
    archived = conn.execute(
        "SELECT * FROM pastes WHERE archived=1 ORDER BY updated_at DESC"
    ).fetchall()
    conn.close()
    return templates.TemplateResponse("index.html", {
        "request": request,
        "pastes": [row_to_dict(p) for p in pastes],
        "archived": [row_to_dict(p) for p in archived],
    })

@app.get("/new", response_class=HTMLResponse)
async def new_paste_form(request: Request):
    return templates.TemplateResponse("edit.html", {"request": request, "paste": None})

@app.get("/p/{paste_id}", response_class=HTMLResponse)
async def view_paste(request: Request, paste_id: str):
    conn = get_db()
    paste = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    if not paste:
        conn.close()
        raise HTTPException(status_code=404)
    conn.execute("UPDATE pastes SET views=views+1 WHERE id=?", (paste_id,))
    conn.commit()
    conn.close()
    paste_dict = row_to_dict(paste)
    highlighted = render_highlight(paste_dict["content"], paste_dict.get("language", "plaintext"))
    return templates.TemplateResponse("view.html", {
        "request": request,
        "paste": paste_dict,
        "highlighted_content": highlighted,
        "pygments_css": PYGMENTS_CSS,
    })

@app.get("/p/{paste_id}/edit", response_class=HTMLResponse)
async def edit_paste_form(request: Request, paste_id: str):
    conn = get_db()
    paste = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    conn.close()
    if not paste:
        raise HTTPException(status_code=404)
    return templates.TemplateResponse("edit.html", {"request": request, "paste": row_to_dict(paste)})

# --- API routes ---
@app.get("/api/pastes")
def api_list(archived: bool = False):
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM pastes WHERE archived=? ORDER BY created_at DESC",
        (1 if archived else 0,)
    ).fetchall()
    conn.close()
    return [row_to_dict(r) for r in rows]

@app.post("/api/pastes", status_code=201)
def api_create(paste: PasteCreate):
    now = int(time.time())
    paste_id = uuid.uuid4().hex[:10]
    expires_at = now + paste.ttl_seconds if paste.ttl_seconds else None
    conn = get_db()
    conn.execute(
        "INSERT INTO pastes (id, title, content, language, created_at, updated_at, expires_at) VALUES (?,?,?,?,?,?,?)",
        (paste_id, paste.title, paste.content, paste.language, now, now, expires_at)
    )
    conn.commit()
    row = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    conn.close()
    return row_to_dict(row)

@app.get("/api/pastes/{paste_id}")
def api_get(paste_id: str):
    conn = get_db()
    row = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Paste not found")
    conn = get_db()
    conn.execute("UPDATE pastes SET views=views+1 WHERE id=?", (paste_id,))
    conn.commit()
    conn.close()
    return row_to_dict(row)

@app.patch("/api/pastes/{paste_id}")
def api_update(paste_id: str, update: PasteUpdate):
    conn = get_db()
    row = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Paste not found")
    now = int(time.time())
    d = row_to_dict(row)
    new_content = update.content if update.content is not None else d["content"]
    new_title = update.title if update.title is not None else d["title"]
    new_lang = update.language if update.language is not None else d["language"]
    if update.ttl_seconds is not None:
        new_expires = now + update.ttl_seconds if update.ttl_seconds > 0 else None
    else:
        new_expires = d["expires_at"]
    conn.execute(
        "UPDATE pastes SET title=?, content=?, language=?, updated_at=?, expires_at=? WHERE id=?",
        (new_title, new_content, new_lang, now, new_expires, paste_id)
    )
    conn.commit()
    row = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    conn.close()
    return row_to_dict(row)

@app.post("/api/pastes/{paste_id}/archive")
def api_archive(paste_id: str):
    conn = get_db()
    row = conn.execute("SELECT * FROM pastes WHERE id=?", (paste_id,)).fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404)
    conn.execute("UPDATE pastes SET archived=1 WHERE id=?", (paste_id,))
    conn.commit()
    conn.close()
    return {"status": "archived"}

@app.post("/api/pastes/{paste_id}/unarchive")
def api_unarchive(paste_id: str):
    conn = get_db()
    conn.execute("UPDATE pastes SET archived=0, expires_at=NULL WHERE id=?", (paste_id,))
    conn.commit()
    conn.close()
    return {"status": "active"}

@app.delete("/api/pastes/{paste_id}", status_code=204)
def api_delete(paste_id: str):
    conn = get_db()
    conn.execute("DELETE FROM pastes WHERE id=?", (paste_id,))
    conn.commit()
    conn.close()

# Form handlers (from UI)
@app.post("/form/create")
async def form_create(request: Request):
    form = await request.form()
    ttl_val = form.get("ttl_seconds")
    ttl = int(ttl_val) if ttl_val and ttl_val != "0" else None
    p = PasteCreate(
        title=form.get("title") or None,
        content=form.get("content"),
        language=form.get("language", "plaintext"),
        ttl_seconds=ttl,
    )
    result = api_create(p)
    return RedirectResponse(f"/p/{result['id']}", status_code=303)

@app.post("/form/update/{paste_id}")
async def form_update(request: Request, paste_id: str):
    form = await request.form()
    ttl_val = form.get("ttl_seconds")
    ttl = int(ttl_val) if ttl_val and ttl_val != "" else None
    u = PasteUpdate(
        title=form.get("title") or None,
        content=form.get("content"),
        language=form.get("language", "plaintext"),
        ttl_seconds=ttl,
    )
    api_update(paste_id, u)
    return RedirectResponse(f"/p/{paste_id}", status_code=303)

@app.post("/form/archive/{paste_id}")
async def form_archive(paste_id: str):
    api_archive(paste_id)
    return RedirectResponse("/", status_code=303)

@app.post("/form/unarchive/{paste_id}")
async def form_unarchive(paste_id: str):
    api_unarchive(paste_id)
    return RedirectResponse("/", status_code=303)

@app.post("/form/delete/{paste_id}")
async def form_delete(paste_id: str):
    api_delete(paste_id)
    return RedirectResponse("/", status_code=303)
