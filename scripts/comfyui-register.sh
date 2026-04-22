#!/usr/bin/env bash
# ComfyUI instance self-registration against my-hybrid-service (scheme D).
#
# Prerequisite: ComfyUI must be listening on 127.0.0.1:8188 before registration succeeds.
#   Typical start (adjust path to your image), run in another shell or your entrypoint first:
#     python /comfyui/main.py --listen 0.0.0.0 --port 8188
#   Or set COMFYUI_AUTO_START=1 so this script starts ComfyUI in the background before waiting
#   (see COMFYUI_LAUNCH_CMD below).
#
# Required environment variables:
#   COMFYUI_BACKEND_URL    - Base URL of my-hybrid-service (e.g. https://api.example.com)
#   COMFYUI_REGISTER_TOKEN - Same value as server COMFYUI_REGISTER_TOKEN
#
# Optional (auto-detected on Vast.ai / RunPod Pod when unset):
#   COMFYUI_PUBLIC_URL - This instance's public HTTP base URL (port mapping to container 8188)
#   PROVIDER           - vast | runpod-pod | other (stored in service_endpoints.provider)
#   INSTANCE_ID        - Provider instance id string
#
# Optional ComfyUI process:
#   COMFYUI_AUTO_START   - If 1/true/yes, start ComfyUI in the background before the wait loop
#   COMFYUI_LAUNCH_CMD   - Full shell command to start ComfyUI (default: python /comfyui/main.py --listen 0.0.0.0 --port 8188)
#
# Auto-detect priority: explicit COMFYUI_PUBLIC_URL > Vast > RunPod Pod
#   Vast:  COMFYUI_PUBLIC_URL = http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_8188}
#   RunPod: COMFYUI_PUBLIC_URL = http://${RUNPOD_PUBLIC_IP}:${RUNPOD_TCP_PORT_8188}
#
# Usage:
#   - Vast/RunPod: export COMFYUI_BACKEND_URL + COMFYUI_REGISTER_TOKEN; start ComfyUI, then run this script.
#   - Or: COMFYUI_AUTO_START=1 with the same exports so ComfyUI is started here.
#   - Other: set COMFYUI_PUBLIC_URL manually.
#
# Example (explicit URL, backward compatible):
#   COMFYUI_BACKEND_URL=https://your-api.com COMFYUI_REGISTER_TOKEN=secret \
#   COMFYUI_PUBLIC_URL=http://1.2.3.4:32067 PROVIDER=vast INSTANCE_ID=12345 \
#   bash /path/to/comfyui-register.sh

set -euo pipefail

: "${COMFYUI_BACKEND_URL:?set COMFYUI_BACKEND_URL}"
: "${COMFYUI_REGISTER_TOKEN:?set COMFYUI_REGISTER_TOKEN}"

# Derive COMFYUI_PUBLIC_URL / PROVIDER / INSTANCE_ID when not set (Vast / RunPod Pod).
detect_instance() {
  if [ -n "${COMFYUI_PUBLIC_URL:-}" ]; then
    export COMFYUI_PUBLIC_URL="${COMFYUI_PUBLIC_URL%/}"
    export PROVIDER="${PROVIDER:-other}"
    export INSTANCE_ID="${INSTANCE_ID:-}"
    echo "[comfyui-register] Using explicit COMFYUI_PUBLIC_URL provider=${PROVIDER} instance_id=${INSTANCE_ID:-<empty>}" >&2
    return
  fi

  if [ -n "${VAST_TCP_PORT_8188:-}" ] && [ -n "${PUBLIC_IPADDR:-}" ]; then
    COMFYUI_PUBLIC_URL="http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_8188}"
    PROVIDER="${PROVIDER:-vast}"
    INSTANCE_ID="${INSTANCE_ID:-${VAST_CONTAINERLABEL:-${CONTAINER_ID:-}}}"
    export COMFYUI_PUBLIC_URL PROVIDER INSTANCE_ID
    echo "[comfyui-register] Auto-detected Vast: url=${COMFYUI_PUBLIC_URL} provider=${PROVIDER} instance_id=${INSTANCE_ID:-<empty>}" >&2
    return
  fi

  if [ -n "${RUNPOD_TCP_PORT_8188:-}" ] && [ -n "${RUNPOD_PUBLIC_IP:-}" ]; then
    COMFYUI_PUBLIC_URL="http://${RUNPOD_PUBLIC_IP}:${RUNPOD_TCP_PORT_8188}"
    PROVIDER="${PROVIDER:-runpod-pod}"
    INSTANCE_ID="${INSTANCE_ID:-${RUNPOD_POD_ID:-}}"
    export COMFYUI_PUBLIC_URL PROVIDER INSTANCE_ID
    echo "[comfyui-register] Auto-detected RunPod Pod: url=${COMFYUI_PUBLIC_URL} provider=${PROVIDER} instance_id=${INSTANCE_ID:-<empty>}" >&2
    return
  fi

  echo "[comfyui-register] ERROR: cannot auto-detect public URL. Set COMFYUI_PUBLIC_URL or run on Vast.ai / RunPod Pod." >&2
  exit 1
}

detect_instance

# Optionally start ComfyUI in the background (same container). Skip if your entrypoint already runs it.
maybe_start_comfyui() {
  case "${COMFYUI_AUTO_START:-}" in
    1|true|yes) ;;
    *) return 0 ;;
  esac
  if [ -n "${COMFYUI_LAUNCH_CMD:-}" ]; then
    echo "[comfyui-register] COMFYUI_AUTO_START: launching via COMFYUI_LAUNCH_CMD" >&2
    bash -c "$COMFYUI_LAUNCH_CMD" &
  else
    echo "[comfyui-register] COMFYUI_AUTO_START: python /comfyui/main.py --listen 0.0.0.0 --port 8188 &" >&2
    python /comfyui/main.py --listen 0.0.0.0 --port 8188 &
  fi
}

maybe_start_comfyui

echo "[comfyui-register] Waiting for ComfyUI on 127.0.0.1:8188 ..."
until curl -fsS "http://127.0.0.1:8188/system_stats" >/dev/null 2>&1; do
  sleep 2
done

JSON_BODY=$(python3 -c "import json,os; i=os.environ.get('INSTANCE_ID','').strip(); print(json.dumps({
  'url': os.environ['COMFYUI_PUBLIC_URL'].rstrip('/'),
  'provider': os.environ.get('PROVIDER') or 'other',
  'instance_id': i if i else None,
}))")

echo "[comfyui-register] Registering with ${COMFYUI_BACKEND_URL} ..."
curl -fsS -X POST "${COMFYUI_BACKEND_URL%/}/api/v1/admin/endpoints/comfyui/register" \
  -H "Authorization: Bearer ${COMFYUI_REGISTER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$JSON_BODY"
echo ""

echo "[comfyui-register] Done. Exiting (no heartbeat loop)." >&2
