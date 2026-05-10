FROM node:20-slim AS cm-builder
WORKDIR /build
COPY cm-build/package.json .
RUN npm install --silent
COPY cm-build/editor.js .
RUN npx esbuild editor.js \
    --bundle \
    --minify \
    --format=iife \
    --global-name=PasteEditor \
    --outfile=editor.bundle.js

FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
COPY --from=cm-builder /build/editor.bundle.js /app/static/editor.bundle.js

RUN mkdir -p /app/data /app/static /app/exports

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8090"]
