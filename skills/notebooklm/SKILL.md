---
name: notebooklm
description: >
  Use this skill for any interaction involving Google NotebookLM — including
  querying notebooks, creating new ones, adding sources, or doing research
  that belongs in a notebook. Trigger on phrases like: "what does my [notebook]
  say about...", "add this to my notebook", "create a notebook for...",
  "research X and save it", "open the [project] notebook", "what have we
  stored on...", or any time the user mentions NotebookLM, a named notebook
  they work with (Held, legal case, CKC, etc.), or wants to preserve research.
  Also use when the user wants to chat with Gemini 2.5 grounded on their sources.
---

# NotebookLM Skill

You have access to the `notebooklm` MCP tools which connect to the user's
Google NotebookLM account via a local browser session. This lets you query
notebooks with Gemini 2.5, add sources, and create new notebooks — all
grounded in the user's actual saved materials.

## Core philosophy: intentional, not automatic

NotebookLM is a deliberate research tool, not a passive filing system.
**Never add sources or create notebooks without being asked to.** Research
and conversation happen in Claude first — the notebook gets involved only
when the user explicitly wants to preserve, query, or build on something.

Good triggers for notebook involvement:
- User says "add this to my notebook / save this / put this in [project]"
- User asks what a notebook contains or says about a topic
- User says "create a notebook for X"
- User wants Gemini's grounded perspective on their saved sources
- User is doing structured research they want to persist

Not a trigger (just help inline):
- General questions Claude can answer from its own knowledge
- Brainstorming, drafting, editing — unless the user pulls in notebook context

## Always start with get_health

Before any tool call, run `get_health` to confirm the server is running and
authenticated. If `authenticated: false`, tell the user to run
`start-remote.ps1` (for Claude.ai) or restart Claude Code (for desktop).

## Querying a notebook

1. `get_health` — confirm connected
2. `list_notebooks` — find the right notebook by name/topic
3. `select_notebook` with its `id`
4. `ask_question` with the user's question; save the returned `session_id`
5. For follow-ups in the same conversation, reuse that `session_id` — this
   keeps Gemini's context sharp across turns

Present the answer conversationally. Quote directly only when precision
matters. Always say which notebook you queried.

## Adding sources

Only do this when the user explicitly asks. Then:
1. Confirm which notebook they want to add to (`list_notebooks` if unsure)
2. `select_notebook` on that notebook
3. `add_source` — supported: URLs and text snippets
4. Tell the user what was added and confirm it's indexed (takes ~5–30s)

When suggesting sources to add (e.g. after research), present the list
and ask "Want me to add any of these to [notebook name]?" — don't add
without confirmation.

## Creating a notebook

When the user asks you to create one:
1. Clarify name, topic/purpose if not obvious from context
2. `add_notebook` with the NotebookLM share URL — **the user must create
   the notebook in NotebookLM first and share the URL with you**, because
   the MCP registers existing notebooks into the local library rather than
   creating them from scratch via the API
3. `update_notebook` to set description, topics, tags in the library

For brand-new notebooks: guide the user to notebooklm.google.com, create
it there, then share the URL. You can pre-draft the name/description for
them to paste in.

> Note: the `create_notebook` tool (if available) automates the browser
> creation flow. Use it if present; fall back to manual guidance if not.

## Audio Overviews

Only generate when explicitly requested. The flow is async:
1. `generate_audio` — starts render, returns immediately
2. Poll `get_audio_status` every 30s (takes 2–10 min)
3. When `status: "ready"`, offer to `download_audio`

## Each person has their own setup

This MCP is personal — it connects to whoever's Google account authenticated
during `setup_auth`. Other people (colleagues, friends) should install the MCP
from the same GitHub repo (`npx github:elodiestephanie-ops/notebooklm-mcp`)
on their own machine, then run `setup_auth` to log in with their own Google
account. They get their own notebooks, completely separate.

The Cloudflare Worker proxy is for the account owner's cross-device access
(Claude.ai on web/mobile) only — not shared with others.

## Error handling

- **503 / tunnel not running**: user needs to run `start-remote.ps1` on their PC
- **authenticated: false**: session expired; user needs to re-authenticate via `re_auth`
- **Session expired mid-conversation**: `reset_session` with same session_id, then re-ask
