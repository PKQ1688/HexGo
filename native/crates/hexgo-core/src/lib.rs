use std::collections::{HashSet, VecDeque};

pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Coord {
    pub q: i32,
    pub r: i32,
}

impl Coord {
    pub const fn new(q: i32, r: i32) -> Self {
        Self { q, r }
    }

    pub const fn s(self) -> i32 {
        -self.q - self.r
    }

    pub fn neighbors(self) -> [Coord; 6] {
        [
            Coord::new(self.q + 1, self.r),
            Coord::new(self.q + 1, self.r - 1),
            Coord::new(self.q, self.r - 1),
            Coord::new(self.q - 1, self.r),
            Coord::new(self.q - 1, self.r + 1),
            Coord::new(self.q, self.r + 1),
        ]
    }

    pub fn key(self) -> String {
        format!("{},{}", self.q, self.r)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CellState {
    Empty,
    Black,
    White,
    TerritoryBlack,
    TerritoryWhite,
}

impl CellState {
    pub const fn as_i32(self) -> i32 {
        match self {
            CellState::Empty => 0,
            CellState::Black => 1,
            CellState::White => 2,
            CellState::TerritoryBlack => 3,
            CellState::TerritoryWhite => 4,
        }
    }
}

impl Default for CellState {
    fn default() -> Self {
        Self::Empty
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Player {
    Black,
    White,
}

impl Player {
    pub const fn other(self) -> Self {
        match self {
            Player::Black => Player::White,
            Player::White => Player::Black,
        }
    }

    pub const fn piece_state(self) -> CellState {
        match self {
            Player::Black => CellState::Black,
            Player::White => CellState::White,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Player::Black => "black",
            Player::White => "white",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Waiting,
    Placing,
    ResolvingCapture,
    ResolvingTerritory,
    Scoring,
    GameOver,
}

impl Phase {
    pub const fn as_str(self) -> &'static str {
        match self {
            Phase::Waiting => "waiting",
            Phase::Placing => "placing",
            Phase::ResolvingCapture => "resolving_capture",
            Phase::ResolvingTerritory => "resolving_territory",
            Phase::Scoring => "scoring",
            Phase::GameOver => "game_over",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScoringMode {
    ManualReview,
    AutoSettle,
}

impl ScoringMode {
    pub const fn as_str(self) -> &'static str {
        match self {
            ScoringMode::ManualReview => "manual_review",
            ScoringMode::AutoSettle => "auto_settle",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RulesConfig {
    pub board_radius: i32,
    pub scoring_mode: ScoringMode,
}

impl RulesConfig {
    pub const fn new(board_radius: i32, scoring_mode: ScoringMode) -> Self {
        Self {
            board_radius,
            scoring_mode,
        }
    }
}

impl Default for RulesConfig {
    fn default() -> Self {
        Self::new(5, ScoringMode::ManualReview)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Board {
    radius: i32,
    all_coords: Vec<Coord>,
    cells: Vec<CellState>,
}

impl Board {
    pub fn new(radius: i32) -> Self {
        let mut all_coords = Vec::new();
        for q in -radius..=radius {
            for r in -radius..=radius {
                let coord = Coord::new(q, r);
                if q.abs().max(r.abs()).max(coord.s().abs()) > radius {
                    continue;
                }
                all_coords.push(coord);
            }
        }
        let cells = vec![CellState::Empty; all_coords.len()];
        Self {
            radius,
            all_coords,
            cells,
        }
    }

    pub fn radius(&self) -> i32 {
        self.radius
    }

    pub fn all_coords(&self) -> &[Coord] {
        &self.all_coords
    }

    fn index_of(&self, coord: Coord) -> Option<usize> {
        self.all_coords.iter().position(|existing| *existing == coord)
    }

    pub fn is_valid_coord(&self, coord: Coord) -> bool {
        coord.q.abs().max(coord.r.abs()).max(coord.s().abs()) <= self.radius
    }

    pub fn get(&self, coord: Coord) -> Option<CellState> {
        self.index_of(coord).map(|index| self.cells[index])
    }

    pub fn set(&mut self, coord: Coord, state: CellState) -> bool {
        if let Some(index) = self.index_of(coord) {
            self.cells[index] = state;
            true
        } else {
            false
        }
    }

    pub fn get_neighbors(&self, coord: Coord) -> Vec<Coord> {
        coord
            .neighbors()
            .into_iter()
            .filter(|neighbor| self.is_valid_coord(*neighbor))
            .collect()
    }

    pub fn get_empty_cells(&self) -> Vec<Coord> {
        self.all_coords
            .iter()
            .copied()
            .filter(|coord| self.get(*coord) == Some(CellState::Empty))
            .collect()
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PlayerScoreBreakdown {
    pub pieces: u32,
    pub territory: u32,
    pub total: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ScoreBreakdown {
    pub black: PlayerScoreBreakdown,
    pub white: PlayerScoreBreakdown,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ScoreTotals {
    pub black: u32,
    pub white: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TerritoryMap {
    pub black: Vec<Coord>,
    pub white: Vec<Coord>,
}

impl TerritoryMap {
    pub fn for_player(&self, player: Player) -> &[Coord] {
        match player {
            Player::Black => &self.black,
            Player::White => &self.white,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GameResult {
    pub is_game_over: bool,
    pub winner: Option<Player>,
    pub margin: i32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Observation {
    pub protocol_version: u32,
    pub rules: RulesConfig,
    pub board_radius: i32,
    pub phase: Phase,
    pub current_player: Player,
    pub consecutive_passes: u32,
    pub move_count: usize,
    pub previous_board_signature: String,
    pub current_board_signature: String,
    pub scores: ScoreTotals,
    pub score_breakdown: ScoreBreakdown,
    pub marked_dead_keys: Vec<String>,
    pub ordered_coords: Vec<Coord>,
    pub cells: Vec<i32>,
    pub action_count: usize,
    pub pass_action_index: usize,
    pub legal_action_mask: Vec<u8>,
    pub legal_action_indices: Vec<usize>,
    pub result: GameResult,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EventType {
    BoardInitialized,
    PiecePlaced,
    PiecesCaptured,
    TerritoryFormed,
    TurnCompleted,
    ScoringStateChanged,
    GameOver,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event {
    pub event_type: EventType,
    pub coord: Option<Coord>,
    pub coords: Vec<Coord>,
    pub player: Option<Player>,
    pub scores: Option<ScoreTotals>,
    pub marked_dead_keys: Vec<String>,
    pub board_radius: Option<i32>,
}

impl Event {
    fn new(event_type: EventType) -> Self {
        Self {
            event_type,
            coord: None,
            coords: Vec::new(),
            player: None,
            scores: None,
            marked_dead_keys: Vec::new(),
            board_radius: None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    Move(Coord),
    Pass,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StepResult {
    pub accepted: bool,
    pub action: Action,
    pub events: Vec<Event>,
    pub observation: Observation,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActionCodec {
    ordered_coords: Vec<Coord>,
}

impl ActionCodec {
    pub fn new(board: &Board) -> Self {
        let mut ordered_coords = board.all_coords().to_vec();
        ordered_coords.sort_by_key(|coord| (coord.q, coord.r, coord.s()));
        Self { ordered_coords }
    }

    pub fn ordered_coords(&self) -> &[Coord] {
        &self.ordered_coords
    }

    pub fn action_count(&self) -> usize {
        self.ordered_coords.len() + 1
    }

    pub fn pass_action_index(&self) -> usize {
        self.ordered_coords.len()
    }

    pub fn is_pass_action(&self, action_index: usize) -> bool {
        action_index == self.pass_action_index()
    }

    pub fn coord_to_action_index(&self, coord: Coord) -> Option<usize> {
        self.ordered_coords
            .iter()
            .position(|existing| *existing == coord)
    }

    pub fn action_index_to_coord(&self, action_index: usize) -> Option<Coord> {
        self.ordered_coords.get(action_index).copied()
    }

    pub fn decode_action_index(&self, action_index: usize) -> Option<Action> {
        if self.is_pass_action(action_index) {
            return Some(Action::Pass);
        }
        self.action_index_to_coord(action_index).map(Action::Move)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MoveRecord {
    Pass {
        player: Player,
    },
    Move {
        player: Player,
        coord: Coord,
        captured: Vec<Coord>,
        territory_black: Vec<Coord>,
        territory_white: Vec<Coord>,
    },
}

#[derive(Clone, Debug)]
struct SimulatedTurn {
    legal: bool,
    board: Board,
    captured: Vec<Coord>,
    territory_map: TerritoryMap,
    scores: ScoreTotals,
    board_signature: String,
    next_player: Player,
    ended_by_double_pass: bool,
    consecutive_passes: u32,
    self_group: Vec<Coord>,
    self_group_liberties: usize,
}

impl SimulatedTurn {
    fn illegal(
        source_board: &Board,
        current_player: Player,
        current_board_signature: &str,
        dead_stones: &HashSet<Coord>,
    ) -> Self {
        let signature = if current_board_signature.is_empty() {
            board_signature(source_board)
        } else {
            current_board_signature.to_string()
        };
        Self {
            legal: false,
            board: source_board.clone(),
            captured: Vec::new(),
            territory_map: resolve_all_territory(source_board),
            scores: calculate(source_board, dead_stones),
            board_signature: signature,
            next_player: current_player,
            ended_by_double_pass: false,
            consecutive_passes: 0,
            self_group: Vec::new(),
            self_group_liberties: 0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct MatchEngine {
    pub board_radius: i32,
    pub board: Board,
    pub current_player: Player,
    pub phase: Phase,
    pub consecutive_passes: u32,
    pub move_history: Vec<MoveRecord>,
    pub scores: ScoreTotals,
    pub score_breakdown: ScoreBreakdown,
    pub marked_dead_stones: HashSet<Coord>,
    pub previous_board_signature: String,
    pub current_board_signature: String,
    pub resume_player_after_scoring: Player,
    pub scoring_mode: ScoringMode,
    pending_events: Vec<Event>,
}

impl MatchEngine {
    pub fn new(rules: RulesConfig) -> Self {
        let mut engine = Self {
            board_radius: rules.board_radius,
            board: Board::new(rules.board_radius),
            current_player: Player::Black,
            phase: Phase::Waiting,
            consecutive_passes: 0,
            move_history: Vec::new(),
            scores: ScoreTotals::default(),
            score_breakdown: ScoreBreakdown::default(),
            marked_dead_stones: HashSet::new(),
            previous_board_signature: String::new(),
            current_board_signature: String::new(),
            resume_player_after_scoring: Player::Black,
            scoring_mode: rules.scoring_mode,
            pending_events: Vec::new(),
        };
        engine.setup_game(rules.board_radius);
        engine
    }

    pub fn rules_config(&self) -> RulesConfig {
        RulesConfig::new(self.board_radius, self.scoring_mode)
    }

    pub fn setup_game(&mut self, radius: i32) {
        self.pending_events.clear();
        self.board_radius = radius;
        self.board = Board::new(radius);
        self.current_player = Player::Black;
        self.phase = Phase::Waiting;
        self.consecutive_passes = 0;
        self.move_history.clear();
        self.marked_dead_stones.clear();
        self.previous_board_signature.clear();
        self.current_board_signature = board_signature(&self.board);
        self.resume_player_after_scoring = Player::Black;
        self.update_scores();
        self.queue_scoring_preview_events();

        let mut board_event = Event::new(EventType::BoardInitialized);
        board_event.board_radius = Some(radius);
        self.queue_event(board_event);

        let mut scoring_event = Event::new(EventType::ScoringStateChanged);
        scoring_event.marked_dead_keys = Vec::new();
        self.queue_event(scoring_event);
        self.queue_turn_completed_event();
    }

    pub fn switch_player(&mut self) {
        self.current_player = self.current_player.other();
    }

    pub fn can_pass(&self) -> bool {
        self.phase == Phase::Waiting
    }

    pub fn can_place_at(&self, coord: Coord) -> bool {
        if self.phase != Phase::Waiting {
            return false;
        }
        if !self.board.is_valid_coord(coord) {
            return false;
        }
        if self.board.get(coord) != Some(CellState::Empty) {
            return false;
        }
        simulate_place(
            &self.board,
            self.current_player,
            &self.previous_board_signature,
            &self.current_board_signature,
            coord,
            &self.marked_dead_stones,
        )
        .legal
    }

    pub fn execute_turn(&mut self, coord: Coord) -> bool {
        self.pending_events.clear();
        if !self.can_place_at(coord) {
            return false;
        }

        let result = simulate_place(
            &self.board,
            self.current_player,
            &self.previous_board_signature,
            &self.current_board_signature,
            coord,
            &self.marked_dead_stones,
        );
        if !result.legal {
            return false;
        }

        self.phase = Phase::Placing;
        let mut piece_event = Event::new(EventType::PiecePlaced);
        piece_event.coord = Some(coord);
        piece_event.player = Some(self.current_player);
        self.queue_event(piece_event);

        self.phase = Phase::ResolvingCapture;
        if !result.captured.is_empty() {
            let mut capture_event = Event::new(EventType::PiecesCaptured);
            capture_event.coords = result.captured.clone();
            self.queue_event(capture_event);
        }

        self.apply_board_state(&result.board);

        self.phase = Phase::ResolvingTerritory;
        self.queue_territory_event(Player::Black, result.territory_map.black.clone());
        self.queue_territory_event(Player::White, result.territory_map.white.clone());

        self.consecutive_passes = 0;
        self.move_history.push(MoveRecord::Move {
            player: self.current_player,
            coord,
            captured: result.captured.clone(),
            territory_black: result.territory_map.black.clone(),
            territory_white: result.territory_map.white.clone(),
        });

        self.previous_board_signature = self.current_board_signature.clone();
        self.current_board_signature = result.board_signature;
        self.switch_player();
        self.phase = Phase::Waiting;
        self.update_scores();
        self.queue_turn_completed_event();
        true
    }

    pub fn record_pass(&mut self) -> bool {
        self.pending_events.clear();
        if self.phase != Phase::Waiting {
            return false;
        }

        let result = simulate_pass(
            &self.board,
            self.current_player,
            &self.current_board_signature,
            self.consecutive_passes,
            &self.marked_dead_stones,
        );
        self.consecutive_passes = result.consecutive_passes;
        self.move_history
            .push(MoveRecord::Pass { player: self.current_player });

        if result.ended_by_double_pass {
            match self.scoring_mode {
                ScoringMode::ManualReview => self.enter_scoring_phase(),
                ScoringMode::AutoSettle => self.finish_game(),
            }
            return true;
        }

        self.switch_player();
        self.update_scores();
        self.queue_scoring_preview_events();
        self.queue_turn_completed_event();
        true
    }

    pub fn is_scoring_phase(&self) -> bool {
        self.phase == Phase::Scoring
    }

    pub fn can_toggle_dead_at(&self, coord: Coord) -> bool {
        if self.phase != Phase::Scoring {
            return false;
        }
        matches!(
            self.board.get(coord),
            Some(CellState::Black) | Some(CellState::White)
        )
    }

    pub fn toggle_dead_group(&mut self, coord: Coord) -> bool {
        self.pending_events.clear();
        if !self.can_toggle_dead_at(coord) {
            return false;
        }

        let state = match self.board.get(coord) {
            Some(CellState::Black) => CellState::Black,
            Some(CellState::White) => CellState::White,
            _ => return false,
        };
        let group = find_group(&self.board, coord, state);
        let should_mark = group
            .iter()
            .any(|item| !self.marked_dead_stones.contains(item));

        for item in group {
            if should_mark {
                self.marked_dead_stones.insert(item);
            } else {
                self.marked_dead_stones.remove(&item);
            }
        }

        self.update_scores();
        self.queue_scoring_preview_events();

        let mut scoring_event = Event::new(EventType::ScoringStateChanged);
        scoring_event.marked_dead_keys = self.get_marked_dead_keys();
        self.queue_event(scoring_event);
        self.queue_turn_completed_event();
        true
    }

    pub fn resume_play(&mut self) -> bool {
        self.pending_events.clear();
        if self.phase != Phase::Scoring {
            return false;
        }
        self.marked_dead_stones.clear();

        let mut scoring_event = Event::new(EventType::ScoringStateChanged);
        scoring_event.marked_dead_keys = Vec::new();
        self.queue_event(scoring_event);

        self.consecutive_passes = 0;
        self.current_player = self.resume_player_after_scoring;
        self.phase = Phase::Waiting;
        self.update_scores();
        self.queue_scoring_preview_events();
        self.queue_turn_completed_event();
        true
    }

    pub fn confirm_scoring(&mut self) -> bool {
        self.pending_events.clear();
        if self.phase != Phase::Scoring {
            return false;
        }
        self.finish_game();
        true
    }

    pub fn get_marked_dead_keys(&self) -> Vec<String> {
        let mut keys: Vec<String> = self.marked_dead_stones.iter().map(|coord| coord.key()).collect();
        keys.sort();
        keys
    }

    pub fn get_scoring_board(&self) -> Board {
        build_scoring_board(&self.board, &self.marked_dead_stones)
    }

    pub fn legal_action_mask(&self, codec: &ActionCodec) -> Vec<u8> {
        let mut mask: Vec<u8> = codec
            .ordered_coords()
            .iter()
            .map(|coord| if self.can_place_at(*coord) { 1 } else { 0 })
            .collect();
        mask.push(if self.can_pass() { 1 } else { 0 });
        mask
    }

    pub fn build_observation(&self, codec: Option<&ActionCodec>) -> Observation {
        let codec = codec.cloned().unwrap_or_else(|| ActionCodec::new(&self.board));
        let legal_action_mask = self.legal_action_mask(&codec);
        let legal_action_indices = legal_action_mask
            .iter()
            .enumerate()
            .filter_map(|(index, value)| if *value != 0 { Some(index) } else { None })
            .collect();
        let ordered_coords = codec.ordered_coords().to_vec();
        let cells = ordered_coords
            .iter()
            .map(|coord| self.board.get(*coord).unwrap_or(CellState::Empty).as_i32())
            .collect();

        Observation {
            protocol_version: PROTOCOL_VERSION,
            rules: self.rules_config(),
            board_radius: self.board_radius,
            phase: self.phase,
            current_player: self.current_player,
            consecutive_passes: self.consecutive_passes,
            move_count: self.move_history.len(),
            previous_board_signature: self.previous_board_signature.clone(),
            current_board_signature: self.current_board_signature.clone(),
            scores: self.scores,
            score_breakdown: self.score_breakdown,
            marked_dead_keys: self.get_marked_dead_keys(),
            ordered_coords,
            cells,
            action_count: codec.action_count(),
            pass_action_index: codec.pass_action_index(),
            legal_action_mask,
            legal_action_indices,
            result: build_game_result(self.phase, self.scores),
        }
    }

    pub fn step_action(&mut self, action: Action, codec: Option<&ActionCodec>) -> StepResult {
        let accepted = match action {
            Action::Move(coord) => self.execute_turn(coord),
            Action::Pass => self.record_pass(),
        };
        let events = self.consume_events();
        let observation = self.build_observation(codec);
        StepResult {
            accepted,
            action,
            events,
            observation,
        }
    }

    pub fn consume_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.pending_events)
    }

    fn enter_scoring_phase(&mut self) {
        self.phase = Phase::Scoring;
        self.resume_player_after_scoring = self.current_player.other();
        self.update_scores();
        self.queue_scoring_preview_events();

        let mut scoring_event = Event::new(EventType::ScoringStateChanged);
        scoring_event.marked_dead_keys = self.get_marked_dead_keys();
        self.queue_event(scoring_event);
        self.queue_turn_completed_event();
    }

    fn finish_game(&mut self) {
        self.phase = Phase::GameOver;
        self.update_scores();
        self.queue_scoring_preview_events();
        self.queue_turn_completed_event();

        let mut game_over_event = Event::new(EventType::GameOver);
        game_over_event.scores = Some(self.scores);
        self.queue_event(game_over_event);
    }

    fn update_scores(&mut self) {
        let scoring_board = build_scoring_board(&self.board, &self.marked_dead_stones);
        let territory_map = resolve_all_territory(&scoring_board);
        self.score_breakdown = calculate_breakdown_from_territory_map(&scoring_board, &territory_map);
        self.scores = totals_from_breakdown(&self.score_breakdown);
    }

    fn queue_scoring_preview_events(&mut self) {
        let preview_board = self.get_scoring_board();
        let territory_map = resolve_all_territory(&preview_board);
        self.queue_territory_event(Player::Black, territory_map.black.clone());
        self.queue_territory_event(Player::White, territory_map.white.clone());
    }

    fn queue_territory_event(&mut self, player: Player, coords: Vec<Coord>) {
        let mut event = Event::new(EventType::TerritoryFormed);
        event.player = Some(player);
        event.coords = coords;
        self.queue_event(event);
    }

    fn queue_turn_completed_event(&mut self) {
        let mut event = Event::new(EventType::TurnCompleted);
        event.player = Some(self.current_player);
        event.scores = Some(self.scores);
        self.queue_event(event);
    }

    fn queue_event(&mut self, event: Event) {
        self.pending_events.push(event);
    }

    fn apply_board_state(&mut self, source_board: &Board) {
        self.board = source_board.clone();
    }
}

fn board_signature(board: &Board) -> String {
    board
        .all_coords()
        .iter()
        .map(|coord| board.get(*coord).unwrap_or(CellState::Empty).as_i32().to_string())
        .collect::<Vec<_>>()
        .join(",")
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
    let mut liberty_set: HashSet<Coord> = HashSet::new();
    for coord in group {
        for neighbor in board.get_neighbors(*coord) {
            if board.get(neighbor) == Some(CellState::Empty) {
                liberty_set.insert(neighbor);
            }
        }
    }
    liberty_set.len()
}

fn resolve_captured(board: &Board, attacker_state: CellState) -> Vec<Coord> {
    let defender_state = match attacker_state {
        CellState::Black => CellState::White,
        CellState::White => CellState::Black,
        _ => return Vec::new(),
    };

    let mut captured = Vec::new();
    let mut visited_groups: HashSet<Coord> = HashSet::new();

    for coord in board.all_coords() {
        if board.get(*coord) != Some(defender_state) {
            continue;
        }
        if visited_groups.contains(coord) {
            continue;
        }

        let group = find_group(board, *coord, defender_state);
        for item in &group {
            visited_groups.insert(*item);
        }

        if get_liberties(board, &group) == 0 {
            captured.extend(group);
        }
    }

    captured
}

fn determine_region_owner(board: &Board, region: &[Coord]) -> Option<Player> {
    let mut touches_boundary = false;
    let mut border_players: HashSet<Player> = HashSet::new();

    for coord in region {
        let neighbors = board.get_neighbors(*coord);
        if neighbors.len() < 6 {
            touches_boundary = true;
            break;
        }

        for neighbor in neighbors {
            match board.get(neighbor) {
                Some(CellState::Black) => {
                    border_players.insert(Player::Black);
                }
                Some(CellState::White) => {
                    border_players.insert(Player::White);
                }
                _ => {}
            }
        }
    }

    if touches_boundary || border_players.len() != 1 {
        return None;
    }

    border_players.into_iter().next()
}

fn resolve_all_territory(board: &Board) -> TerritoryMap {
    let mut result = TerritoryMap::default();
    let mut visited: HashSet<Coord> = HashSet::new();

    for coord in board.all_coords() {
        if board.get(*coord) != Some(CellState::Empty) {
            continue;
        }
        if visited.contains(coord) {
            continue;
        }

        let region = find_group(board, *coord, CellState::Empty);
        for item in &region {
            visited.insert(*item);
        }

        match determine_region_owner(board, &region) {
            Some(Player::Black) => result.black.extend(region),
            Some(Player::White) => result.white.extend(region),
            None => {}
        }
    }

    result
}

fn build_scoring_board(board: &Board, dead_stones: &HashSet<Coord>) -> Board {
    let mut scoring_board = board.clone();
    for coord in dead_stones {
        scoring_board.set(*coord, CellState::Empty);
    }
    scoring_board
}

fn calculate(board: &Board, dead_stones: &HashSet<Coord>) -> ScoreTotals {
    totals_from_breakdown(&calculate_breakdown(board, dead_stones))
}

fn calculate_breakdown(board: &Board, dead_stones: &HashSet<Coord>) -> ScoreBreakdown {
    let scoring_board = build_scoring_board(board, dead_stones);
    let territory_map = resolve_all_territory(&scoring_board);
    calculate_breakdown_from_territory_map(&scoring_board, &territory_map)
}

fn calculate_from_territory_map(
    board: &Board,
    territory_map: &TerritoryMap,
    dead_stones: &HashSet<Coord>,
) -> ScoreTotals {
    if dead_stones.is_empty() {
        totals_from_breakdown(&calculate_breakdown_from_territory_map(board, territory_map))
    } else {
        calculate(board, dead_stones)
    }
}

fn calculate_breakdown_from_territory_map(
    board: &Board,
    territory_map: &TerritoryMap,
) -> ScoreBreakdown {
    let mut result = ScoreBreakdown::default();

    for coord in board.all_coords() {
        match board.get(*coord).unwrap_or(CellState::Empty) {
            CellState::Black => result.black.pieces += 1,
            CellState::White => result.white.pieces += 1,
            _ => {}
        }
    }

    result.black.territory = territory_map.black.len() as u32;
    result.white.territory = territory_map.white.len() as u32;
    result.black.total = result.black.pieces + result.black.territory;
    result.white.total = result.white.pieces + result.white.territory;
    result
}

fn totals_from_breakdown(breakdown: &ScoreBreakdown) -> ScoreTotals {
    ScoreTotals {
        black: breakdown.black.total,
        white: breakdown.white.total,
    }
}

fn simulate_place(
    source_board: &Board,
    current_player: Player,
    previous_board_signature: &str,
    current_board_signature: &str,
    coord: Coord,
    dead_stones: &HashSet<Coord>,
) -> SimulatedTurn {
    let mut result = SimulatedTurn::illegal(
        source_board,
        current_player,
        current_board_signature,
        dead_stones,
    );

    if !source_board.is_valid_coord(coord) {
        return result;
    }
    if source_board.get(coord) != Some(CellState::Empty) {
        return result;
    }

    let mut board_copy = source_board.clone();
    let piece_state = current_player.piece_state();
    board_copy.set(coord, piece_state);

    let captured = resolve_captured(&board_copy, piece_state);
    for captured_coord in &captured {
        board_copy.set(*captured_coord, CellState::Empty);
    }

    let self_group = find_group(&board_copy, coord, piece_state);
    if self_group.is_empty() {
        return result;
    }

    let liberties = get_liberties(&board_copy, &self_group);
    if liberties == 0 {
        return result;
    }

    let next_signature = board_signature(&board_copy);
    if !previous_board_signature.is_empty() && next_signature == previous_board_signature {
        return result;
    }

    let territory_map = resolve_all_territory(&board_copy);
    result.legal = true;
    result.board = board_copy;
    result.captured = captured;
    result.territory_map = territory_map;
    result.scores = calculate_from_territory_map(&result.board, &result.territory_map, dead_stones);
    result.board_signature = next_signature;
    result.next_player = current_player.other();
    result.self_group = self_group;
    result.self_group_liberties = liberties;
    result.consecutive_passes = 0;
    result
}

fn simulate_pass(
    source_board: &Board,
    current_player: Player,
    current_board_signature: &str,
    consecutive_passes: u32,
    dead_stones: &HashSet<Coord>,
) -> SimulatedTurn {
    let mut result = SimulatedTurn::illegal(
        source_board,
        current_player,
        current_board_signature,
        dead_stones,
    );
    let pass_count = consecutive_passes + 1;
    result.legal = true;
    result.consecutive_passes = pass_count;
    result.ended_by_double_pass = pass_count >= 2;
    result.next_player = current_player.other();
    result
}

fn build_game_result(phase: Phase, scores: ScoreTotals) -> GameResult {
    if phase != Phase::GameOver {
        return GameResult {
            is_game_over: false,
            winner: None,
            margin: 0,
        };
    }

    let margin = scores.black as i32 - scores.white as i32;
    let winner = if margin > 0 {
        Some(Player::Black)
    } else if margin < 0 {
        Some(Player::White)
    } else {
        None
    };

    GameResult {
        is_game_over: true,
        winner,
        margin: margin.abs(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn board_size_formula_matches_radius_three() {
        let board = Board::new(3);
        assert_eq!(board.all_coords().len(), 37);
    }

    #[test]
    fn action_codec_round_trip_matches_gdscript_shape() {
        let board = Board::new(2);
        let codec = ActionCodec::new(&board);
        let center = Coord::new(0, 0);
        let center_index = codec.coord_to_action_index(center).unwrap();
        assert_eq!(codec.action_count(), 20);
        assert!(codec.is_pass_action(codec.pass_action_index()));
        assert_eq!(codec.action_index_to_coord(center_index), Some(center));
        assert_eq!(codec.decode_action_index(codec.pass_action_index()), Some(Action::Pass));
    }

    #[test]
    fn capture_resolver_removes_a_single_surrounded_stone() {
        let mut board = Board::new(2);
        board.set(Coord::new(0, 0), CellState::White);
        for coord in [
            Coord::new(1, 0),
            Coord::new(1, -1),
            Coord::new(0, -1),
            Coord::new(-1, 0),
            Coord::new(-1, 1),
            Coord::new(0, 1),
        ] {
            board.set(coord, CellState::Black);
        }
        let captured = resolve_captured(&board, CellState::Black);
        assert_eq!(captured, vec![Coord::new(0, 0)]);
    }

    #[test]
    fn territory_resolver_marks_a_closed_center_point() {
        let mut board = Board::new(3);
        for coord in [
            Coord::new(1, 0),
            Coord::new(1, -1),
            Coord::new(0, -1),
            Coord::new(-1, 0),
            Coord::new(-1, 1),
            Coord::new(0, 1),
        ] {
            board.set(coord, CellState::Black);
        }
        let territory = resolve_all_territory(&board);
        assert_eq!(territory.black, vec![Coord::new(0, 0)]);
        assert!(territory.white.is_empty());
    }

    #[test]
    fn auto_settle_ends_the_game_after_two_passes() {
        let mut engine = MatchEngine::new(RulesConfig::new(2, ScoringMode::AutoSettle));
        engine.consume_events();
        assert!(engine.record_pass());
        assert_eq!(engine.phase, Phase::Waiting);
        assert!(engine.record_pass());
        assert_eq!(engine.phase, Phase::GameOver);
        let events = engine.consume_events();
        assert_eq!(events.last().map(|event| event.event_type), Some(EventType::GameOver));
    }

    #[test]
    fn observation_contains_protocol_fields_for_bindings() {
        let mut engine = MatchEngine::new(RulesConfig::new(1, ScoringMode::ManualReview));
        engine.consume_events();
        let codec = ActionCodec::new(&engine.board);
        let observation = engine.build_observation(Some(&codec));
        assert_eq!(observation.protocol_version, PROTOCOL_VERSION);
        assert_eq!(observation.rules.board_radius, 1);
        assert_eq!(observation.rules.scoring_mode, ScoringMode::ManualReview);
        assert_eq!(observation.phase, Phase::Waiting);
        assert_eq!(observation.current_player, Player::Black);
        assert_eq!(observation.cells.len(), 7);
        assert_eq!(observation.ordered_coords.len(), 7);
        assert_eq!(observation.legal_action_mask.len(), 8);
        assert!(!observation.result.is_game_over);
    }
}
