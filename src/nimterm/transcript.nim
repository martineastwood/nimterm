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
    runId*: string
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
    approvalChoices*: seq[ApprovalChoice]
    cancelChoiceId*: string

  Transcript* = object
    items*: seq[TranscriptItem]
    activeRunId*: string
    activeStep*: int

proc newTranscript*(): Transcript =
  Transcript(activeStep: -1)

proc appendUser*(transcript: var Transcript, text: string, id = "") =
  transcript.items.add TranscriptItem(kind: tikUser, id: id, text: text)

proc itemIndex(transcript: Transcript, runId, id: string): int =
  for i, item in transcript.items:
    if item.id == id and (runId.len == 0 or item.runId == runId):
      return i
  -1

proc apply*(transcript: var Transcript, event: AgentUiEvent) =
  case event.kind
  of ueRunStarted:
    transcript.activeRunId = event.runId
    transcript.activeStep = -1
    if event.prompt.len > 0:
      transcript.appendUser(event.prompt, event.runId & ":user")
  of ueStepStarted:
    transcript.activeStep = event.step
  of ueTextDelta:
    if event.text.len == 0: return
    let id = event.runId & ":" & $event.step & ":assistant"
    var index = transcript.itemIndex(event.runId, id)
    if index < 0:
      transcript.items.add TranscriptItem(kind: tikAssistant,
        id: id, runId: event.runId, step: event.step, model: event.model)
      index = transcript.items.high
    if index >= 0:
      transcript.items[index].text.add event.text
      transcript.items[index].pending = true
      if event.model.len > 0:
        transcript.items[index].model = event.model
  of ueThinkingDelta:
    if event.text.len == 0: return
    let id = event.runId & ":" & $event.step & ":thinking"
    var index = transcript.itemIndex(event.runId, id)
    if index < 0:
      transcript.items.add TranscriptItem(kind: tikThinking,
        id: id, runId: event.runId, step: event.step, pending: true)
      index = transcript.items.high
    if index >= 0:
      transcript.items[index].text.add event.text
      transcript.items[index].pending = true
  of ueToolCalled:
    transcript.items.add TranscriptItem(kind: tikTool, id: event.toolId,
      runId: event.runId,
      title: event.toolName, toolInput: event.toolInput, pending: true,
      step: event.step)
  of ueApprovalRequired:
    let index = transcript.itemIndex(event.runId, event.toolId)
    if index >= 0:
      transcript.items[index].approvalRequired = true
      if event.text.len > 0:
        transcript.items[index].text = event.text
      transcript.items[index].approvalChoices = event.approvalChoices
      transcript.items[index].cancelChoiceId = event.cancelChoiceId
    else:
      transcript.items.add TranscriptItem(kind: tikTool, id: event.toolId,
        title: event.toolName, text: event.text, toolInput: event.toolInput,
        runId: event.runId, pending: true, approvalRequired: true, step: event.step,
        approvalChoices: event.approvalChoices,
        cancelChoiceId: event.cancelChoiceId)
  of ueToolResult:
    let index = transcript.itemIndex(event.runId, event.toolId)
    if index >= 0:
      transcript.items[index].pending = false
      transcript.items[index].isError = event.isError
      transcript.items[index].text = event.toolOutput
      transcript.items[index].durationMs = event.durationMs
      transcript.items[index].approvalRequired = false
      transcript.items[index].approvalChoices.setLen(0)
      transcript.items[index].cancelChoiceId = ""
    else:
      transcript.items.add TranscriptItem(kind: tikTool, id: event.toolId,
        runId: event.runId, title: event.toolName, text: event.toolOutput, pending: false,
        isError: event.isError, durationMs: event.durationMs, step: event.step)
  of ueStepFinished:
    let thinking = transcript.itemIndex(event.runId,
      event.runId & ":" & $event.step & ":thinking")
    if thinking >= 0:
      transcript.items[thinking].pending = false
    let assistant = transcript.itemIndex(event.runId,
      event.runId & ":" & $event.step & ":assistant")
    if assistant >= 0:
      transcript.items[assistant].pending = false
  of ueRunFinished:
    for item in transcript.items.mitems:
      if item.runId == event.runId: item.pending = false
  of ueError:
    for item in transcript.items.mitems:
      if item.runId == event.runId: item.pending = false
    transcript.items.add TranscriptItem(kind: tikError, id: event.runId & ":error:" &
      $transcript.items.len, text: event.error, isError: true)
