# Tomorrow's Dead

Tomorrow's Dead is a systems-driven narrative game prototype built with **Godot 4.7**. The project focuses on deterministic simulation, data-driven gameplay rules, accessible keyboard navigation, and a testable separation between game logic and presentation.

> **Status:** Work in progress. The core systems and HUD foundation are implemented; production session bootstrap and final narrative content are still under development.

## Highlights

- Deterministic game state and time progression
- Data-driven resources, trust, tasks, decisions, advice, occurrences, equipment, and endings
- Atomic state changes: an action either applies completely or not at all
- Directional trust and condition-based companion advice
- Accessible cable-repair mini-game with keyboard and mouse support
- Responsive HUD tested at 1280x720 and 1920x1080
- Headless automated test runner with **820 passing tests** in the latest verified local run
- Story-independent architecture that keeps narrative content outside system code

## Current Project State

The repository currently opens into a safe HUD shell. The main gameplay systems are implemented and verified through deterministic integration scenarios, including:

- two different reachable endings;
- a technical "no deaths" path;
- task assignment and completion effects;
- advice that informs but never overrides the player's choice;
- cable-puzzle success and failure outcomes;
- deterministic replay of the same action sequence.

The production data/session bootstrap that connects these systems to the playable HUD is the next development milestone.

## Architecture

The project is organized into distinct layers:

```text
Data resources
    -> Core state
    -> Gameplay systems
    -> Presentation model and presenter
    -> Godot UI scenes
```

Gameplay systems do not depend on the UI. UI views emit player-intent signals and do not write directly to game state. See [ARCHITECTURE.md](ARCHITECTURE.md) for a more detailed overview.

## Accessibility

- Full keyboard navigation for the HUD and cable puzzle
- Explicit focus order and visible focus styling
- Status information is not communicated by color alone
- Scrollable container-based layout instead of fixed screen coordinates
- Minimum logical text size of 30 px
- Minimum logical action-button height of 72 px
- Modal mini-game focus and mouse isolation with safe focus restoration

## Automated Tests

The project includes unit, smoke, and integration tests. The latest verified local result is:

```text
Total: 820 | Passed: 820 | Failed: 0
Exit code: 0
```

Run the suite with the Godot console executable:

```powershell
& "<GODOT_CONSOLE_EXE>" --headless --path . --import
& "<GODOT_CONSOLE_EXE>" --headless --path . --script res://tests/run_tests.gd
```

The import step builds Godot's local UID cache for a fresh clone. Replace
`<GODOT_CONSOLE_EXE>` with the path to your local Godot 4.7 console executable.

## Running the Project

1. Install Godot 4.7 or a compatible Godot 4.x version.
2. Clone or download this repository.
3. Import `project.godot` in the Godot Project Manager.
4. Run the project.

At the current milestone, the main scene displays the accessible HUD in its safe no-session state. The production bootstrap is intentionally not represented as complete.

## Repository Scope

This public snapshot contains the technical implementation, automated tests, and neutral placeholder identifiers used to validate the architecture. Private narrative planning, design decisions, licensed media, and internal development instructions are intentionally excluded.

## Roadmap

- [x] Deterministic core state and gameplay systems
- [x] Automated unit, smoke, and end-to-end system tests
- [x] Accessible HUD foundation
- [x] Accessible cable-repair mini-game
- [ ] Production session and data bootstrap
- [ ] Playable vertical slice
- [ ] Final narrative content, art, audio, and balancing

## Rights

Source code is publicly available for portfolio review. **All rights reserved.** No open-source license is granted by this repository.
