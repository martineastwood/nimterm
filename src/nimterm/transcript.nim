## Retained, agent-agnostic transcript state.

import std/json
import ./events

type
  TranscriptItemKind* = enum
    tikUser
    tikAssistant
    tikThinking
    tikTool
    tikError
    tikStatus

  TranscriptItem* = object
    kind*: TranscriptItemKind
    id*: string
    title*: string
    text*: string
    pending*: bool
    isError*: bool
    approvalRequired*: bool
    expanded*: bool
    toolInput*: JsonNode
    durationMs*: int
    step*: int
    model*: string
    approve*: proc (allowed: bool) {.closure.}
    rememberSession*: proc () {.closure.}
    rememberProject*: proc () {.closure.}

  Transcript* = object
    items*: seq[TranscriptItem]
    activeRunId*: string
    activeStep*: int
    activeAssistantId*: string
    activeThinkingId*: string

proc newTranscript*(): Transcript =
  Transcript(activeStep: -1)

proc appendUser*(transcript: var Transcript, text: string, id = "") =
  transcript.items.add TranscriptItem(kind: tikUser, id: id, text: text)

proc itemIndex(transcript: Transcript, id: string): int =
  for i, item in transcript.items:
    if item.id == id:
      return i
  -1

proc apply*(transcript: var Transcript, event: AgentUiEvent) =
  case event.kind
  of ueRunStarted:
    transcript.activeRunId = event.runId
    transcript.activeStep = -1
    transcript.activeAssistantId = ""
    transcript.activeThinkingId = ""
    if event.prompt.len > 0:
      transcript.appendUser(event.prompt, event.runId & ":user")
  of ueStepStarted:
    transcript.activeStep = event.step
    transcript.activeAssistantId = ""
    transcript.activeThinkingId = ""
  of ueTextDelta:
    if event.text.len == 0: return
    if transcript.activeAssistantId.len == 0:
      transcript.activeAssistantId = event.runId & ":" & $event.step & ":assistant"
      transcript.items.add TranscriptItem(kind: tikAssistant,
        id: transcript.activeAssistantId, step: event.step, model: event.model)
    let index = transcript.itemIndex(transcript.activeAssistantId)
    if index >= 0:
      transcript.items[index].text.add event.text
      transcript.items[index].pending = true
      if event.model.len > 0:
        transcript.items[index].model = event.model
  of ueThinkingDelta:
    if event.text.len == 0: return
    if transcript.activeThinkingId.len == 0:
      transcript.activeThinkingId = event.runId & ":" & $event.step & ":thinking"
      transcript.items.add TranscriptItem(kind: tikThinking,
        id: transcript.activeThinkingId, step: event.step, pending: true)
    let index = transcript.itemIndex(transcript.activeThinkingId)
    if index >= 0:
      transcript.items[index].text.add event.text
      transcript.items[index].pending = true
  of ueToolCalled:
    transcript.items.add TranscriptItem(kind: tikTool, id: event.toolId,
      title: event.toolName, toolInput: event.toolInput, pending: true,
      step: event.step)
  of ueApprovalRequired:
    let index = transcript.itemIndex(event.toolId)
    if index >= 0:
      transcript.items[index].approvalRequired = true
      if event.text.len > 0:
        transcript.items[index].text = event.text
      transcript.items[index].approve = event.approve
      transcript.items[index].rememberSession = event.rememberSession
      transcript.items[index].rememberProject = event.rememberProject
    else:
      transcript.items.add TranscriptItem(kind: tikTool, id: event.toolId,
        title: event.toolName, text: event.text, toolInput: event.toolInput,
        pending: true, approvalRequired: true, step: event.step,
        approve: event.approve, rememberSession: event.rememberSession,
        rememberProject: event.rememberProject)
  of ueToolResult:
    let index = transcript.itemIndex(event.toolId)
    if index >= 0:
      transcript.items[index].pending = false
      transcript.items[index].isError = event.isError
      transcript.items[index].text = event.toolOutput
      transcript.items[index].durationMs = event.durationMs
      transcript.items[index].approvalRequired = false
      transcript.items[index].approve = nil
      transcript.items[index].rememberSession = nil
      transcript.items[index].rememberProject = nil
    else:
      transcript.items.add TranscriptItem(kind: tikTool, id: event.toolId,
        title: event.toolName, text: event.toolOutput, pending: false,
        isError: event.isError, durationMs: event.durationMs, step: event.step)
  of ueStepFinished:
    let thinking = transcript.itemIndex(transcript.activeThinkingId)
    if thinking >= 0:
      transcript.items[thinking].pending = false
    let assistant = transcript.itemIndex(transcript.activeAssistantId)
    if assistant >= 0:
      transcript.items[assistant].pending = false
  of ueRunFinished:
    let thinking = transcript.itemIndex(transcript.activeThinkingId)
    if thinking >= 0:
      transcript.items[thinking].pending = false
    let assistant = transcript.itemIndex(transcript.activeAssistantId)
    if assistant >= 0:
      transcript.items[assistant].pending = false
    transcript.activeAssistantId = ""
    transcript.activeThinkingId = ""
  of ueError:
    let thinking = transcript.itemIndex(transcript.activeThinkingId)
    if thinking >= 0: transcript.items[thinking].pending = false
    let assistant = transcript.itemIndex(transcript.activeAssistantId)
    if assistant >= 0: transcript.items[assistant].pending = false
    transcript.items.add TranscriptItem(kind: tikError, id: event.runId & ":error:" &
      $transcript.items.len, text: event.error, isError: true)
    transcript.activeAssistantId = ""
    transcript.activeThinkingId = ""
