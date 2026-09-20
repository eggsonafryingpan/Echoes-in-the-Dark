# Echoes in the Dark — Implementation Brief for Claude Code

> **How to use this file:** Drop it in the repo root. Read it fully before writing code. The **published camera-ready paper is ground truth** (see §0.1) — where anything conflicts with it, the paper wins. Implement in the numbered **phases** (§12), stopping for review after each. Commit per system. Decisions marked **[OPEN]** — implement the stated default but keep configurable.

---

## 0. Context — what this is and why it matters

An **audio-only** (no visuals) cave-exploration game for **blind and low-vision (BLV)** players, built in **Godot 4** with **godot-steam-audio**, using an **EmotiBit** worn on a headband for head-tracking and heart rate.

**This is a real research project accepted to the ACM UIST 2026 Student Innovation Contest** (peer-reviewed; in-person demo in Detroit, Nov 2–5 2026; DOI 10.1145/3830397.3841317). The "research-integrity" notes throughout this brief — the conjunctive overload detector, not claiming to measure cognitive load, unconditional progression, adopting directional scanning rather than claiming it as novel — are **defensible claims in a published paper. Treat them as firm requirements, not preferences.**

The deliverable driving this work is an **8-minute in-person demo** (and a demo video). **Success metric:** the judge must leave feeling they *accomplished something inside the game* — that they solved the mystery — not that they sat through sound effects. Every system serves that.

