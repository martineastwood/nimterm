## Generic UI events, aligned with nimgent's normalized lifecycle semantics.

import std/json
import ./keys

type
  UiAction* = object
    sourceId*: string
    targetId*: string
    kind*: string
    value*: string
    index*: int
    cancelled*: bool

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

  UiMouseButton* = enum
    umbNone
    umbLeft
    umbMiddle
    umbRight

  AgentUiEventKind* = enum
    ueRunStarted
    ueStepStarted
    ueTextDelta
    ueThinkingDelta
    ueToolCalled
    ueApprovalRequired
    ueToolOutputDelta
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
    uiFocus
    uiError
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
    button*: UiMouseButton
    shift*: bool
    alt*: bool
    ctrl*: bool
    scrollDelta*: int
    focused*: bool
    sourceId*: string
    error*: string
    cancelled*: bool
    width*: int
    height*: int
    timerId*: string
    agent*: AgentUiEvent

proc agentEvent*(event: AgentUiEvent): UiEvent =
  UiEvent(kind: uiAgent, agent: event)

proc quitEvent*(): UiEvent = UiEvent(kind: uiQuit)
