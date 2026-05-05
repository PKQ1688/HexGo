#!/usr/bin/env python3
"""GLM-4-7 HexGo strategy — deterministic, standard-library only."""

import json
import sys

NEIGHBOR_DELTAS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def neighbors(q, r):
    for dq, dr in NEIGHBOR_DELTAS:
        yield q + dq, r + dr


def build_board(occupied_cells):
    board = {}
    for cell in occupied_cells:
        board[(cell["q"], cell["r"])] = cell["state"]
    return board


def on_board(q, r, radius):
    s = -q - r
    return abs(q) <= radius and abs(r) <= radius and abs(s) <= radius


def group_liberties(q, r, board, radius):
    """Return (group_size, liberty_set) for the group containing (q,r)."""
    color = board.get((q, r))
    if color is None:
        return 0, set()
    visited = set()
    liberties = set()
    stack = [(q, r)]
    while stack:
        cq, cr = stack.pop()
        if (cq, cr) in visited:
            continue
        visited.add((cq, cr))
        for nq, nr in neighbors(cq, cr):
            if not on_board(nq, nr, radius):
                continue
            cell = board.get((nq, nr))
            if cell is None:
                liberties.add((nq, nr))
            elif cell == color and (nq, nr) not in visited:
                stack.append((nq, nr))
    return len(visited), liberties


def count_captures(q, r, player, board, radius):
    """Count opponent stones captured by placing player at (q,r)."""
    opponent = "white" if player == "black" else "black"
    total = 0
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) == opponent:
            _, libs = group_liberties(nq, nr, board, radius)
            # The new stone at (q,r) removes one liberty; if only that liberty
            # remained, the group is captured.
            if libs == {(q, r)}:
                _, libs_after = group_liberties(nq, nr, board, radius)
                if (q, r) in libs_after and len(libs_after) == 1:
                    total += 0  # already counted via libs check
                total += 0  # will recalculate below
    # Simpler: place the stone, then check each adjacent opponent group
    sim = dict(board)
    sim[(q, r)] = player
    captured = 0
    checked = set()
    for nq, nr in neighbors(q, r):
        if (nq, nr) in checked:
            continue
        if sim.get((nq, nr)) == opponent:
            size, libs = group_liberties(nq, nr, sim, radius)
            checked.update(group_stones(nq, nr, sim, radius))
            if len(libs) == 0:
                captured += size
    return captured


def group_stones(q, r, board, radius):
    """Return set of stones in the group containing (q,r)."""
    color = board.get((q, r))
    if color is None:
        return set()
    visited = set()
    stack = [(q, r)]
    while stack:
        cq, cr = stack.pop()
        if (cq, cr) in visited:
            continue
        visited.add((cq, cr))
        for nq, nr in neighbors(cq, cr):
            if board.get((nq, nr)) == color and (nq, nr) not in visited:
                stack.append((nq, nr))
    return visited


def friendly_liberties_after(q, r, player, board, radius):
    """Liberties of the friendly group after placing player at (q,r)."""
    sim = dict(board)
    sim[(q, r)] = player
    _, libs = group_liberties(q, r, sim, radius)
    return len(libs)


def count_adjacent_friendly(q, r, player, board, radius):
    count = 0
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) == player:
            count += 1
    return count


def score_move(q, r, player, board, radius, move_count):
    """Score a candidate move; higher is better."""
    score = 0.0

    # 1. Capture bonus
    captures = count_captures(q, r, player, board, radius)
    score += captures * 100.0

    # 2. Liberties of resulting friendly group
    libs = friendly_liberties_after(q, r, player, board, radius)
    if libs == 0:
        # Should not happen (suicide filtered), but safety
        return -1e9
    if libs == 1:
        score -= 40.0  # in danger
    elif libs == 2:
        score -= 10.0
    else:
        score += min(libs, 6) * 5.0

    # 3. Centrality — prefer center in opening
    dist = max(abs(q), abs(r), abs(-q - r))
    centrality = radius - dist
    if move_count < radius * 3:
        score += centrality * 3.0
    else:
        score += centrality * 1.0

    # 4. Connectivity — adjacent friendly stones
    adj_friendly = count_adjacent_friendly(q, r, player, board, radius)
    score += adj_friendly * 4.0

    # 5. Adjacent empty — more options
    adj_empty = 0
    for nq, nr in neighbors(q, r):
        if on_board(nq, nr, radius) and board.get((nq, nr)) is None:
            adj_empty += 1
    score += adj_empty * 2.0

    # 6. Slight penalty for playing on the very edge
    if dist == radius:
        score -= 8.0

    return score


def choose(request):
    player = request["player"]
    state = request["state"]
    board_radius = state["board_radius"]
    move_count = state["move_count"]
    legal_actions = request["legal_actions"]
    pass_action_index = state["pass_action_index"]

    board = build_board(state["occupied_cells"])

    # Separate pass and move actions
    move_actions = [a for a in legal_actions if a["type"] == "move"]
    pass_actions = [a for a in legal_actions if a["type"] == "pass"]

    if not move_actions:
        # Only pass available
        return pass_action_index, "no legal moves, pass"

    # Score every move action
    best_score = -1e18
    best_action = None
    best_reason = ""
    for action in move_actions:
        q, r = action["q"], action["r"]
        s = score_move(q, r, player, board, board_radius, move_count)
        if s > best_score:
            best_score = s
            best_action = action
            captures = count_captures(q, r, player, board, board_radius)
            libs = friendly_liberties_after(q, r, player, board, board_radius)
            if captures > 0:
                best_reason = f"capture {captures} stone(s), {libs} liberties"
            elif libs <= 1:
                best_reason = f"only {libs} liberty, avoid"
            else:
                best_reason = f"score {best_score:.0f}, {libs} liberties"

    # Avoid pass while good moves exist
    if best_action is not None and best_score > -50:
        return best_action["action_index"], best_reason

    # All moves look bad — still prefer a move over pass unless very late
    if move_count < board_radius * 6 and best_action is not None:
        return best_action["action_index"], best_reason

    # Pass as last resort
    if pass_actions:
        return pass_actions[0]["action_index"], "all moves bad, pass"
    return pass_action_index, "all moves bad, pass"


def main():
    data = json.load(sys.stdin)
    action_index, reason = choose(data)
    json.dump({"action_index": action_index, "reason": reason}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
