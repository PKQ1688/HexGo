Write a single Python 3 HexGo strategy program.

Output only raw Python code. Do not use Markdown fences. Do not explain.

Runtime protocol:
- The program is executed once per move.
- Read exactly one JSON object from stdin.
- Write exactly one JSON object to stdout: {"action_index": number, "reason": string}
- Do not print anything else to stdout.
- Use only Python standard library.
- Keep runtime under 3 seconds.

Input shape:
- request["player"] is "black" or "white".
- request["state"] contains:
  - board_radius
  - current_player
  - move_count
  - consecutive_passes
  - pass_action_index
  - scores: {"black": int, "white": int}
  - occupied_cells: list of {"q": int, "r": int, "state": "black"|"white"|...}
- request["legal_actions"] is a list of legal moves and pass, shaped like:
  - {"action_index": int, "type": "move", "q": int, "r": int}
  - {"action_index": int, "type": "pass"}
- request["legal_action_indices"] contains all legal action indices.
- request["pass_action_index"] is the pass action.

HexGo rules summary:
- Axial hex coordinates (q,r), s = -q-r.
- Neighbor deltas: (+1,0), (+1,-1), (0,-1), (-1,0), (-1,+1), (0,+1).
- Connected same-color stones form groups; adjacent empty cells are liberties.
- After a move, opponent groups with zero liberties are captured.
- Suicide and repetition moves are already removed from legal_actions.
- Empty regions bordered by one color count as that color's territory.
- Passing is legal; two consecutive passes end the game and settle score.
- Objective: maximize final live stones plus controlled territory.

Strategy guidance:
- Build a board map from occupied_cells.
- Prefer legal moves that immediately capture opponent stones.
- Avoid playing moves that leave the new friendly group with very few liberties unless it captures.
- Prefer central, high-liberty, connected moves in the opening.
- Avoid pass while legal non-pass moves exist, unless every move is clearly bad.
- Be deterministic.
