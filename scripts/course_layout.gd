extends RefCounted
class_name CourseLayout

const OBSTACLE_SETS_MIN := 8
const OBSTACLE_SETS_MAX := 11
const START_CLEARANCE := 1400.0
const FINISH_CLEARANCE := 700.0
const MIN_SET_SPACING := 550.0
const SET_JITTER := 0.3
const SHAPE_WEIGHTS := {"single": 15, "cluster": 30, "partial": 25, "row": 20, "slalom": 10}
const CLUSTER_COUNT_MIN := 3
const CLUSTER_COUNT_MAX := 5
const CLUSTER_SPREAD := 50.0
const CLUSTER_STEP := 40.0
const PARTIAL_COUNT_MIN := 3
const PARTIAL_COUNT_MAX := 5
const PARTIAL_LANE_MIN := 100.0
const SLALOM_ROWS_MIN := 2
const SLALOM_ROWS_MAX := 3
const SLALOM_ROW_SPACING := 190.0
const SLALOM_COVER_MIN := 0.55
const SLALOM_COVER_MAX := 0.65
const HARD_CHANCE := 0.5
const TILT_JITTER := 0.105
const WALL_MARGIN := 14.0
const OBSTACLE_HALF_SIZE := 18.0
const OBSTACLE_SPACING_MAX := 46.0
const GAP_MIN := 80.0
const GAP_MAX := 140.0
const MAX_ROAD_WIDTH := 460.0
const MIN_SIDE_WIDTH := 90.0
const SECTION_SEARCH_STEP := 40.0
const ART_SAMPLE_STEP := 16.0
const ART_EDGE_INSET := 20.0
const ART_EDGE_OUTSET := 24.0

const BOX_ROWS := 2
const BOX_ROW_COUNT_MIN := 3
const BOX_ROW_COUNT_MAX := 4
const BOX_SINGLES_MIN := 3
const BOX_SINGLES_MAX := 4
const BOX_GAP_CHANCE := 0.4
const BOX_RANDOM_CHANCE := 0.3
const BOX_MIN_DISTANCE := 350.0
const BOX_OBSTACLE_CLEARANCE := 150.0
const BOX_ATTEMPTS := 40

var obstacles: Array[Dictionary] = []
var obstacle_spans: Array[Vector2] = []
var row_gaps: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _track: RaceTrack
var _length := 0.0
var _is_drawn_road: Callable


func _init(track: RaceTrack, seed_value: int, is_drawn_road: Callable = Callable()) -> void:
	_track = track
	_is_drawn_road = is_drawn_road
	_rng.seed = seed_value
	_length = track.get_course_length() * track.global_scale.x


func generate_obstacles() -> void:
	obstacles.clear()
	obstacle_spans.clear()
	row_gaps.clear()
	var set_count := _rng.randi_range(OBSTACLE_SETS_MIN, OBSTACLE_SETS_MAX)
	var usable := _length - START_CLEARANCE - FINISH_CLEARANCE
	var slot := usable / set_count
	for set_index in range(set_count):
		var slot_start := START_CLEARANCE + slot * set_index
		var target := slot_start + slot * (0.5 + _rng.randf_range(-SET_JITTER, SET_JITTER))
		_place_set(target, slot_start, slot_start + slot, set_index)
	var next_index := set_count
	while obstacle_spans.size() < set_count and _fill_largest_gap(next_index):
		next_index += 1


func _place_set(target: float, low: float, high: float, set_index: int) -> bool:
	var shape := _pick_shape()
	var rows := _rng.randi_range(SLALOM_ROWS_MIN, SLALOM_ROWS_MAX) if shape == "slalom" else 1
	var cluster_count := _rng.randi_range(CLUSTER_COUNT_MIN, CLUSTER_COUNT_MAX)
	var depth := 0.0
	match shape:
		"cluster":
			depth = CLUSTER_STEP * (cluster_count - 1)
		"slalom":
			depth = SLALOM_ROW_SPACING * (rows - 1)
	var distance := _find_set_distance(clampf(target, low, high - depth), low, high - depth, depth)
	if distance < 0.0:
		return false
	var hard := _rng.randf() < HARD_CHANCE
	match shape:
		"single":
			_add_single(distance, hard, set_index)
		"cluster":
			_add_cluster(distance, cluster_count, hard, set_index)
		"partial":
			_add_partial(distance, hard, set_index)
		"row":
			_add_row(distance, hard, set_index)
		"slalom":
			_add_slalom(distance, rows, hard, set_index)
	obstacle_spans.append(Vector2(distance - OBSTACLE_HALF_SIZE, distance + depth + OBSTACLE_HALF_SIZE))
	obstacle_spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return true


func _pick_shape() -> String:
	var total := 0
	for weight in SHAPE_WEIGHTS.values():
		total += weight
	var roll := _rng.randi_range(1, total)
	for shape in SHAPE_WEIGHTS:
		roll -= SHAPE_WEIGHTS[shape]
		if roll <= 0:
			return shape
	return "single"


