---
name: notebooklm-new
description: Create a new NotebookLM notebook and register it in the library — all in one step. Use this skill whenever the user wants to create a notebook, start a new notebook, set up a notebook for a project or topic, or says anything like "make me a notebook for X", "create a notebook about X", "I need a notebook for X", "start a new notebook", "set up a notebook". Always use this skill rather than trying to create notebooks manually.
---

# NotebookLM New Notebook Skill

Your job is to create a new NotebookLM notebook and immediately register it in the library so it's ready to use — one command, zero manual steps.

## Steps

### 1. Gather what you need

You need three things before calling `create_notebook`:
- **Name** — short, clear (e.g. "Legal Case", "Marketing Research")
- **Description** — 1–2 sentences on what this notebook is for
- **Topics** — 3–5 keywords that describe what goes in it

If the user's message makes these obvious, derive them directly — don't ask. If the topic is clear but the name isn't obvious, pick a sensible one. Only ask if something critical is genuinely missing.

### 2. Call create_notebook

```
create_notebook(
  name: "...",
  description: "...",
  topics: ["...", "...", "..."],
  content_types: [...],   // optional: "research", "legal", "documentation", etc.
  use_cases: [...]        // optional: when Claude should reach for this notebook
)
```

The tool creates the notebook on NotebookLM via browser automation and registers it locally in one step. It returns the notebook object with its `id`.

### 3. Confirm and invite next action

Tell the user the notebook is ready, then offer the natural next step:

> Created **[Notebook Name]** — ready to use.
>
> Want me to research and add sources now, or ask it a question?

Keep it short. The notebook is empty so asking it questions won't return much yet — gently nudge toward research if the context suggests it.

## What not to do

- Don't open a browser or navigate manually — `create_notebook` handles everything
- Don't ask for the URL — the tool creates the notebook and captures the URL automatically
- Don't ask unnecessary questions — infer name/description/topics from context when possible
