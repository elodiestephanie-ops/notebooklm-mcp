---
name: notebooklm-research
description: Research a topic and add the best sources directly to a NotebookLM notebook, then return a concise summary. Always use this skill when the user wants to research something, gather sources, investigate a topic, find articles, populate a notebook, or keep a notebook up to date — even if they don't use the word "research". Triggers include "research X", "find sources on X", "look into X", "add articles about X to my notebook", "gather info on X", "update my notebook with X", "investigate X", "what's new on X", "I'm working on X can you find me some reading". Also triggers when the user asks to expand, refresh, or deepen any notebook. Always use this skill rather than just answering the question — the goal is to build up a grounded knowledge base the user can query later, not give a one-off answer.
---

# NotebookLM Research Skill

Your job is to find high-quality sources on a topic and add them to the right NotebookLM notebook, then give the user a short summary of what you found. The notebook holds the knowledge — you're just the librarian.

## Why this matters
Every source you add becomes something the user can query at any time, for free, without using Claude tokens. The more you put in the notebook now, the less re-research you both have to do later. Be generous with sources.

## Steps

### 1. Identify the notebook
- Call `list_notebooks` to see what's registered
- Pick the best match for the topic — don't ask if it's obvious
- If nothing matches and the topic is substantial, offer to create a new notebook first using `create_notebook`, then proceed
- If it's genuinely ambiguous between two notebooks, ask one quick question and move on

### 2. Search for sources
- Use web search to find 5–8 high-quality sources on the topic
- Prioritise: authoritative sites (government, academic, established organisations), recent content (last 2 years unless historical context is needed), primary sources over aggregators
- Collect the full URLs — don't summarise yet, you haven't read them

### 3. Add everything in one batch
- Call `batch_add_sources` with all URLs at once — this is much faster than adding one at a time
- Use `type: "url"` for each source
- Give each a clear, descriptive title so the user can identify it in their notebook later

### 4. Return a useful summary
After the batch completes, report back with:
- How many sources were added and to which notebook
- 3–5 key themes or findings across the sources (based on what you found in your search, not a re-read)
- A prompt inviting them to ask their notebook follow-up questions

## What not to do
- Don't re-read or deeply summarise every source — that wastes tokens and the notebook does it better
- Don't ask for approval before searching — just go
- Don't add fewer than 4 sources unless the topic is very narrow

## Output format
Keep it tight:

> Added 7 sources to **[Notebook Name]** on [topic].
>
> Key themes:
> - [theme 1]
> - [theme 2]
> - [theme 3]
>
> Ask your notebook anything about this — or say "research more" if you want me to dig deeper.
