## Generic UI events, aligned with nimgent's normalized lifecycle semantics.

import std/json
import ./keys

type
  ApprovalChoice* = object
    id*: string
    key*: string
    label*: string

  UiMouseKind* = enum
    umNone
    umPress
    umRelease
    umDrag
    umScroll

  AgentUiEventKind* = enum
    ueRunStarted
    ueStepStarted
    ueTextDelta
    ueThinkingDelta
    ueToolCalled
    ueApprovalRequired
    ueToolResult
    ueStepFinished
    ueRunFinished
    ueError

  AgentUiEvent* = object
    kind*: AgentUiEventKind
    runId*: string
    sessionId*: string
    turnId*: string
    step*: int
    prompt*: string
    model*: string
    text*: string
    toolId*: string
    toolName*: string
    toolInput*: JsonNode
    toolOutput*: string
    isError*: bool
    durationMs*: int
    error*: string
    approvalChoices*: seq[ApprovalChoice]
    cancelChoiceId*: string

  UiEventKind* = enum
    uiNone
    uiKey
    uiMouse
    uiResize
    uiTimer
    uiAgent
    uiQuit

  UiEvent* = object
    kind*: UiEventKind
    key*: Key
    text*: string
    x*: int
    y*: int
    mouse*: UiMouseKind
    scrollDelta*: int
    width*: int
    height*: int
    timerId*: string
    agent*: AgentUiEvent

proc agentEvent*(event: AgentUiEvent): UiEvent =
  UiEvent(kind: uiAgent, agent: event)

proc quitEvent*(): UiEvent = UiEvent(kind: uiQuit)
