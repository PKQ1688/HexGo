#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://ark.ap-southeast.bytepluses.com/api/coding/v3}"
API_KEY_ENV="${API_KEY_ENV:-ARK_API_KEY}"
BOARD_RADIUS="${BOARD_RADIUS:-3}"
GAMES_PER_SIDE="${GAMES_PER_SIDE:-1}"
MAX_TURNS="${MAX_TURNS:-120}"
TEMPERATURE="${TEMPERATURE:-0.2}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
MAX_RETRIES="${MAX_RETRIES:-0}"
RETRY_BACKOFF_MS="${RETRY_BACKOFF_MS:-1500}"
OUT="${OUT:-native/eval-results/ark-pairwise.jsonl}"

MODELS=(
	"glm-5.1"
	"kimi-k2.5"
	"dola-seed-2.0-pro"
	"gpt-oss-120b"
)

if [[ -z "${!API_KEY_ENV:-}" ]]; then
	echo "Missing API key environment variable: ${API_KEY_ENV}" >&2
	echo "Set it first, for example: export ${API_KEY_ENV}=..." >&2
	exit 1
fi

mkdir -p "$(dirname "$OUT")"
: > "$OUT"

for ((i = 0; i < ${#MODELS[@]}; i++)); do
	for ((j = i + 1; j < ${#MODELS[@]}; j++)); do
		black="${MODELS[$i]}"
		white="${MODELS[$j]}"

		echo "Running ${black} black vs ${white} white"
		cargo run --manifest-path native/Cargo.toml -p hexgo-eval -- \
			--black-model "$black" \
			--white-model "$white" \
			--base-url "$BASE_URL" \
			--api-key-env "$API_KEY_ENV" \
			--games "$GAMES_PER_SIDE" \
			--board-radius "$BOARD_RADIUS" \
			--max-turns "$MAX_TURNS" \
			--temperature "$TEMPERATURE" \
			--timeout-seconds "$TIMEOUT_SECONDS" \
			--max-retries "$MAX_RETRIES" \
			--retry-backoff-ms "$RETRY_BACKOFF_MS" \
			--out "$OUT"

		echo "Running ${white} black vs ${black} white"
		cargo run --manifest-path native/Cargo.toml -p hexgo-eval -- \
			--black-model "$white" \
			--white-model "$black" \
			--base-url "$BASE_URL" \
			--api-key-env "$API_KEY_ENV" \
			--games "$GAMES_PER_SIDE" \
			--board-radius "$BOARD_RADIUS" \
			--max-turns "$MAX_TURNS" \
			--temperature "$TEMPERATURE" \
			--timeout-seconds "$TIMEOUT_SECONDS" \
			--max-retries "$MAX_RETRIES" \
			--retry-backoff-ms "$RETRY_BACKOFF_MS" \
			--out "$OUT"
	done
done

echo "Pairwise results written to ${OUT}"
