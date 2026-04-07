use std::collections::{HashSet, VecDeque};

use godot::classes::RefCounted;
use godot::prelude::*;
use hexgo_core::{
    Action, ActionCodec, Board, CellState, Coord, Event, EventType, MatchEngine, MoveRecord,
    Observation, Phase, Player, RulesConfig, StepResult,
};

struct HexGoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for HexGoExtension {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct HexGoNativeEngine {
    base: Base<RefCounted>,
    engine: MatchEngine,
    action_codec: ActionCodec,
}

#[godot_api]
impl IRefCounted for HexGoNativeEngine {
    fn init(base: Base<RefCounted>) -> Self {
        let engine = MatchEngine::new(RulesConfig::default());
        let action_codec = ActionCodec::new(&engine.board);
        Self {
            base,
            engine,
            action_codec,
        }
    }
}

#[godot_api]
impl HexGoNativeEngine {
    #[func]
    fn setup_game(&mut self, radius: i32) {
        self.engine.setup_game(radius);
        self.refresh_codec();
    }

    #[func]
    fn switch_player(&mut self) {
        self.engine.switch_player();
    }

    #[func]
    fn record_pass(&mut self) -> bool {
        let accepted = self.engine.record_pass();
        self.refresh_codec();
        accepted
    }

    #[func]
    fn can_pass(&self) -> bool {
        self.engine.can_pass()
    }

    #[func]
    fn can_place_at(&self, coord: Vector2i) -> bool {
        self.engine.can_place_at(coord_from_vector(coord))
    }

    #[func]
    fn execute_turn(&mut self, coord: Vector2i) -> bool {
        let accepted = self.engine.execute_turn(coord_from_vector(coord));
        self.refresh_codec();
        accepted
    }

    #[func]
    fn is_scoring_phase(&self) -> bool {
        self.engine.is_scoring_phase()
    }

    #[func]
    fn get_visible_threats(&self) -> VarDictionary {
        serialize_visible_threats(&self.engine.board, self.engine.phase)
    }

    #[func]
    fn can_toggle_dead_at(&self, coord: Vector2i) -> bool {
        self.engine.can_toggle_dead_at(coord_from_vector(coord))
    }

    #[func]
    fn toggle_dead_group(&mut self, coord: Vector2i) -> bool {
        let accepted = self.engine.toggle_dead_group(coord_from_vector(coord));
        self.refresh_codec();
        accepted
    }

    #[func]
    fn resume_play(&mut self) -> bool {
        let accepted = self.engine.resume_play();
        self.refresh_codec();
        accepted
    }

    #[func]
    fn confirm_scoring(&mut self) -> bool {
        let accepted = self.engine.confirm_scoring();
        self.refresh_codec();
        accepted
    }

    #[func]
    fn get_scoring_board(&self) -> VarDictionary {
        serialize_board_snapshot(&self.engine.get_scoring_board())
    }

    #[func]
    fn build_turn_snapshot(&self) -> VarDictionary {
        self.export_state()
    }

    #[func]
    fn consume_events(&mut self) -> VarArray {
        serialize_events(&self.engine.consume_events())
    }

    #[func]
    fn export_state(&self) -> VarDictionary {
        serialize_engine_state(&self.engine, &self.action_codec)
    }

    #[func]
    fn binding_status(&self) -> GString {
        GString::from("native bridge ready")
    }

    #[func]
    fn observation_transport(&self) -> VarDictionary {
        serialize_observation_dict(&self.engine.build_observation(Some(&self.action_codec)))
    }

    #[func]
    fn step_action_index(&mut self, action_index: i64) -> VarDictionary {
        let mut result = VarDictionary::new();
        let Some(action) = self.action_codec.decode_action_index(action_index as usize) else {
            result.set("accepted", false);
            result.set("reason", "invalid_action_index");
            return result;
        };
        let step = self.engine.step_action(action, Some(&self.action_codec));
        self.refresh_codec();
        let events = serialize_events(&step.events);
        let observation = serialize_observation_dict(&step.observation);
        result.set("accepted", step.accepted);
        result.set("events", &events);
        result.set("observation", &observation);
        result
    }
}

impl HexGoNativeEngine {
    fn refresh_codec(&mut self) {
        self.action_codec = ActionCodec::new(&self.engine.board);
    }
}

pub struct GodotBridgeEngine {
    engine: MatchEngine,
    action_codec: ActionCodec,
}

impl GodotBridgeEngine {
    pub fn new(rules: RulesConfig) -> Self {
        let engine = MatchEngine::new(rules);
        let action_codec = ActionCodec::new(&engine.board);
        Self { engine, action_codec }
    }

