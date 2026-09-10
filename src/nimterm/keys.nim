## Keys for the nimterm input layer.

type
  Key* = enum
    keyNone
    keyChar       ## printable; see InputEvent.ch
    keyEscape
    keyEnter
    keyBackspace
    keyDelete
    keyLeft
    keyRight
    keyUp
    keyDown
    keyHome
    keyEnd
    keyPageUp
    keyPageDown
    keyCtrlA
    keyCtrlB
    keyCtrlC
    keyCtrlE
    keyCtrlF
    keyCtrlN
    keyCtrlO
    keyCtrlP
    keyCtrlU
    keyCtrlV
    keyCopy         ## copy the selected transcript text
    keyAltB
    keyAltF
    keyTab
    keyShiftTab
    keyShiftEnter  ## newline in the composer (Shift+Enter)