func _fill_largest_gap(set_index: int) -> bool:
	var gaps: Array[Vector2] = []
	var cursor := START_CLEARANCE
	for span in obstacle_spans:
		gaps.append(Vector2(cursor, span.x))
		cursor = span.y
	gaps.append(Vector2(cursor, _length - FINISH_CLEARANCE))
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y - a.x > b.y - b.x)
	for gap in gaps:
		if _place_set((gap.x + gap.y) * 0.5, gap.x, gap.y, set_index):
			return true
	return false


func generate_item_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for gap in row_gaps:
		if _rng.randf() < BOX_GAP_CHANCE:
			boxes.append(_box(gap.position, "gap", gap.distance))
	for row in range(BOX_ROWS):
		for attempt in range(BOX_ATTEMPTS):
			var distance := _rng.randf_range(START_CLEARANCE, _length - FINISH_CLEARANCE)
			var section := section_at(distance)
			if not _is_free(distance, section, boxes):
				continue
			var count := _rng.randi_range(BOX_ROW_COUNT_MIN, BOX_ROW_COUNT_MAX)
			var low: float = -section.right + WALL_MARGIN + OBSTACLE_HALF_SIZE
			var high: float = section.left - WALL_MARGIN - OBSTACLE_HALF_SIZE
			for index in range(count):
				var across := lerpf(low, high, (index + 0.5) / count)
				boxes.append(_box(section.center + section.normal * across, "row", distance))
			break
	var singles := _rng.randi_range(BOX_SINGLES_MIN, BOX_SINGLES_MAX)
	for single in range(singles):
		for attempt in range(BOX_ATTEMPTS):
			var distance := _rng.randf_range(START_CLEARANCE, _length - FINISH_CLEARANCE)
			var section := section_at(distance)
			if not _is_free(distance, section, boxes):
				continue
			var across := _rng.randf_range(-section.right + WALL_MARGIN + OBSTACLE_HALF_SIZE, section.left - WALL_MARGIN - OBSTACLE_HALF_SIZE)
			var position: Vector2 = section.center + section.normal * across
			if _too_close(position, boxes):
				continue
			boxes.append(_box(position, "single", distance))
			break
	return boxes


func section_at(distance: float) -> Dictionary:
	return _track.get_road_section(distance / _track.global_scale.x)


func is_usable_section(section: Dictionary) -> bool:
	if section.left + section.right > MAX_ROAD_WIDTH or section.left < MIN_SIDE_WIDTH or section.right < MIN_SIDE_WIDTH:
		return false
	return not _is_drawn_road.is_valid() or _matches_drawn_road(section)


func upright_rotation(section: Dictionary) -> float:
	return section.tangent.angle() + PI * 0.5


func _matches_drawn_road(section: Dictionary) -> bool:
	var normal: Vector2 = section.normal
	var center: Vector2 = section.center
	var across: float = -section.right + ART_EDGE_INSET
	while across <= section.left - ART_EDGE_INSET:
		if not _is_drawn_road.call(center + normal * across):
			return false
		across += ART_SAMPLE_STEP
	var beyond_left: Vector2 = center + normal * (section.left + ART_EDGE_OUTSET)
	var beyond_right: Vector2 = center - normal * (section.right + ART_EDGE_OUTSET)
	return not _is_drawn_road.call(beyond_left) and not _is_drawn_road.call(beyond_right)


func _find_set_distance(target: float, low: float, high: float, depth: float) -> float:
	var step := 0.0
	while step <= (high - low):
		for candidate in [target + step, target - step]:
			if candidate >= low and candidate <= high and _clear_of_sets(candidate, depth) and _usable_span(candidate, depth):
				return candidate
		step += SECTION_SEARCH_STEP
	return -1.0


func _clear_of_sets(distance: float, depth: float) -> bool:
	for span in obstacle_spans:
		if distance + depth + OBSTACLE_HALF_SIZE > span.x - MIN_SET_SPACING and distance - OBSTACLE_HALF_SIZE < span.y + MIN_SET_SPACING:
			return false
	return true


func _usable_span(distance: float, depth: float) -> bool:
	var probe := 0.0
	while probe <= depth:
		if not is_usable_section(section_at(distance + probe)):
			return false
		probe += SECTION_SEARCH_STEP
	return true


func _center_range(section: Dictionary) -> Vector2:
	return Vector2(-section.right + WALL_MARGIN + OBSTACLE_HALF_SIZE, section.left - WALL_MARGIN - OBSTACLE_HALF_SIZE)


func _add_single(distance: float, hard: bool, set_index: int) -> void:
	var section := section_at(distance)
	var span := _center_range(section)
	_add_obstacle(section, distance, _rng.randf_range(span.x, span.y), hard, set_index, "single")