    pub fn setup_game(&mut self, radius: i32) {
        self.engine.setup_game(radius);
        self.action_codec = ActionCodec::new(&self.engine.board);
    }

    pub fn observation(&self) -> Observation {
        self.engine.build_observation(Some(&self.action_codec))
    }

    pub fn step_action_index(&mut self, action_index: usize) -> Option<StepResult> {
        let action = self.action_codec.decode_action_index(action_index)?;
        let result = self.engine.step_action(action, Some(&self.action_codec));
        self.action_codec = ActionCodec::new(&self.engine.board);
        Some(result)
    }

    pub fn step_coord(&mut self, q: i32, r: i32) -> StepResult {
        let result = self
            .engine
            .step_action(Action::Move(Coord::new(q, r)), Some(&self.action_codec));
        self.action_codec = ActionCodec::new(&self.engine.board);
        result
    }

    pub fn record_pass(&mut self) -> StepResult {
        let result = self.engine.step_action(Action::Pass, Some(&self.action_codec));
        self.action_codec = ActionCodec::new(&self.engine.board);
        result
    }

    pub fn action_codec(&self) -> &ActionCodec {
        &self.action_codec
    }

    pub fn engine(&self) -> &MatchEngine {
        &self.engine
    }
}

pub fn binding_status() -> &'static str {
    "godot gdextension bridge ready"
}

fn coord_from_vector(coord: Vector2i) -> Coord {
    Coord::new(coord.x, coord.y)
}

fn player_to_id(player: Player) -> i32 {
    match player {
        Player::Black => 0,
        Player::White => 1,
    }
}

fn phase_to_id(phase: Phase) -> i32 {
    match phase {
        Phase::Waiting => 0,
        Phase::Placing => 1,
        Phase::ResolvingCapture => 2,
        Phase::ResolvingTerritory => 3,
        Phase::Scoring => 4,
        Phase::GameOver => 5,
    }
}

fn coord_to_variant(coord: Coord) -> Variant {
    let mut array = VarArray::new();
    array.push(coord.q);
    array.push(coord.r);
    array.to_variant()
}

fn coords_to_array(coords: &[Coord]) -> VarArray {
    let mut result = VarArray::new();
    for coord in coords {
        let coord_variant = coord_to_variant(*coord);
        result.push(&coord_variant);
    }
    result
}

fn strings_to_array(strings: &[String]) -> VarArray {
    let mut result = VarArray::new();
    for value in strings {
        result.push(value.as_str());
    }
    result
}

fn serialize_scores(scores: hexgo_core::ScoreTotals) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("black", scores.black as i64);
    result.set("white", scores.white as i64);
    result
}

fn serialize_score_breakdown(breakdown: hexgo_core::ScoreBreakdown) -> VarDictionary {
    let mut result = VarDictionary::new();
    let black = serialize_player_breakdown(breakdown.black);
    let white = serialize_player_breakdown(breakdown.white);
    result.set("black", &black);
    result.set("white", &white);
    result
}

fn serialize_player_breakdown(entry: hexgo_core::PlayerScoreBreakdown) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("pieces", entry.pieces as i64);
    result.set("territory", entry.territory as i64);
    result.set("total", entry.total as i64);
    result
}

fn serialize_move_history(records: &[MoveRecord]) -> VarArray {
    let mut result = VarArray::new();
    for record in records {
        let mut entry = VarDictionary::new();
        match record {
            MoveRecord::Pass { player } => {
                entry.set("type", "pass");
                entry.set("player", player_to_id(*player));
            }
            MoveRecord::Move {
                player,
                coord,
                captured,
                territory_black,
                territory_white,
            } => {
                let captured_array = coords_to_array(captured);
                let territory_black_array = coords_to_array(territory_black);
                let territory_white_array = coords_to_array(territory_white);
                let coord_variant = coord_to_variant(*coord);
                entry.set("type", "move");
                entry.set("player", player_to_id(*player));
                entry.set("coord", &coord_variant);
                entry.set("captured", &captured_array);
                entry.set("territory_black", &territory_black_array);
                entry.set("territory_white", &territory_white_array);
            }
        }
        result.push(&entry);
    }
    result
}

