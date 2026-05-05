#!/usr/bin/env python3
"""HexGo strategy: greedy capture + liberty/centrality heuristic."""

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


def find_group(board, q, r):
    color = board.get((q, r))
    if color is None:
        return set(), set()
    group = set()
    liberties = set()
    stack = [(q, r)]
    while stack:
        cq, cr = stack.pop()
        if (cq, cr) in group:
            continue
        group.add((cq, cr))
        for nq, nr in neighbors(cq, cr):
            cell = board.get((nq, nr))
            if cell is None:
                liberties.add((nq, nr))
            elif cell == color and (nq, nr) not in group:
                stack.append((nq, nr))
    return group, liberties


def count_captures(board, q, r, player, opponent):
    """Count opponent stones captured by placing player at (q,r)."""
    board[(q, r)] = player
    captured = 0
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) == opponent:
            _, libs = find_group(board, nq, nr)
            if not libs:
                captured += 1
    del board[(q, r)]
    return captured


def resulting_liberties(board, q, r, player):
    """Liberties of the friendly group after placing player at (q,r)."""
    board[(q, r)] = player
    _, libs = find_group(board, q, r)
    del board[(q, r)]
    return len(libs)


def friendly_neighbor_count(board, q, r, player):
    count = 0
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) == player:
            count += 1
    return count


def centrality(q, r, board_radius):
    """Higher value for more central positions."""
    s = -q - r
    dist = max(abs(q), abs(r), abs(s))
    return board_radius - dist


def score_move(board, action, player, opponent, board_radius):
    q, r = action["q"], action["r"]

    captures = count_captures(board, q, r, player, opponent)
    libs = resulting_liberties(board, q, r, player)
    friends = friendly_neighbor_count(board, q, r, player)
    center = centrality(q, r, board_radius)

    # Heavy weight on captures
    score = captures * 1000

    # Liberty safety: penalize very low liberties unless capturing
    if captures == 0 and libs <= 1:
        score -= 500
    else:
        score += libs * 5

    # Connection bonus (but not too much — avoid over-concentration)
    score += min(friends, 3) * 10

    # Centrality bonus
    score += center * 3

    return score, captures, libs


def choose_action(request):
    player = request["player"]
    state = request["state"]
    board = build_board(state["occupied_cells"])
    board_radius = state["board_radius"]
    opponent = "white" if player == "black" else "black"

    legal_actions = request["legal_actions"]
    pass_index = state["pass_action_index"]

    move_actions = [a for a in legal_actions if a["type"] == "move"]
    pass_actions = [a for a in legal_actions if a["type"] == "pass"]

    if not move_actions:
        if pass_actions:
            return pass_actions[0]["action_index"], "no legal moves, pass"
        return pass_index, "no legal moves, pass"

    best_score = None
    best_action = None
    best_reason = ""

    for action in move_actions:
        sc, caps, libs = score_move(board, action, player, opponent, board_radius)
        if best_score is None or sc > best_score:
            best_score = sc
            best_action = action
            parts = []
            if caps > 0:
                parts.append(f"capture {caps}")
            parts.append(f"libs={libs}")
            parts.append(f"score={sc}")
            best_reason = "; ".join(parts)

    # Only pass if every move is clearly bad (negative score) and we have
    # enough territory advantage or late game
    if best_score < -400 and pass_actions:
        return pass_actions[0]["action_index"], "all moves harmful, pass"

    return best_action["action_index"], best_reason


def main():
    request = json.load(sys.stdin)
    action_index, reason = choose_action(request)
    print(json.dumps({"action_index": action_index, "reason": reason}))


if __name__ == "__main__":
    main()