func _add_cluster(distance: float, count: int, hard: bool, set_index: int) -> void:
	var span := _center_range(section_at(distance))
	var anchor := _rng.randf_range(span.x + CLUSTER_SPREAD, span.y - CLUSTER_SPREAD)
	for index in range(count):
		var along := CLUSTER_STEP * index
		var across := anchor + _rng.randf_range(-CLUSTER_SPREAD, CLUSTER_SPREAD)
		_add_obstacle(section_at(distance + along), distance + along, across, hard, set_index, "cluster")


func _add_partial(distance: float, hard: bool, set_index: int) -> void:
	var section := section_at(distance)
	var span := _center_range(section)
	var count := _rng.randi_range(PARTIAL_COUNT_MIN, PARTIAL_COUNT_MAX)
	while count > 1 and (span.y - span.x) - OBSTACLE_SPACING_MAX * (count - 1) < PARTIAL_LANE_MIN:
		count -= 1
	var length := OBSTACLE_SPACING_MAX * (count - 1)
	var inset := _rng.randf_range(0.0, maxf((span.y - span.x) - length - PARTIAL_LANE_MIN, 0.0))
	var start := span.x + inset if _rng.randf() < 0.5 else span.y - length - inset
	for index in range(count):
		_add_obstacle(section, distance, start + OBSTACLE_SPACING_MAX * index, hard, set_index, "partial")


func _add_row(distance: float, hard: bool, set_index: int) -> void:
	var section := section_at(distance)
	var low: float = -section.right + WALL_MARGIN
	var high: float = section.left - WALL_MARGIN
	var gap_width := _rng.randf_range(GAP_MIN, GAP_MAX)
	var gap_low := _rng.randf_range(low, high - gap_width)
	_fill_row(section, distance, low, high, gap_low, gap_low + gap_width, hard, set_index, "row")
	var gap_center := gap_low + gap_width * 0.5
	row_gaps.append({"position": section.center + section.normal * gap_center, "distance": distance, "width": gap_width})


func _add_slalom(distance: float, rows: int, hard: bool, set_index: int) -> void:
	var from_left := _rng.randf() < 0.5
	for row in range(rows):
		var row_distance := distance + SLALOM_ROW_SPACING * row
		var section := section_at(row_distance)
		var low: float = -section.right + WALL_MARGIN
		var high: float = section.left - WALL_MARGIN
		var cover: float = (high - low) * _rng.randf_range(SLALOM_COVER_MIN, SLALOM_COVER_MAX)
		if from_left:
			_fill_row(section, row_distance, low, high, low, high - cover, hard, set_index, "slalom")
		else:
			_fill_row(section, row_distance, low, high, low + cover, high, hard, set_index, "slalom")
		from_left = not from_left


func _fill_row(section: Dictionary, distance: float, low: float, high: float, gap_low: float, gap_high: float, hard: bool, set_index: int, shape: String) -> void:
	_fill_segment(section, distance, low, gap_low, hard, set_index, shape)
	_fill_segment(section, distance, gap_high, high, hard, set_index, shape)


func _fill_segment(section: Dictionary, distance: float, from: float, to: float, hard: bool, set_index: int, shape: String) -> void:
	var reach := to - from - OBSTACLE_HALF_SIZE * 2.0
	if reach < 0.0:
		return
	var count := ceili(reach / OBSTACLE_SPACING_MAX) + 1
	for index in range(count):
		var across := from + OBSTACLE_HALF_SIZE + (reach * index / (count - 1) if count > 1 else reach * 0.5)
		_add_obstacle(section, distance, across, hard, set_index, shape)


func _add_obstacle(section: Dictionary, distance: float, across: float, hard: bool, set_index: int, shape: String) -> void:
	obstacles.append({
		"position": section.center + section.normal * across,
		"rotation": upright_rotation(section) + _rng.randf_range(-TILT_JITTER, TILT_JITTER),
		"hard": hard,
		"set": set_index,
		"shape": shape,
		"distance": distance,
	})


func _is_free(distance: float, section: Dictionary, boxes: Array[Dictionary]) -> bool:
	if not is_usable_section(section):
		return false
	for span in obstacle_spans:
		if distance > span.x - BOX_OBSTACLE_CLEARANCE and distance < span.y + BOX_OBSTACLE_CLEARANCE:
			return false
	for box in boxes:
		if absf(box.distance - distance) < BOX_MIN_DISTANCE:
			return false
	return true


func _too_close(position: Vector2, boxes: Array[Dictionary]) -> bool:
	for box in boxes:
		if box.position.distance_to(position) < BOX_MIN_DISTANCE:
			return true
	return false


func _box(position: Vector2, kind: String, distance: float) -> Dictionary:
	var state := -1
	if _rng.randf() >= BOX_RANDOM_CHANCE:
		state = _rng.randi_range(0, PathEffects.State.size() - 1)
	return {"position": position, "state": state, "kind": kind, "distance": distance, "rotation": upright_rotation(section_at(distance))}
