## Platform-neutral terminal control facade.

when defined(windows):
  import ./term_windows
  export term_windows
else:
  import ./term_posix
  export term_posix
