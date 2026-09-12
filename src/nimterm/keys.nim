## Keys for the nimterm input layer.

type
  Key* = enum
    keyNone
    keyChar       ## printable; see InputEvent.ch
    keyEscape
    keyEnter
    keyBackspace
    keyInsert
    keyDelete
    keyLeft
    keyRight
    keyUp
    keyDown
    keyHome
    keyEnd
    keyPageUp
    keyPageDown
    keyF1
    keyF2
    keyF3
    keyF4
    keyF5
    keyF6
    keyF7
    keyF8
    keyF9
    keyF10
    keyF11
    keyF12
    keyCtrlA
    keyCtrlB
    keyCtrlC
    keyCtrlD
    keyCtrlE
    keyCtrlF
    keyCtrlG
    keyCtrlH
    keyCtrlK
    keyCtrlL
    keyCtrlN
    keyCtrlO
    keyCtrlP
    keyCtrlQ
    keyCtrlR
    keyCtrlS
    keyCtrlT
    keyCtrlU
    keyCtrlV
    keyCtrlW
    keyCtrlX
    keyCtrlY
    keyCtrlZ
    keyCopy         ## copy the selected transcript text
    keyAltB
    keyAltF
    keyAltD
    keyAltJ
    keyAltUp
    keyAltEnter
    keyTab
    keyShiftTab
    keyShiftEnter  ## newline in the composer (Shift+Enter)
