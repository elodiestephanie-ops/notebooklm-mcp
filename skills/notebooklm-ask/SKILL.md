---
name: notebooklm-ask
description: Query a NotebookLM notebook using ask_question — getting answers grounded in the notebook's sources (powered by Gemini 2.5). Use this skill whenever the user wants to ask their notebook something, query a notebook, get information from a notebook, look something up in a notebook, or says things like "ask my notebook about X", "what does my notebook say about X", "check the notebook for X", "query X", "what does the legal notebook say", "summarise what the notebook knows about X". Always prefer this over answering from Claude's own knowledge when a relevant notebook exists — the whole point is to use the grounded, source-backed answers.
---

# NotebookLM Ask Skill

Your job is to route the user's question to the right notebook and return the answer. NotebookLM answers are grounded in the user's actual sources — more accurate and trustworthy than Claude's general knowledge for anything the user has researched.

## Steps

### 1. Find the right notebook

- If the user names a notebook explicitly, use `search_notebooks` to find its id
- If the active notebook is obvious from context, use it (omit `notebook_id` — defaults to active)
- If it's ambiguous, call `list_notebooks` and pick the best match — announce your choice ("Checking the Legal notebook…") rather than asking

### 2. Ask the question

Call `ask_question` with:
- `question`: the user's question, rephrased if needed for clarity
- `notebook_id`: the notebook id (omit if using the active notebook)
- `session_id`: reuse the session id from any prior `ask_question` call to the same notebook — this keeps conversational context and makes follow-up answers sharper

NotebookLM returns an answer grounded in the notebook's sources, with inline citations.

### 3. Return the answer

Pass the answer through cleanly. Don't rewrite or summarise it — NotebookLM's answer is already well-formed and citation-backed.

If the answer is "I don't have sources on that" or thin, suggest adding more sources:
> The notebook doesn't have much on this yet. Want me to research and add sources?

### Session continuity

If the user asks follow-up questions in the same conversation, keep reusing the same `session_id`. This is important — NotebookLM uses session-based RAG so follow-ups are much more accurate when the session is maintained.

## What not to do

- Don't answer from Claude's own knowledge if a relevant notebook exists — always go to the notebook first
- Don't call `list_notebooks` on every message — use the active notebook when it's obvious from context
- Don't paraphrase or truncate the answer — return it as-is with citations intact
