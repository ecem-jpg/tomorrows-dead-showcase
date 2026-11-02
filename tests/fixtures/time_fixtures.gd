extends RefCounted
## Zaman testleri için tarafsız veri kurucuları (K-018). Oyun içeriği değildir.
## Varsayılanlar: 2 gece × 10 birim; action_a = 2, action_b = 0.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")


static func make_state() -> GameStateScript:
	return GameStateScript.new(make_state_setup())


static func make_state_setup() -> InitialStateDataScript:
	var setup: InitialStateDataScript = InitialStateDataScript.new()
	setup.id = "state_setup_a"
	setup.rng_seed = 1
	return setup


static func make_rules(night_count: int = 2, night_length_units: int = 10) -> TimeRulesDataScript:
	var rules: TimeRulesDataScript = TimeRulesDataScript.new()
	rules.id = "time_rules_a"
	rules.night_count = night_count
	rules.night_length_units = night_length_units
	rules.action_costs = {&"action_a": 2, &"action_b": 0}
	return rules


static func make_event(id: String, night: int, at_units: int, order: int) -> ScheduledEventDataScript:
	var event: ScheduledEventDataScript = ScheduledEventDataScript.new()
	event.id = id
	event.night = night
	event.at_units = at_units
	event.order = order
	return event


## 1. gecenin 4. biriminde üç olay (beklenen sıra: event_b, event_a, event_c),
## 1. gecenin sınırında event_d, 2. gecede event_e.
static func default_events() -> Array[ScheduledEventDataScript]:
	var events: Array[ScheduledEventDataScript] = [
		make_event("event_c", 1, 4, 1),
		make_event("event_d", 1, 10, 0),
		make_event("event_a", 1, 4, 1),
		make_event("event_e", 2, 3, 0),
		make_event("event_b", 1, 4, 0),
	]
	return events


static func make_system(state: GameStateScript) -> TimeSystemScript:
	return TimeSystemScript.new(state, make_rules(), default_events())


## Olaysız sistem; yalnızca saat davranışını sınayan testler için.
static func make_plain_system(state: GameStateScript, rules: TimeRulesDataScript = null) -> TimeSystemScript:
	var no_events: Array[ScheduledEventDataScript] = []
	return TimeSystemScript.new(state, rules if rules != null else make_rules(), no_events)
