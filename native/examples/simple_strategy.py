#!/usr/bin/env python3
"""Minimal HexGo external strategy.

Reads one JSON observation from stdin and writes:
{"action_index": number, "reason": string}
"""

import json
import sys


def main() -> None:
    request = json.load(sys.stdin)
    legal = list(request.get("legal_action_indices", []))
    pass_index = int(request.get("pass_action_index", -1))
    legal_moves = [index for index in legal if index != pass_index]

    center_index = None
    for action in request.get("legal_actions", []):
        if action.get("type") == "move" and action.get("q") == 0 and action.get("r") == 0:
            center_index = int(action["action_index"])
            break

    if center_index in legal:
        choice = center_index
        reason = "take center"
    elif legal_moves:
        choice = legal_moves[0]
        reason = "take first legal move"
    elif pass_index in legal:
        choice = pass_index
        reason = "pass is the only legal action"
    else:
        choice = legal[0]
        reason = "fallback to first legal action"

    print(json.dumps({"action_index": choice, "reason": reason}, separators=(",", ":")))


if __name__ == "__main__":
    main()