fn serialize_board_snapshot(board: &Board) -> VarDictionary {
    let codec = ActionCodec::new(board);
    let mut ordered_coords = VarArray::new();
    let mut cells = VarArray::new();
    for coord in codec.ordered_coords() {
        let coord_variant = coord_to_variant(*coord);
        ordered_coords.push(&coord_variant);
        let cell = board.get(*coord).unwrap_or(CellState::Empty).as_i32();
        cells.push(cell as i64);
    }

    let mut snapshot = VarDictionary::new();
    snapshot.set("board_radius", board.radius());
    snapshot.set("ordered_coords", &ordered_coords);
    snapshot.set("cells", &cells);
    snapshot
}

fn serialize_engine_state(engine: &MatchEngine, codec: &ActionCodec) -> VarDictionary {
    let mut snapshot = serialize_board_snapshot(&engine.board);
    let move_history = serialize_move_history(&engine.move_history);
    let scores = serialize_scores(engine.scores);
    let score_breakdown = serialize_score_breakdown(engine.score_breakdown);
    let marked_dead_keys = strings_to_array(&engine.get_marked_dead_keys());
    snapshot.set("current_player", player_to_id(engine.current_player));
    snapshot.set("phase", phase_to_id(engine.phase));
    snapshot.set("phase_id", phase_to_id(engine.phase));
    snapshot.set("consecutive_passes", engine.consecutive_passes as i64);
    snapshot.set("move_history", &move_history);
    snapshot.set("scores", &scores);
    snapshot.set("score_breakdown", &score_breakdown);
    snapshot.set("marked_dead_keys", &marked_dead_keys);
    snapshot.set("previous_board_signature", engine.previous_board_signature.as_str());
    snapshot.set("current_board_signature", engine.current_board_signature.as_str());
    snapshot.set(
        "resume_player_after_scoring",
        player_to_id(engine.resume_player_after_scoring),
    );
    snapshot.set("action_count", codec.action_count() as i64);
    snapshot.set("pass_action_index", codec.pass_action_index() as i64);
    snapshot
}

fn serialize_observation_dict(observation: &Observation) -> VarDictionary {
    let mut result = VarDictionary::new();
    let rules = serialize_rules(observation.rules);
    let scores = serialize_scores(observation.scores);
    let score_breakdown = serialize_score_breakdown(observation.score_breakdown);
    let marked_dead_keys = strings_to_array(&observation.marked_dead_keys);
    let mut ordered_coords = VarArray::new();
    let mut cells = VarArray::new();
    let mut legal_mask = VarArray::new();
    let mut legal_indices = VarArray::new();

    for coord in &observation.ordered_coords {
        let coord_variant = coord_to_variant(*coord);
        ordered_coords.push(&coord_variant);
    }
    for cell in &observation.cells {
        cells.push(*cell as i64);
    }
    for value in &observation.legal_action_mask {
        legal_mask.push(*value as i64);
    }
    for value in &observation.legal_action_indices {
        legal_indices.push(*value as i64);
    }

    let game_result = serialize_result(observation.result);
    result.set("protocol_version", observation.protocol_version as i64);
    result.set("rules", &rules);
    result.set("board_radius", observation.board_radius);
    result.set("phase", phase_to_id(observation.phase));
    result.set("phase_name", observation.phase.as_str());
    result.set("phase_id", phase_to_id(observation.phase));
    result.set("current_player", player_to_id(observation.current_player));
    result.set("current_player_name", observation.current_player.as_str());
    result.set("consecutive_passes", observation.consecutive_passes as i64);
    result.set("move_count", observation.move_count as i64);
    result.set("previous_board_signature", observation.previous_board_signature.as_str());
    result.set("current_board_signature", observation.current_board_signature.as_str());
    result.set("scores", &scores);
    result.set("score_breakdown", &score_breakdown);
    result.set("marked_dead_keys", &marked_dead_keys);
    result.set("ordered_coords", &ordered_coords);
    result.set("cells", &cells);
    result.set("legal_action_mask", &legal_mask);
    result.set("legal_action_indices", &legal_indices);
    result.set("action_count", observation.action_count as i64);
    result.set("pass_action_index", observation.pass_action_index as i64);
    result.set("result", &game_result);
    result
}

fn serialize_rules(rules: RulesConfig) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("board_radius", rules.board_radius);
    result.set("scoring_mode", rules.scoring_mode.as_str());
    result
}

fn serialize_result(result_value: hexgo_core::GameResult) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("is_game_over", result_value.is_game_over);
    result.set(
        "winner",
        result_value
            .winner
            .map(Player::as_str)
            .unwrap_or_default(),
    );
    result.set("margin", result_value.margin);
    result
}

