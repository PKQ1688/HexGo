import json
import sys
from collections import deque

NEIGHBOR_DELTAS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def neighbors(q, r):
    for dq, dr in NEIGHBOR_DELTAS:
        yield q + dq, r + dr


def hex_dist(q, r):
    return max(abs(q), abs(r), abs(-q - r))


def find_group(q, r, board):
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
            visited.add((nq, nr))
            cell = board.get((nq, nr))
            if cell is None:
                liberties.add((nq, nr))
            elif cell == color:
                queue.append((nq, nr))
    return group, liberties


def count_captures(q, r, player, board):
    opponent = "white" if player == "black" else "black"
    captured = 0
    checked = set()
    for nq, nr in neighbors(q, r):
        if (nq, nr) in checked:
            continue
        if board.get((nq, nr)) == opponent:
            group, liberties = find_group(nq, nr, board)
            checked |= group
            if (q, r) in liberties:
                remaining = liberties - {(q, r)}
                if len(remaining) == 0:
                    captured += len(group)
    return captured


def count_group_liberties_after(q, r, player, board):
    temp = dict(board)
    temp[(q, r)] = player
    group, liberties = find_group(q, r, temp)
    return len(liberties)


def count_friendly_neighbors(q, r, player, board):
    count = 0
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) == player:
            count += 1
    return count


def is_eye(q, r, player, board, board_radius):
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) != player:
            return False
    diagonals = [
        (q + 1, r + 1), (q + 1, r - 1), (q - 1, r - 1), (q - 1, r + 1),
        (q + 2, r - 1), (q - 2, r + 1), (q - 1, r + 2), (q + 1, r - 2),
    ]
    opp = "white" if player == "black" else "black"
    opp_diag = 0
    for dq, dr in diagonals:
        if hex_dist(dq, dr) <= board_radius and board.get((dq, dr)) == opp:
            opp_diag += 1
    return opp_diag < 2


def evaluate_move(q, r, player, board, board_radius, move_count):
    score = 0.0

    captures = count_captures(q, r, player, board)
    score += captures * 100.0

    liberties = count_group_liberties_after(q, r, player, board)
    if captures == 0 and liberties <= 1:
        score -= 200.0
    elif captures == 0 and liberties == 2:
        score -= 30.0
    else:
        score += liberties * 5.0

    friendly = count_friendly_neighbors(q, r, player, board)
    score += friendly * 8.0

    if friendly == 0 and captures == 0:
        dist = hex_dist(q, r)
        centrality = (board_radius - dist) / max(board_radius, 1)
        score += centrality * 15.0

    if is_eye(q, r, player, board, board_radius):
        score -= 150.0

    dist = hex_dist(q, r)
    if move_count < board_radius * 2:
        if dist <= board_radius // 2:
            score += 10.0
        elif dist <= board_radius * 3 // 4:
            score += 5.0

    opp = "white" if player == "black" else "black"
    for nq, nr in neighbors(q, r):
        if board.get((nq, nr)) == opp:
            opp_group, opp_libs = find_group(nq, nr, board)
            if len(opp_libs) == 2 and (q, r) in opp_libs:
                score += 20.0
            elif len(opp_libs) == 3 and (q, r) in opp_libs:
                score += 5.0

    return score


def main():
    raw = sys.stdin.read()
    request = json.loads(raw)

    player = request["player"]
    state = request["state"]
    board_radius = state["board_radius"]
    move_count = state["move_count"]
    consecutive_passes = state["consecutive_passes"]
    legal_actions = request["legal_actions"]
    pass_action_index = state["pass_action_index"]

    board = {}
    for cell in state.get("occupied_cells", []):
        board[(cell["q"], cell["r"])] = cell["state"]

    non_pass = [a for a in legal_actions if a["type"] != "pass"]

    if not non_pass:
        reason = "No non-pass moves available"
        print(json.dumps({"action_index": pass_action_index, "reason": reason}))
        return

    best_score = None
    best_action = None
    best_reason = ""

    for action in non_pass:
        q, r = action["q"], action["r"]
        score = evaluate_move(q, r, player, board, board_radius, move_count)
        captures = count_captures(q, r, player, board)
        liberties = count_group_liberties_after(q, r, player, board)
        friendly = count_friendly_neighbors(q, r, player, board)

        if best_score is None or score > best_score:
            best_score = score
            best_action = action
            parts = []
            if captures > 0:
                parts.append(f"captures {captures}")
            parts.append(f"libs {liberties}")
            parts.append(f"friends {friendly}")
            parts.append(f"score {score:.1f}")
            best_reason = f"({q},{r}): " + ", ".join(parts)

    if best_action is not None:
        print(json.dumps({"action_index": best_action["action_index"], "reason": best_reason}))
    else:
        print(json.dumps({"action_index": pass_action_index, "reason": "Fallback pass"}))


if __name__ == "__main__":
    main()
