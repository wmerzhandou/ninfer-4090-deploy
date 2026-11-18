#!/usr/bin/env bash
set -euo pipefail

api="${NINFER_BASE_URL:-http://127.0.0.1:8003/v1}"
api="${api%/}"
root="${api%/v1}"
key="${NINFER_API_KEY:-change-me}"
model="${NINFER_MODEL_ID:-qwen3.8-27b}"
image=""
skip_responses=0
skip_vision=0

while (($#)); do
  case "$1" in
    --base-url) api="${2:?--base-url requires a value}"; api="${api%/}"; root="${api%/v1}"; shift 2 ;;
    --api-key) key="${2:?--api-key requires a value}"; shift 2 ;;
    --model) model="${2:?--model requires a value}"; shift 2 ;;
    --image) image="${2:?--image requires a value}"; shift 2 ;;
    --skip-responses) skip_responses=1; shift ;;
    --skip-vision) skip_vision=1; shift ;;
    -h|--help)
      printf 'Usage: smoke-test.sh [--base-url URL] [--api-key KEY] [--model ID] [--image FILE]\n'
      printf '  --skip-responses  skip /v1/responses check\n'
      printf '  --skip-vision     skip image input check\n'
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ninfer-smoke.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
auth=(-H "Authorization: Bearer $key" -H "Content-Type: application/json")

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
show_body() { printf '      body: %s\n' "$(head -c 400 "$1" 2>/dev/null | tr '\n' ' ')"; }

http_post() {
  local name="$1" path="$2" body="$3"
  local out="$tmp/$name.json"
  local code
  code="$(curl -sS --max-time 240 -o "$out" -w '%{http_code}' -X POST "${auth[@]}" \
    "$api$path" -d "$body" || true)"
  printf '%s' "$code"
  printf '%s' "$out" > "$tmp/$name.path"
}

check_health() {
  local out="$tmp/health.json" code
  code="$(curl -sS --max-time 10 -o "$out" -w '%{http_code}' "$root/health" || true)"
  if [[ "$code" == "200" ]] && grep -q '"status"[[:space:]]*:[[:space:]]*"ok"' "$out"; then
    ok "health ($root/health)"
  else
    bad "health ($root/health, HTTP $code)"
    show_body "$out"
  fi
}

check_models() {
  local out="$tmp/models.json" code
  code="$(curl -sS --max-time 10 -o "$out" -w '%{http_code}' "${auth[@]}" "$api/models" || true)"
  if [[ "$code" == "200" ]] && python3 - "$out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert isinstance(data.get("data"), list) and data["data"]
PY
  then
    ok "models ($api/models)"
  else
    bad "models ($api/models, HTTP $code)"
    show_body "$out"
  fi
}

check_chat() {
  local code out
  code="$(http_post chat /chat/completions "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word OK.\"}],\"max_tokens\":16,\"temperature\":0}")"
  out="$(cat "$tmp/chat.path")"
  if [[ "$code" == "200" ]] && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["choices"][0]["message"]
PY
  then
    ok "chat completions"
  else
    bad "chat completions (HTTP $code)"
    show_body "$out"
  fi
}

check_stream() {
  local out="$tmp/stream.txt" code
  code="$(curl -sS -N --max-time 240 -o "$out" -w '%{http_code}' -X POST "${auth[@]}" \
    "$api/chat/completions" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Count 1 to 3.\"}],\"max_tokens\":24,\"temperature\":0,\"stream\":true}" || true)"
  if [[ "$code" == "200" ]] && grep -q '^data:' "$out"; then
    ok "streaming SSE"
  else
    bad "streaming SSE (HTTP $code)"
    show_body "$out"
  fi
}

check_json_schema() {
  local code out
  code="$(http_post schema /chat/completions "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Return a JSON object with ok set to true.\"}],\"max_tokens\":128,\"temperature\":0,\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{\"name\":\"result\",\"strict\":true,\"schema\":{\"type\":\"object\",\"properties\":{\"ok\":{\"type\":\"boolean\"}},\"required\":[\"ok\"],\"additionalProperties\":false}}}}")"
  out="$(cat "$tmp/schema.path")"
  if [[ "$code" == "200" ]] && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
content = d["choices"][0]["message"]["content"]
parsed = json.loads(content)
assert isinstance(parsed, dict) and parsed.get("ok") is True
PY
  then
    ok "JSON Schema constrained output"
  else
    bad "JSON Schema constrained output (HTTP $code)"
    show_body "$out"
  fi
}

check_responses() {
  local out="$tmp/responses.json" code
  code="$(curl -sS --max-time 240 -o "$out" -w '%{http_code}' -X POST "${auth[@]}" \
    "$api/responses" \
    -d "{\"model\":\"$model\",\"input\":\"Reply with the single word OK.\",\"max_output_tokens\":16}" || true)"
  if [[ "$code" == "200" ]] && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("object") == "response" or "output" in d
PY
  then
    ok "Responses API"
  else
    bad "Responses API (HTTP $code)"
    show_body "$out"
  fi
}

check_vision() {
  [[ -n "$image" ]] || return 0
  [[ -f "$image" ]] || { bad "vision input (missing file: $image)"; return 0; }
  python3 - "$image" "$model" > "$tmp/vision-request.json" <<'PY'
import base64, json, mimetypes, sys
path = sys.argv[1]
model = sys.argv[2]
mime = mimetypes.guess_type(path)[0] or "image/jpeg"
data = base64.b64encode(open(path, "rb").read()).decode("ascii")
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": [
        {"type": "text", "text": "Describe the image in one word."},
        {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{data}"}}
    ]}],
    "max_tokens": 64,
    "temperature": 0
}))
PY
  local out="$tmp/vision.json" code
  code="$(curl -sS --max-time 240 -o "$out" -w '%{http_code}' -X POST "${auth[@]}" \
    "$api/chat/completions" --data-binary @"$tmp/vision-request.json" || true)"
  if [[ "$code" == "200" ]] && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["choices"][0]["message"]
PY
  then
    ok "vision input"
  else
    bad "vision input (HTTP $code)"
    show_body "$out"
  fi
}

check_health
check_models
check_chat
check_stream
check_json_schema
if (( ! skip_responses )); then check_responses; fi
if (( ! skip_vision )); then check_vision; fi

printf '\nResult: %s passed, %s failed\n' "$pass" "$fail"
(( fail == 0 ))