fn serialize_event(event: &Event) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("type", event_type_name(event.event_type));
    if let Some(player) = event.player {
        result.set("player", player_to_id(player));
        result.set("player_name", player.as_str());
    }
    if let Some(coord) = event.coord {
        let coord_variant = coord_to_variant(coord);
        result.set("coord", &coord_variant);
    }
    if !event.coords.is_empty() {
        let coords = coords_to_array(&event.coords);
        result.set("coords", &coords);
    }
    if let Some(scores) = event.scores {
        let serialized_scores = serialize_scores(scores);
        result.set("scores", &serialized_scores);
    }
    if !event.marked_dead_keys.is_empty() {
        let marked_dead_keys = strings_to_array(&event.marked_dead_keys);
        result.set("marked_dead_keys", &marked_dead_keys);
    }
    if let Some(board_radius) = event.board_radius {
        result.set("board_radius", board_radius);
    }
    result
}

fn serialize_events(events: &[Event]) -> VarArray {
    let mut result = VarArray::new();
    for event in events {
        let serialized = serialize_event(event);
        result.push(&serialized);
    }
    result
}

fn event_type_name(event_type: EventType) -> &'static str {
    match event_type {
        EventType::BoardInitialized => "board_initialized",
        EventType::PiecePlaced => "piece_placed",
        EventType::PiecesCaptured => "pieces_captured",
        EventType::TerritoryFormed => "territory_formed",
        EventType::TurnCompleted => "turn_completed",
        EventType::ScoringStateChanged => "scoring_state_changed",
        EventType::GameOver => "game_over",
    }
}

fn serialize_visible_threats(board: &Board, phase: Phase) -> VarDictionary {
    if matches!(phase, Phase::Scoring | Phase::GameOver) {
        return VarDictionary::new();
    }

    let mut result = VarDictionary::new();
    let mut visited: HashSet<Coord> = HashSet::new();
    for coord in board.all_coords() {
        let state = board.get(*coord).unwrap_or(CellState::Empty);
        if !matches!(state, CellState::Black | CellState::White) {
            continue;
        }
        if visited.contains(coord) {
            continue;
        }

        let group = find_group(board, *coord, state);
        let liberties = get_liberties(board, &group) as i64;
        let level = if liberties <= 1 {
            "DANGER"
        } else if liberties == 2 {
            "WARNING"
        } else {
            "SAFE"
        };

        let mut entry = VarDictionary::new();
        entry.set("liberties", liberties);
        entry.set("threat_level", level);
        for item in &group {
            visited.insert(*item);
            result.set(item.key(), &entry);
        }
    }
    result
}

fn find_group(board: &Board, start_coord: Coord, target_state: CellState) -> Vec<Coord> {
    if board.get(start_coord) != Some(target_state) {
        return Vec::new();
    }

    let mut visited: HashSet<Coord> = HashSet::new();
    let mut queue: VecDeque<Coord> = VecDeque::new();
    let mut group = Vec::new();
    queue.push_back(start_coord);

    while let Some(current) = queue.pop_front() {
        if !visited.insert(current) {
            continue;
        }
        group.push(current);

        for neighbor in board.get_neighbors(current) {
            if visited.contains(&neighbor) {
                continue;
            }
            if board.get(neighbor) == Some(target_state) {
                queue.push_back(neighbor);
            }
        }
    }

    group
}

fn get_liberties(board: &Board, group: &[Coord]) -> usize {
    let mut liberties: HashSet<Coord> = HashSet::new();
    for coord in group {
        for neighbor in board.get_neighbors(*coord) {
            if board.get(neighbor) == Some(CellState::Empty) {
                liberties.insert(neighbor);
            }
        }
    }
    liberties.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use hexgo_core::{Player, PROTOCOL_VERSION};

    #[test]
    fn bridge_engine_exposes_an_observation_and_pass_index() {
        let bridge = GodotBridgeEngine::new(RulesConfig::default());
        let observation = bridge.observation();
        assert_eq!(observation.protocol_version, PROTOCOL_VERSION);
        assert_eq!(observation.pass_action_index + 1, observation.action_count);
    }

    #[test]
    fn bridge_engine_can_step_by_action_index() {
        let mut bridge = GodotBridgeEngine::new(RulesConfig::new(1, hexgo_core::ScoringMode::ManualReview));
        let action_index = bridge
            .action_codec()
            .coord_to_action_index(Coord::new(0, 0))
            .unwrap();
        let result = bridge.step_action_index(action_index).unwrap();
        assert!(result.accepted);
        assert_eq!(bridge.engine().current_player, Player::White);
    }
}
