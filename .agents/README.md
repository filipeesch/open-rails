# .agents/ — the Agent Knowledge Base

Three kinds of document, each answering a different question. Keep them
different when you write:

| Kind | Question | One file is… | Location |
|---|---|---|---|
| **Reference** | *What is true?* | shared facts with concrete values (numbers, names, formats) — no procedures | `.agents/references/<topic>.md` |
| **Skill** | *What must I know to work on this area?* | reusable project knowledge for one area: invariants, interfaces, rules — **not** a step list | `.agents/skills/<name>/SKILL.md` |
| **Workflow** | *In what order do I do this?* | an ordered procedure that **composes skills** and ends in real `rr.py` verification | `.agents/workflows/<name>.md` |

`AGENTS.md` (repo root) is the entry point and index; the skill set it
indexes is fixed by spec §78 — 35 skills, no more unless the spec changes.
(`.agents/skills/openspec-*` belong to OpenSpec tooling, not to this system;
don't edit them here.)

## Conventions

- **Skills** follow the mandated structure (spec §79) — exactly these `##`
  sections, in this order: Purpose, When to use, Non-goals, Dependencies,
  Invariants, Public interfaces, Implementation rules, Validation, Common
  mistakes, Related skills. Optional extras live in
  `scripts/ examples/ references/` beside the SKILL.md.
- **Write reusable knowledge, not feature notes.** A skill states the rule
  that outlives the ticket; the ticket's story belongs in `openspec/`.
- **Invariants must be checkable** — phrased so a test, `rr.py check` or a
  review can answer yes/no ("allocation Σ == produced quantity", not "cargo
  is correct").
- **Concrete values only.** Numbers live in references (or the canonical
  `art/config/world.toml` / `game/data/`); skills point at them and state
  the rule. No "TBD", no invented paths — if the thing doesn't exist yet,
  it's an openspec proposal first.
- **Where the spec is silent**, make the reasonable choice and mark it
  "**project decision**" so it can be found and revisited.
- **Workflows read first, then act**: list the skills to load, then ordered
  steps ending in the real verification commands
  (`python tools/rr.py art build/validate/preview`, `test`, `check`,
  `stress`).

## Adding a document

1. Pick the kind: fact → reference, rule-set → skill, procedure → workflow.
   If you're about to write a skill "for one feature", stop — extend the
   relevant system's skill instead (spec §79: no skill per feature).
2. Copy the shape: any existing file of the same kind is the template.
3. Cite sources: spec section numbers (`spec §37`), openspec design
   decisions, or the code/file that owns the value.
4. Cross-link both ways: update `Related skills`, and add the new entry to
   the index in `AGENTS.md` (skills index / workflows list).
5. Verify structure — for skills, all ten headings, in order:

   ```bash
   for h in "Purpose" "When to use" "Non-goals" "Dependencies" "Invariants" \
            "Public interfaces" "Implementation rules" "Validation" \
            "Common mistakes" "Related skills"; do
     grep -q "^## $h$" .agents/skills/<name>/SKILL.md || echo "missing: $h"
   done
   ```

6. Contradiction check: if your document changes a value, the owner changes
   in the same commit (world.toml + generated constants + reference file),
   and `python tools/rr.py check` still passes.

## What this directory is *not*

Not a changelog, not a design-rationale archive (that's
`openspec/changes/*/design.md`), not task tracking, and not a place for
instructions that override the spec — `docs/requirements/v1.md` stays
authoritative; when they disagree, the spec wins and this gets fixed.
