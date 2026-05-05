#!/usr/bin/env python3
"""HexGo strategy: deterministic, capture-preferring, liberty-aware."""

import json
import sys
from collections import deque

NEIGHBOR_DELTAS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def neighbors(q, r):
    for dq, dr in NEIGHBOR_DELTAS:
        yield q + dq, r + dr


def on_board(q, r, radius):
    return abs(q) <= radius and abs(r) <= radius and abs(-q - r) <= radius


def build_board(occupied_cells, radius):
    board = {}
    for cell in occupied_cells:
        board[(cell["q"], cell["r"])] = cell["state"]
    return board


def get_group_and_liberties(board, q, r, radius):
    color = board.get((q, r))
    if color is None:
        return set(), set()
    group = set()
    liberties = set()
    queue = deque([(q, r)])
    visited = set()
    visited.add((q, r))
    while queue:
        cq, cr = queue.popleft()
        group.add((cq, cr))
        for nq, nr in neighbors(cq, cr):
            if (nq, nr) in visited:
                continue
            if not on_board(nq, nr, radius):
                continue
            visited.add((nq, nr))
            cell = board.get((nq, nr))
            if cell is None:
                liberties.add((nq, nr))
            elif cell == color and (nq, nr) not in group:
                queue.append((nq, nr))
    return group, liberties


def count_captures(board, q, r, player, opponent, radius):
    captures = 0
    captured_groups = []
    seen_groups = set()
    for nq, nr in neighbors(q, r):
        if not on_board(nq, nr, radius):
            continue
        if board.get((nq, nr)) == opponent:
            group, liberties = get_group_and_liberties(board, nq, nr, radius)
            if (q, r) in liberties:
                new_liberties = liberties - {(q, r)}
                if len(new_liberties) == 0:
                    group_key = frozenset(group)
                    if group_key in seen_groups:
                        continue
                    seen_groups.add(group_key)
                    captures += len(group)
                    captured_groups.append(group)
    return captures, captured_groups


def count_own_liberties_after(board, q, r, player, radius, captured_groups):
    temp_board = dict(board)
    temp_board[(q, r)] = player
    for group in captured_groups:
        for gq, gr in group:
            temp_board.pop((gq, gr), None)
    _, liberties = get_group_and_liberties(temp_board, q, r, radius)
    return len(liberties)


def hex_distance(q, r):
    return max(abs(q), abs(r), abs(-q - r))


def count_adjacent_friendly(board, q, r, player, radius):
    count = 0
    for nq, nr in neighbors(q, r):
        if on_board(nq, nr, radius) and board.get((nq, nr)) == player:
            count += 1
    return count


def count_empty_neighbors(board, q, r, radius):
    count = 0
    for nq, nr in neighbors(q, r):
        if on_board(nq, nr, radius) and board.get((nq, nr)) is None:
            count += 1
    return count


def evaluate_move(board, q, r, player, opponent, radius, move_count, board_radius):
    score = 0.0

    captures, captured_groups = count_captures(board, q, r, player, opponent, radius)
    score += captures * 100.0

    own_liberties = count_own_liberties_after(board, q, r, player, radius, captured_groups)
    if own_liberties == 0 and captures == 0:
        return -10000.0
    if own_liberties == 1 and captures == 0:
        score -= 50.0
    score += own_liberties * 5.0

    adj_friendly = count_adjacent_friendly(board, q, r, player, radius)
    score += adj_friendly * 3.0

    empty_neighbors = count_empty_neighbors(board, q, r, radius)
    score += empty_neighbors * 2.0

    dist = hex_distance(q, r)
    max_dist = board_radius
    centrality = (max_dist - dist) / max(max_dist, 1)
    opening_weight = max(0.0, 1.0 - move_count / 40.0)
    score += centrality * 8.0 * opening_weight

    if captures > 0:
        for nq, nr in neighbors(q, r):
            if on_board(nq, nr, radius) and board.get((nq, nr)) == opponent:
                grp, libs = get_group_and_liberties(board, nq, nr, radius)
                if (q, r) in libs and len(libs) <= 2:
                    score += 15.0

    for nq, nr in neighbors(q, r):
        if on_board(nq, nr, radius) and board.get((nq, nr)) == player:
            grp, libs = get_group_and_liberties(board, nq, nr, radius)
            if len(libs) == 1 and (q, r) in libs:
                score += 40.0

    return score


def compute_territory_estimate(board, player, opponent, radius):
    visited = set()
    player_territory = 0
    opponent_territory = 0
    all_cells = set()
    for q in range(-radius, radius + 1):
        for r in range(-radius, radius + 1):
            if on_board(q, r, radius):
                all_cells.add((q, r))

    for cell in all_cells:
        if cell in visited or cell in board:
            continue
        region = set()
        borders = set()
        queue = deque([cell])
        visited.add(cell)
        while queue:
            cq, cr = queue.popleft()
            region.add((cq, cr))
            for nq, nr in neighbors(cq, cr):
                if not on_board(nq, nr, radius):
                    continue
                if (nq, nr) in visited:
                    continue
                occ = board.get((nq, nr))
                if occ is not None:
                    borders.add(occ)
                else:
                    visited.add((nq, nr))
                    queue.append((nq, nr))
        if borders == {player}:
            player_territory += len(region)
        elif borders == {opponent}:
            opponent_territory += len(region)

    return player_territory, opponent_territory


def run():
    data = json.load(sys.stdin)
    player = data["player"]
    opponent = "white" if player == "black" else "black"
    state = data["state"]
    radius = state["board_radius"]
    move_count = state["move_count"]
    consecutive_passes = state["consecutive_passes"]
    legal_actions = data["legal_actions"]
    pass_action_index = state["pass_action_index"]

    board = build_board(state["occupied_cells"], radius)

    move_actions = [a for a in legal_actions if a["type"] == "move"]

    if not move_actions:
        reason = "No legal moves available; passing"
        print(json.dumps({"action_index": pass_action_index, "reason": reason}))
        return

    best_score = -float("inf")
    best_action = None
    best_reason = ""

    for action in move_actions:
        q, r = action["q"], action["r"]
        score = evaluate_move(board, q, r, player, opponent, radius, move_count, radius)
        captures, _ = count_captures(board, q, r, player, opponent, radius)
        if score > best_score:
            best_score = score
            best_action = action
            parts = [f"eval={score:.1f}"]
            if captures > 0:
                parts.append(f"cap={captures}")
            parts.append(f"dist={hex_distance(q, r)}")
            best_reason = "; ".join(parts)

    if best_action is None:
        best_action = move_actions[0]
        best_reason = "fallback first legal move"

    if best_score < -80.0 and move_count > radius * 2:
        my_territory, opp_territory = compute_territory_estimate(board, player, opponent, radius)
        my_stones = sum(1 for v in board.values() if v == player)
        opp_stones = sum(1 for v in board.values() if v == opponent)
        my_total = my_stones + my_territory
        opp_total = opp_stones + opp_territory
        if my_total > opp_total and consecutive_passes == 0:
            print(json.dumps({
                "action_index": pass_action_index,
                "reason": f"winning position (me={my_total} opp={opp_total}); pass to end"
            }))
            return

    print(json.dumps({"action_index": best_action["action_index"], "reason": best_reason}))


if __name__ == "__main__":
    run()
