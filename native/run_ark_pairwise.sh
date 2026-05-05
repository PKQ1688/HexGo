#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://ark.ap-southeast.bytepluses.com/api/coding/v3}"
API_KEY_ENV="${API_KEY_ENV:-ARK_API_KEY}"
BOARD_RADIUS="${BOARD_RADIUS:-4}"
GAMES_PER_SIDE="${GAMES_PER_SIDE:-3}"
MAX_TURNS="${MAX_TURNS:-180}"
TEMPERATURE="${TEMPERATURE:-0.2}"
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-256}"
CANDIDATE_COUNT="${CANDIDATE_COUNT:-8}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
MAX_RETRIES="${MAX_RETRIES:-0}"
RETRY_BACKOFF_MS="${RETRY_BACKOFF_MS:-1500}"
DECISION_RETRIES="${DECISION_RETRIES:-1}"
DECISION_RETRY_BACKOFF_MS="${DECISION_RETRY_BACKOFF_MS:-1500}"
MAX_GAME_ATTEMPTS="${MAX_GAME_ATTEMPTS:-2}"
REPLAY_INVALID_GAMES="${REPLAY_INVALID_GAMES:-1}"
JSON_RESPONSE_FORMAT="${JSON_RESPONSE_FORMAT:-0}"
CURL_CLIENT="${CURL_CLIENT:-1}"
OUT="${OUT:-native/eval-results/ark-pairwise.jsonl}"

if [[ -n "${MODELS_CSV:-}" ]]; then
	IFS=',' read -r -a MODELS <<<"$MODELS_CSV"
else
	MODELS=(
		"glm-5.1"
		"kimi-k2.5"
		"dola-seed-2.0-pro"
		"glm-4.7"
		"gpt-oss-120b"
	)
fi

if [[ -z "${!API_KEY_ENV:-}" ]]; then
	echo "Missing API key environment variable: ${API_KEY_ENV}" >&2
	echo "Set it first, for example: export ${API_KEY_ENV}=..." >&2
	exit 1
fi

mkdir -p "$(dirname "$OUT")"
: > "$OUT"

COMMON_ARGS=(
	--base-url "$BASE_URL"
	--api-key-env "$API_KEY_ENV"
	--games "$GAMES_PER_SIDE"
	--board-radius "$BOARD_RADIUS"
	--max-turns "$MAX_TURNS"
	--temperature "$TEMPERATURE"
	--max-output-tokens "$MAX_OUTPUT_TOKENS"
	--candidate-count "$CANDIDATE_COUNT"
	--timeout-seconds "$TIMEOUT_SECONDS"
	--max-retries "$MAX_RETRIES"
	--retry-backoff-ms "$RETRY_BACKOFF_MS"
	--decision-retries "$DECISION_RETRIES"
	--decision-retry-backoff-ms "$DECISION_RETRY_BACKOFF_MS"
	--max-game-attempts "$MAX_GAME_ATTEMPTS"
	--out "$OUT"
)
if [[ "$REPLAY_INVALID_GAMES" == "1" ]]; then
	COMMON_ARGS+=(--replay-invalid-games)
fi
if [[ "$JSON_RESPONSE_FORMAT" == "1" ]]; then
	COMMON_ARGS+=(--json-response-format)
fi
if [[ "$CURL_CLIENT" == "1" ]]; then
	COMMON_ARGS+=(--curl-client)
fi

for ((i = 0; i < ${#MODELS[@]}; i++)); do
	for ((j = i + 1; j < ${#MODELS[@]}; j++)); do
		black="${MODELS[$i]}"
		white="${MODELS[$j]}"

		echo "Running ${black} black vs ${white} white"
		cargo run --manifest-path native/Cargo.toml -p hexgo-eval -- \
			--black-model "$black" \
			--white-model "$white" \
			"${COMMON_ARGS[@]}"

		echo "Running ${white} black vs ${black} white"
		cargo run --manifest-path native/Cargo.toml -p hexgo-eval -- \
			--black-model "$white" \
			--white-model "$black" \
			"${COMMON_ARGS[@]}"
	done
done

echo "Pairwise results written to ${OUT}"
