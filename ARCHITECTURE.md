# Architecture Overview

Tomorrow's Dead uses a data-driven, test-first architecture designed to keep gameplay rules independent from scenes and narrative content.

## Layer Responsibilities

### Data

Godot `Resource` classes define configuration for initial state, time rules, trust relationships, tasks, decisions, advice, occurrences, equipment, cable puzzles, and endings.

Gameplay code uses neutral identifiers such as `actor_a`, `task_a`, and `ending_a`. Character names and story details are not hard-coded into systems.

### Core State

`GameState` is the authoritative state container. Changes that affect multiple categories are applied as a single atomic package, preventing partial updates when an action cannot be completed.

State categories include:

- resources and flags;
- time and active tasks;
- directional trust;
- occurrence outcomes;
- equipment state;
- cable-puzzle progress.

### Gameplay Systems

Systems validate and plan operations before state is written. Major systems include:

- `ResourceSystem`
- `TimeSystem`
- `TrustSystem`
- `DecisionSystem`
- `TaskSystem`
- `TaskCompletionSystem`
- `AdviceSystem`
- `OccurrenceSystem`
- `EquipmentSystem`
- `CableRepairSystem`
- `EndingResolver`

Systems communicate through explicit results rather than scene lookups or hidden global state.

### Presentation

The HUD is split into three responsibilities:

- `MainHudModel`: an independent snapshot containing only display-safe information;
- `MainHudConfig`: neutral mappings the UI cannot infer from system state;
- `MainHudPresenter`: translates user commands into public gameplay-system calls.

Hidden advice data, including internal accuracy categories and variant identifiers, is never exposed to the HUD model.

### User Interface

`MainHudView` renders models and emits intent signals. It does not know about `GameState` or gameplay systems.

The main scene keeps its `Node2D` root and instances the HUD as a separate scene:

```text
Main (Node2D)
└─ UI / MainHud (Node)
   ├─ HudLayer (CanvasLayer)
   │  └─ Root (Control)
   └─ MiniGameHost (Node)
```

The cable puzzle opens as a separate `CanvasLayer`. While it is open, HUD focus and mouse input are recursively disabled and later restored to their previous values.

## State-Change Flow

```text
Player intent
    -> Controller or presenter command
    -> System validation and planning
    -> One atomic state write
    -> New presentation model
    -> UI refresh
```

Normal rejections do not silently select another action. Advice can recommend a choice, but only an explicit player action changes the game.

## Determinism

The same initial data and action sequence produce the same outcome. Ordering rules are explicit for time occurrences, task completions, and ending resolution.

Integration tests replay complete technical scenarios multiple times and compare normalized final snapshots.

## Testing Strategy

The custom headless runner discovers `test_*.gd` files and reports each test independently. The test suite includes:

- unit tests for data and systems;
- smoke tests for scene loading and lifecycle behavior;
- accessibility and focus-navigation tests;
- atomic-write and failure-path tests;
- deterministic full-game integration scenarios.

The latest verified local run contains 820 passing tests. Deliberately triggered engine errors in negative tests are captured and asserted by the test framework rather than ignored.

## Current Boundary

The core systems and presentation foundation are implemented. A production session/bootstrap layer is still required to load neutral production data, construct systems in dependency order, initialize trust, create the presenter, and connect HUD intent signals.

This limitation is stated explicitly so the portfolio snapshot does not present unfinished behavior as complete.
