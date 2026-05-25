# kwwk Domain Glossary

This glossary defines product language for kwwk. It avoids implementation
details and is the vocabulary to use in issues, PRDs, tests, and design notes.

## Agent Harness

A surface that lets a person direct coding-agent work with local context,
runtime settings, history, and repeatable actions. In kwwk, the harness spans
the terminal agent and the native launcher.

Avoid: "AI wrapper" when the concept includes context, commands, workflows, and
runtime control.

## Launcher Command Surface

The native palette area where people search, filter, preview, and run
commands. It includes search, scopes, command results, previews, and secondary
actions.

Avoid: "launcher UI" when discussing the product boundary; use "launcher command
surface" for the searchable command/control experience.

## Command

A searchable unit of intent that can be selected and run. A command may open a
file, run an agent prompt, apply an AI profile, execute a script, start a
workflow, or reveal a local artifact.

Avoid: "action" for this concept. Actions are the secondary operations attached
to a command.

## Action

A secondary operation available for a selected command, such as copy, reveal,
open in terminal, save as workflow, or ask about this result.

Avoid: "command" for this concept unless the operation is itself searchable.

## Scope

A search filter that narrows the command surface to a command family such as
AI, CLI, apps, workspace, workflows, quicklinks, snippets, or models.

Avoid: "category" when describing the user-facing search control.

## Workspace Context

The local checkout, files, project tasks, and bounded file contents that can be
attached to agent work.

Avoid: "cwd" when the user-facing meaning is broader than the process working
directory.

## Terminal Context

Captured terminal output saved so the launcher and CLI can inspect, replay, or
ask an agent about it later.

Avoid: "log" when the captured content may be test output, command output, or
any piped text.

## Prompt Command

A reusable agent prompt template that can be searched, rendered with current
context, run headlessly, or opened as an editable terminal draft.

Avoid: "saved prompt" when the command is meant to be executed repeatedly.

## Workflow

A repeatable multi-step automation composed from agent prompts and shell work,
where later steps can use previous output.

Avoid: "script" when the sequence includes agent steps or previous-output
handoff.

## AI Profile

A named runtime preset for model, thinking level, and long-context behavior.

Avoid: "model preset" when the preset also controls reasoning or context mode.

## Deep Link

A `kwwk://launcher` handoff that opens the native launcher with search text,
selected command, selected action, context paths, working directory, and optional
run intent.

Avoid: "URL" alone when the product behavior is native app handoff.

## Resident Launcher

The always-available native app process that can show or hide the command
surface, keep menu-bar access alive, and remember context between invocations.

Avoid: "menu bar app" when the main behavior is a resident command surface with
a companion menu-bar extra.