### 0.1 Ground truth from the paper (do not contradict)
- **Three contributions:** (1) **head orientation as the listening reference frame** — orientation and translation are independent inputs, so surveying is separate from moving and needs no joystick; (2) a **three-layer audio priority architecture** (priority / essential / environmental) whose layers are removed and restored by detected state; (3) a **conjunctive overload detector** requiring elevated heart rate **and** independent behavioral evidence of struggle, so adaptation never rests on a physiological signal alone.
- **Design philosophy:** where existing assistance answers difficulty by *supplying more information*, this system answers it by *removing competing information*, and **never routes the player**. Directional scanning is adopted from prior work, **not claimed as novel**.
- **Awareness split (from Kuikkaniemi et al.):** the player must be *told* about signals they have to act on, so the **breathing/CALM mechanic is taught in dialogue**; **layer adaptation stays unannounced**, because its job is to passively reduce load, not to be noticed.
- **Indirect signals (Nacke et al.):** heart rate is an indirect signal, so it should **alter the environment, not the player's abilities** — which is exactly the audio-complexity adaptation.
- The detector **identifies a state, not a quantity.** It does **not** claim to measure cognitive load (real-time inference from consumer wearables isn't established; arousal is hard to separate from cognitive demand). Cite this framing in comments.

---

## 1. Hard constraints & principles

- **Diegetic teaching only.** No tutorial text, no "press left to move left." Mechanics are taught through the fiction. Core contribution — do not violate.
- **Unconditional progression.** No mechanic may hard-lock the player out. Biosignal mechanics make success *feel earned*; time + escalating assistance guarantee the event *always resolves* (§7, §8). The paper commits to this ("a time-based fallback so nobody is blocked").
- **Remove, don't add; never route.** Difficulty is answered by stripping competing audio, never by adding narration or forcing a path.
- **The player discovers; the game does not explain.** Bat and player dialogue may *react*, never state conclusions.
- **Teach CALM aloud; keep layer adaptation silent.** (Kuikkaniemi split, above.)
- **Mock-first development.** All sensor-driven systems must run from recorded/synthetic data with no EmotiBit connected (§3.5). Hardware tuning is a later human task.
- **No visuals in the shipped build**, but the 3D scene stays intact under a black overlay (reused for the observer replay, §11).

---

## 2. System architecture (two processes)

Per the paper, signal processing lives in **Python**, not Godot.

**Process A — Python sensor bridge**
- EmotiBit streams over **OSC**. `python-osc` ingests it.
- **Orientation:** 9-axis IMU → **Madgwick filter** (`ahrs` library) → quaternion/euler.
- **Heart rate:** **green-channel PPG** (not the onboard estimate) → bandpass filter → **HeartPy** over a sliding window → BPM.
- **EDA** is logged but **not** used by the detector.
- **Motion-gate** applied here (or exposed so Godot can): mark HR samples valid only when angular velocity is low.
- Forwards orientation + HR (+ validity flag) to Godot via **GodOSC**.

**Process B — Godot game.** Receives processed orientation + HR over OSC and runs everything below as **autoload singletons**:
1. **`SensorBridge`** — OSC receiver; exposes clean signals; owns baseline.
2. **`GameState`** — derived state everyone reads: orientation, `is_still`/HR-valid, HR trend, elevated flag, collision & disorientation counters.
3. **`AudioDirector`** — owns the three layers + the steam-audio listener; the only thing that changes SFX complexity.
4. **`OverloadDetector`** — conjunctive detector → tells `AudioDirector` to strip/restore.
5. **`BatCompanion`** — scan + dialogue, as a virtual spatial source.
6. **`EventDirector`** — sequences the three events; owns per-event pass logic + anti-lockout timers.

---

## 3. Sensor layer

### 3.1 Metrics used and why (forehead mount, constant head motion, live)
- **IMU (9-axis)** — primary, always live; Madgwick → orientation. Drives FOCUS, navigation, motion-gate.
- **HR (green PPG → HeartPy)** — trusted **only when the head is still** (PPG is wrecked by motion). Fine, because HR is only needed during CALM, when the player deliberately holds still.
- **Respiration** — not required; CALM keys off HR trend + breathing behavior, not a derived respiration channel.
- **EDA** — logged, **not used** by the detector (paper).
- **Temperature** — unused.

### 3.2 Motion-gate
`is_still = angular_velocity < STILL_THRESHOLD`; HR sampled/trusted only then. Paper: "angular velocity gates heart rate readings, and state transitions are evaluated only on settled data."

### 3.3 Baseline
~30 s quiet stillness at session start (folded into the spoken intro) → resting HR reference. All downstream logic reads **relative to baseline** ("elevated" = meaningfully above resting), never absolute BPM, so it generalizes across demoers. Skip HRV baseline.

### 3.4 CALM reference (separate from global baseline)
CALM uses a **start-of-event** reference (the player's elevated rate when the event begins) and detects a **relative drop from their own starting rate**, with a time-based fallback (§8). The global baseline is for the detector's elevated-vs-resting test.

### 3.5 Mock / replay mode (required)
`SensorSource` interface with `LiveOSCSource` and `MockSource`. `MockSource` replays recorded/scripted OSC traces ("startled then calming," "elevated + colliding"). Build and test everything on `MockSource` first.

---

## 4. Audio architecture (`AudioDirector`) — paper taxonomy

Three layers, by how directly a source bears on the current objective:
- **Priority** — the 1–2 sources representing the objective (e.g. a call leading toward the current goal). **Never stripped.**
- **Essential** — story and progression cues that inform the route without defining it. Stripped **second**.
- **Environmental** — ambience and spatial texture (water on cave walls, wind, flavor). Stripped **first**.

> **Correction from earlier drafts:** an earlier note called these "essential / environmental / elective." The paper's names are **priority / essential / environmental**; the old "elective/fun" SFX belong inside **environmental** (stripped first). Use the paper's taxonomy everywhere.

On overload: remove **environmental first, essential second, leaving priority isolated**. Restore as behavioral indicators improve. Implement as Godot buses with independent gain; strip = smooth fade to silence, not a cut. Players can also set layer volumes from the main menu. All spatial sources route through godot-steam-audio with the listener driven by head orientation.

---

## 5. Passive overload detector (`OverloadDetector`)

Runs continuously. **Both** conditions must hold before intervening (paper §2.4):
- **HR elevated** above the session baseline (motion-gated reads only), **AND**
- **behavioral evidence of struggle:** repeated **wall collisions** + **no reduction in distance to the objective** + **few object interactions** within a rolling window.

Never fires on HR alone; **identifies a state, not a quantity**; does **not** claim to measure cognitive load (keep in comments). Wall proximity/collisions come from the navigation raycast (§6.1).

**Output → complexity:** overload → strip environmental, then essential (leave priority); recovered → re-bloom. Adaptation is **unannounced**.

**Arbitration:** CALM events *expect* elevated HR — during an active CALM sequence, **suppress the overload→audio adaptation** (`EventDirector` sets a flag the detector respects) so ambience isn't stripped exactly when CALM needs it.

---

## 6. Mechanics

### 6.1 Navigation (largely built — verify/finish)
Joystick = translation; head orientation (IMU) sets facing **and** the audio-listener orientation, independent of translation (look left + push forward = walk left; look up/down doesn't change translation). **Wall proximity by raycast** drives a proximity cue and supplies the collision counts the detector uses. Keep intact under the black overlay.

### 6.2 Controller
Joystick (move), **scan button** (§9), interact **[OPEN — stub]**, pause/menu. **Heartbeat haptic:** during CALM, render the player's smoothed live HR as a **bilateral, synchronized** pulse in **both motors** (deliberately non-directional, so it reads as physiological state, not a spatial cue).

### 6.3 FOCUS
Sustained head orientation toward a source raises that cue's volume and builds a "focus" layer until it becomes **recognizable** — FOCUS is what supplies **identity** (the scan gives only bearing, §9). Paper example: the scan finds a cluster ahead; FOCUS turns "indistinct buzzing" into "recognizable mosquitoes." Prompted diegetically by the bat. FOCUS is "the voluntary counterpart to automatic layer removal."
**Anti-lockout:** build threshold decays over time so the reveal always fires (§7).

### 6.4 CALM
See §8.

---

## 7. Anti-lockout — FOCUS (shared pattern)
1. On-target dwell accrues focus → threshold fires reveal.
2. **Auto-relax:** required dwell/precision loosens over time.
3. **Timeout fail-forward (~20–25 s):** fire the reveal anyway; bat closes the fiction ("there — you hear it now?"). Player never learns a threshold existed.

---

## 8. Anti-lockout — CALM (never a hard gate)
CALM is an experiential beat, not a skill check. HR accuracy is irrelevant — we only need a **noticeable downward trend**, and even that isn't required to progress (paper: relative drop with a time-based fallback). Escalation ladder:
1. **Start-of-event reference**; detect a downward slope from it (heavy multi-second smoothing; motion-gated windows only).
2. **Generous threshold** — a small sustained drop passes.
3. **Auto-relax** — required drop shrinks over time.
4. **OR conditions** — HR down **or** breathing slowing **or** dwell time.
5. **Escalating in-fiction help** — bat's own breathing louder/slower → gentle guided count ("in… and out…"); the guide usually produces the calming we measure.
6. **Fail-forward timeout (~25–30 s):** passage opens regardless; "…there. You're okay now." **No lockout possible.**

Controller pulse mirrors the smoothed live signal throughout, so success feels genuinely theirs and assistance stays invisible. **Do not have the bat say "hold still"** — the calming fiction produces the stillness for free; gate on it silently.

---

## 9. Bat companion — role, scan, dialogue (`BatCompanion`)

### 9.1 Role & the headphones problem [OPEN — default, keep configurable]
The paper describes a **companion bat on the shoulder** performing scans **and closed-back headphones** — but closed-back headphones acoustically block a physical shoulder speaker, and two audio paths create sync/latency problems.
**Default resolution:** the bat's audio is a **virtual spatial source rendered into the headphones**, anchored to a fixed **shoulder position** via head-tracking (stays at the shoulder as the head turns; distinct timbre). The **3D-printed shell is a tactile/aesthetic prop + magnetic mount only** — no audio output. Fiction = "a bat on my shoulder"; implementation = one clean audio path. (EmotiBit is on the headband, not the bat.) Robot-vs-real-bat stays **[OPEN]**; dialogue works either way.

### 9.2 Echolocation scan — scope (rework the current label-reading)
Per the paper, the scan **returns the bearing of nearby sources without identifying them.** So:
- **On scan-button press:** active sonar sweep SFX, then render nearby sources as **spatialized directional returns** — the *direction* is conveyed by where the return sits in 3D space, nearer/louder = closer. **No identification, no coordinate readouts.**
- **Identity is earned via FOCUS**, not the scan. Replace "there's something small at seven o'clock" entirely — the scan says *where*, FOCUS reveals *what*.
- **Limits:** range-limited to proximate sources, short **cooldown (~2–3 s)**, returns story-relevant/interactable sources + immediate obstacles. Walls are felt via returns + proximity cue, not spoken.
- The current object-label data can drive **which** sources return and their FOCUS-revealed identity — just never spoken as coordinates.
- Reserve **verbal** bat lines for mandatory story beats, FOCUS prompts, and CALM coaching — short, characterful, never a menu.

### 9.3 Dialogue system
Data-driven (lines as resources/JSON: id, audio file, trigger, mandatory/cutscene flag). `EventDirector` fires by id. TTS placeholders now; human VO later.

### 9.4 Player self-dialogue [OPEN — recommended: sparing]
First-person reactions ("…that's not right," "I should note this") reinforce the researcher framing and voice the accomplishment beat. **Rule: react, never explain.** Use only at real discovery moments (the swarm; the music). Toggleable.

---

## 10. The three-event demo arc (`EventDirector`)

~6 playable minutes; rest is intro + resets. Each event teaches a primitive the next reuses. **End on a resolution the player caused, not on a mechanic.**

**Event 1 — CALM (~2.5 min) — "my body is an input":** cold open falling whoosh + loud rock-tumble; scripted fast **bilateral** controller pulse; panicked breathing. Bat names the input (seeds, doesn't instruct): *"Woah — your heart's pounding, I can feel it. Slow it down with me."* CALM loop per §8; passage ambience opens on success.

**Event 2 — FOCUS (~2.5 min) — "louder = right, holding reveals":** bat gives **bearing** from a scan (*"something ahead — turn toward it and hold still"*); FOCUS resolves *identity* (§6.3/§7). Reveal: many calm creatures, predators and prey together, unnaturally still. Bat: *"…they're all just sitting there. That's not right."* Optional player line.

**Event 3 — REVEAL (~2 min) — apply both, free navigation:** the **music** (a **priority**-layer source, distinct timbre) becomes faintly audible. Player combines joystick + head orientation to walk toward it through a short passage with **one gentle bend** (same "louder = right" gradient, now on their feet). Footsteps + wall-thuds shape the space; bat nudges once max. Arrive → music full → cause resolves. **Attribution beat:** *"You found it — that's what's keeping them all calm."* The "I solved it" moment.

### 10.1 Map — demo scope vs the paper's procgen
The paper describes a **procedurally generated cave**; the general system stays procgen, but the **demo build pins it** to a short, near-linear layout via a **fixed seed or constrained generation params** (or a hand-authored demo scene): landing (E1) → short passage → swarm chamber (E2) → short passage with **one bend** → music chamber (E3). Only E3 has real traversal (~20–40 s). No branches, no dead ends; walls are soft guides. Rationale: instant reset between demoers, no wanderers blowing the 8-min window, and no first-timer frustration (the opposite of "accomplished").

---

## 11. Reviewer-driven demo features (Reviewer 1, 5/5)

Two features that directly answer Reviewer 1 and reinforce the "judge feels they did something" goal:

- **A/B adaptive toggle.** Let the judge experience the **non-adaptive** version (no layer stripping) alongside the adaptive one, so they *feel* how overwhelming the audio gets without adaptation and appreciate the benefit. Implement as a runtime switch in `AudioDirector` (adaptation on/off) exposed via a demo-operator hotkey. The reviewer explicitly requested this.
- **Sighted-observer replay / visualization.** Because the game is a real 3D Godot scene under a black overlay, **drop the overlay at the end** and show the audience the backend: the player's **trajectory**, live **active-layer state**, **HR**, and **overload triggers**, ideally replaying what the judge just did and how the system responded. This lets sighted attendees understand the interaction they (or the judge) experienced. Build a lightweight observer HUD over the existing 3D view.

**Stealth section — deferred (do not build for the demo).** The proposal's blind-cave-predator/heart-rate-stealth mechanic was flagged by the reviewer as optional and the design has **cut the predator mechanic**. The adaptive audio layers are the standalone experience. Only revisit if everything else is robustly done and tuned.

### 11.1 For the final write-up (not code, but design it so this is answerable)
Reviewer 1 wants the paper to specify **what counts as low- vs high-complexity audio** and **how those levels are determined/designed**. Keep the layer definitions and strip thresholds explicit and documented in code/config so this maps cleanly into the writeup.

---

## 12. SFX asset pipeline (Task 2)

Organized pipeline; wire placeholders first (final assets are a human sourcing/licensing task — prefer CC0). Provide an **asset manifest** (path, **layer** using paper names, event, license) and one-step placeholder→final swap.

- **Priority:** the objective sources per event — e.g. the goal **music motif** (distinct, recognizable timbre); the swarm cue once it's the objective.
- **Essential:** footsteps (rock, gravel, mud, shallow water), wall-collision thud, heartbeat (calm→elevated tempos, for the audible-heartbeat CALM cue), breathing (calm vs panicked), echolocation sweep + directional returns, bat voice lines, UI confirm/back.
- **Environmental:** water drips, distant flow/river, wind through passages, rock settling/creaks, low reverb bed, opening rockslide (E1), plus sparse flavor ambience — **all first to be stripped**.
- **Animals (calm swarm):** bat chittering/wingbeats, small-prey rustling, larger-creature breathing/footsteps — **all calm/non-threatening variants; nothing aggressive or jump-scare-y** (the reveal only works if animals read as peaceful; no predator mechanic).

---

## 13. Build order (stop for review after each phase)

- **Phase 0** — Repo/project audit; add this file; scaffold the six autoloads; set up the three audio buses.
- **Phase 1** — **Python sensor bridge** (OSC in, Madgwick, green-PPG+HeartPy, motion-gate, GodOSC out) **+** Godot `SensorBridge` + baseline; `MockSource`. Test on mock traces, no hardware.
- **Phase 2** — `AudioDirector`: priority/essential/environmental buses, steam-audio listener from head orientation, bat as spatial source, per-layer menu volumes.
- **Phase 3** — `OverloadDetector` (conjunctive) → strip environmental→essential; CALM arbitration flag; **A/B adaptive toggle**.
- **Phase 4** — FOCUS + anti-lockout (§6.3/§7).
- **Phase 5** — CALM + anti-lockout ladder + bilateral haptic pulse (§8).
- **Phase 6** — Echolocation scan rework: bearing-only returns, cooldown, FOCUS-for-identity (§9.2).
- **Phase 7** — Dialogue system + `EventDirector` sequencing the three events (§10).
- **Phase 8** — SFX pipeline + manifest + wiring (§12).
- **Phase 9** — Black-overlay demo build, instant reset/respawn, timing pass, **sighted-observer replay/HUD** (§11).

---

## 14. Acceptance criteria
- Full playthrough runs end-to-end on `MockSource`, no hardware.
- HR never trusted during head motion; state transitions on settled data only.
- Detector never fires on HR alone; strips environmental→essential; never strips during CALM.
- No mechanic can lock the player out (each anti-lockout timeout verified).
- No visuals in the shipped build; audio conveys all state; observer HUD reveals backend on demand.
- A/B toggle audibly changes the experience.
- A 3-event playthrough completes in ~6 min and ends on the attribution beat.

## 15. Open decisions (surface, don't silently pick)
- Robot bat vs real cave bat (VO tone only).
- Interact button: include or cut.
- Player self-dialogue amount (default sparing; react-not-explain).
- Bat shell: houses haptics or purely aesthetic.
- Demo map: fixed-seed procgen vs hand-authored scene.

---

## Appendix A — Reviewer 1 (score 5/5, "definite accept," expert)

Congratulations on acceptance. The team clearly identified persistent challenges around cognitive overload during nonvisual interface navigation for BLV users and proposes a neat EmotiBit integration to address it. Suggestions for the demo and final writeup:

- **Adaptive audio layers.** In the final writeup, specify what counts as low- vs high-complexity audio and how those levels are determined/designed. For the demo, let attendees experience **both the adaptive and non-adaptive versions** for direct comparison, so they can observe firsthand how overwhelming the audio gets without adaptation and appreciate the benefit.
- **Game used in the demo.** They agree with using a game without visual elements. Since such a game is being used, adding a **visualization of the trajectories/game elements for sighted attendees** at the end could showcase the backend — replaying the underlying mechanics and how the system responds to user action.
- **Stealth section.** Curious whether participants would be told about the heart-rate-driven predator detection mechanic or expected to discover it; without some introduction it may be hard to understand. They believe the **adaptive audio layers already stand alone**, and recommend treating stealth as a **potential second part only if time remains** after the adaptive audio is implemented — noting significant effort is already required to robustly detect overload, design scenarios eliciting different load levels, and tune the layers into a meaningful experience.

*Human-owned, out of scope for Claude Code: sourcing/licensing final audio, EmotiBit hardware-in-the-loop testing on real bodies, and threshold tuning from real playtests.*
