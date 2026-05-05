#!/usr/bin/env python3
import json
import sys
from collections import deque


NEIGHBORS = ((1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1))


def other(player):
    return "white" if player == "black" else "black"


def dist(coord):
    q, r = coord
    return max(abs(q), abs(r), abs(-q - r))


def valid(coord, radius):
    return dist(coord) <= radius


def neighbors(coord, radius):
    q, r = coord
    for dq, dr in NEIGHBORS:
        nxt = (q + dq, r + dr)
        if valid(nxt, radius):
            yield nxt


def group_and_liberties(board, start, radius):
    color = board.get(start)
    if color not in ("black", "white"):
        return set(), set()

    group = set()
    liberties = set()
    queue = deque([start])
    seen = {start}

    while queue:
        coord = queue.popleft()
        group.add(coord)
        for nxt in neighbors(coord, radius):
            state = board.get(nxt)
            if state is None:
                liberties.add(nxt)
            elif state == color and nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)
    return group, liberties


def simulate(board, move, player, radius):
    opp = other(player)
    after = dict(board)
    after[move] = player
    captured = set()
    checked = set()

    for nxt in neighbors(move, radius):
        if nxt in checked or after.get(nxt) != opp:
            continue
        group, libs = group_and_liberties(after, nxt, radius)
        checked |= group
        if not libs:
            captured |= group

    for coord in captured:
        after.pop(coord, None)

    own_group, own_libs = group_and_liberties(after, move, radius)
    return after, captured, own_group, own_libs


def empty_points(radius, board):
    for q in range(-radius, radius + 1):
        for r in range(-radius, radius + 1):
            coord = (q, r)
            if valid(coord, radius) and coord not in board:
                yield coord


def territory_hint(board, player, radius):
    opp = other(player)
    total = 0
    for coord in empty_points(radius, board):
        own_touch = 0
        opp_touch = 0
        for nxt in neighbors(coord, radius):
            if board.get(nxt) == player:
                own_touch += 1
            elif board.get(nxt) == opp:
                opp_touch += 1
        if own_touch and not opp_touch:
            total += 1
        elif own_touch > opp_touch:
            total += 0.35
    return total


def own_eye_like(board, move, player, radius):
    opp = other(player)
    own = 0
    opp_count = 0
    open_count = 0
    for nxt in neighbors(move, radius):
        state = board.get(nxt)
        if state == player:
            own += 1
        elif state == opp:
            opp_count += 1
        else:
            open_count += 1
    return own >= 4 and opp_count == 0 and open_count <= 1


def score_move(action, board, player, radius, move_count, current_margin):
    move = (int(action["q"]), int(action["r"]))
    opp = other(player)
    after, captured, own_group, own_libs = simulate(board, move, player, radius)
    liberties = len(own_libs)
    capture_count = len(captured)

    friendly_neighbors = 0
    enemy_neighbors = 0
    pressure = 0
    rescue = 0
    for nxt in neighbors(move, radius):
        state = board.get(nxt)
        if state == player:
            friendly_neighbors += 1
            group, libs = group_and_liberties(board, nxt, radius)
            if move in libs and len(libs) <= 2:
                rescue += len(group)
        elif state == opp:
            enemy_neighbors += 1
            group, libs = group_and_liberties(board, nxt, radius)
            if move in libs:
                if len(libs) == 1:
                    pressure += 9 * len(group)
                elif len(libs) == 2:
                    pressure += 3 * len(group)
                elif len(libs) == 3:
                    pressure += len(group)

    centrality = radius - dist(move)
    score = 0.0
    score += capture_count * 120.0
    score += pressure * 7.0
    score += rescue * 8.0
    score += liberties * 9.0
    score += min(len(own_group), 6) * 4.0
    score += friendly_neighbors * 8.0
    score += enemy_neighbors * 2.0
    score += centrality * (7.0 if move_count < radius * 5 else 2.5)

    before_hint = territory_hint(board, player, radius)
    after_hint = territory_hint(after, player, radius)
    score += (after_hint - before_hint) * 4.0

    if capture_count == 0 and liberties <= 1:
        score -= 260.0
    elif capture_count == 0 and liberties == 2:
        score -= 35.0

    if own_eye_like(board, move, player, radius) and capture_count == 0:
        score -= 120.0

    if friendly_neighbors == 0 and enemy_neighbors == 0 and move_count > radius * 4:
        score -= 12.0

    if current_margin < 0:
        score += capture_count * 20.0 + enemy_neighbors * 1.5

    score += (move[0] * 0.013) + (move[1] * 0.007)
    return score, capture_count, liberties, friendly_neighbors, pressure


def main():
    request = json.load(sys.stdin)
    player = request.get("player", "black")
    state = request.get("state", {})
    radius = int(state.get("board_radius", 1))
    move_count = int(state.get("move_count", 0))
    pass_index = int(request.get("pass_action_index", state.get("pass_action_index", -1)))
    scores = state.get("scores", {})
    current_margin = int(scores.get(player, 0)) - int(scores.get(other(player), 0))

    board = {}
    for cell in state.get("occupied_cells", []):
        color = cell.get("state")
        if color in ("black", "white"):
            board[(int(cell["q"]), int(cell["r"]))] = color

    moves = [action for action in request.get("legal_actions", []) if action.get("type") == "move"]
    if not moves:
        print(json.dumps({"action_index": pass_index, "reason": "no legal moves"}))
        return

    best = None
    for action in moves:
        score, captures, libs, friends, pressure = score_move(
            action, board, player, radius, move_count, current_margin
        )
        key = (score, captures, libs, friends, -dist((int(action["q"]), int(action["r"]))))
        if best is None or key > best[0]:
            best = (key, action, score, captures, libs, friends, pressure)

    _, action, score, captures, libs, friends, pressure = best
    reason = (
        f"score={score:.1f} cap={captures} libs={libs} "
        f"friends={friends} pressure={pressure}"
    )
    print(json.dumps({"action_index": int(action["action_index"]), "reason": reason}))


if __name__ == "__main__":
    main()
