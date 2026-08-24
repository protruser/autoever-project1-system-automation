#!/bin/bash
set -e
cd "$(dirname "$0")"
pnpm run build
pkill -f "vite.*preview" || true
sleep 1
nohup pnpm run preview -- --host 0.0.0.0 --port 8443 > ~/frontend.log 2>&1 &
disown
sleep 2
echo "rebuilt and restarted, pid: $(pgrep -f 'vite.*preview')"
