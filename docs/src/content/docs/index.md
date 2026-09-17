---
title: nimterm
description: A terminal UI library designed for building agents in Nim, with streamed transcripts, tool calls, approvals, prompts, and a testable canvas.
template: splash
hero:
  title: The terminal UI library for Nim
  tagline: Built for agent frontends. Stream output, show tool calls, collect approvals, and run the session in a native terminal UI.
  actions:
    - text: Get started
      link: /introduction/
      variant: primary
      icon: right-arrow
    - text: View on GitHub
      link: https://github.com/martineastwood/nimterm
      variant: secondary
      icon: external
---

<div class="landing-shell not-content">
  <p class="landing-lede">Install nimterm, compose a widget tree, and run an interactive terminal app from Nim. Stream agent output into a transcript, collect approvals and prompts, and test the rendered cells without a live terminal.</p>

  <section class="landing-terminal" aria-labelledby="landing-terminal-title">
    <div class="landing-terminal-bar">
      <div class="landing-terminal-dots" aria-hidden="true"><span></span><span></span><span></span></div>
      <span id="landing-terminal-title">hello.nim</span>
      <span class="landing-terminal-mode">interactive</span>
    </div>
    <pre class="not-content"><code><span class="kw">import</span> nimterm&#10;&#10;<span class="kw">let</span> screen = newPanel(
  newText(<span class="str">&quot;Hello from nimterm&quot;</span>),
  title = <span class="str">&quot;Welcome&quot;</span>)
<span class="kw">var</span> app = newApp(newPlatformBackend(fullscreen = <span class="kw">false</span>), screen)
app.run()</code></pre>
  </section>

  <section class="landing-section" aria-labelledby="landing-runtime-title">
    <p class="landing-kicker">Native Nim</p>
    <h2 id="landing-runtime-title">A frontend you can ship in a binary</h2>
    <p class="landing-section-intro">Nimterm is ordinary Nim. It compiles into your program, paints terminal cells, and does not require a hosted service, a webview, or a model SDK beside the app you already ship.</p>
    <div class="landing-grid">
      <article class="landing-card">
        <span class="landing-card-index">01</span>
        <h3>Testable rendering</h3>
        <p>Measure, lay out, and paint widgets onto a canvas you can assert on in tests without opening a live terminal.</p>
      </article>
      <article class="landing-card">
        <span class="landing-card-index">02</span>
        <h3>Agent-shaped widgets</h3>
        <p>Transcripts, tool calls, approvals, diffs, input, menus, and questions cover the path from streamed events to cells.</p>
      </article>
      <article class="landing-card">
        <span class="landing-card-index">03</span>
        <h3>Bring any event source</h3>
        <p>Adapt your model SDK, subprocess, or remote service to the agent event vocabulary. No nimgent dependency required.</p>
      </article>
      <article class="landing-card">
        <span class="landing-card-index">04</span>
        <h3>Small API surface</h3>
        <p>Start with <code>newApp</code>, a backend, and a widget tree. Reach for lower-level modules when you need custom widgets or a host-owned loop.</p>
      </article>
    </div>
  </section>

  <section class="landing-section" aria-labelledby="landing-work-title">
    <p class="landing-kicker">In your app</p>
    <h2 id="landing-work-title">From events to terminal cells</h2>
    <p class="landing-section-intro">Poll input, route events through widgets, and present frames. Nimterm normalizes keyboard, mouse, timer, resize, and agent lifecycle events into one vocabulary.</p>
    <div class="landing-grid">
      <article class="landing-card">
        <span class="landing-card-index">01</span>
        <h3>Stream a transcript</h3>
        <p>Feed <code>AgentUiEvent</code> values into a retained transcript that groups thinking, text, tools, and approvals by run.</p>
      </article>
      <article class="landing-card">
        <span class="landing-card-index">02</span>
        <h3>Collect decisions</h3>
        <p>Ask for text, pick from a menu, or answer a multiple-choice question and handle the resulting <code>UiAction</code>.</p>
      </article>
      <article class="landing-card">
        <span class="landing-card-index">03</span>
        <h3>Render Markdown and diffs</h3>
        <p>Wrap ANSI-aware text layout, semantic styles, and Markdown rendering in panels, cards, and scroll regions.</p>
      </article>
      <article class="landing-card">
        <span class="landing-card-index">04</span>
        <h3>Theme the session</h3>
        <p>Use built-in dark and light palettes or load JSON theme files with ANSI 16, ANSI 256, and truecolor values.</p>
      </article>
    </div>
  </section>

  <section class="landing-section" aria-labelledby="landing-customize-title">
    <p class="landing-kicker">Agent-neutral events</p>
    <h2 id="landing-customize-title">Any source in, rendered UI out</h2>
    <p class="landing-section-intro">Map your agent or model events to <code>AgentUiEvent</code>, apply them to a transcript widget, and let nimterm handle layout, wrapping, and redraw.</p>
    <div class="landing-extend">
      <div class="landing-code">
        <div class="landing-code-bar"><span>transcript.nim</span></div>
        <pre class="not-content"><code><span class="kw">import</span> nimterm&#10;&#10;<span class="kw">let</span> transcript = newTranscript()
<span class="kw">let</span> view = newTranscriptWidget(transcript)
<span class="kw">var</span> app = newApp(newPlatformBackend(fullscreen = <span class="kw">false</span>), view)&#10;&#10;app.onEvent = <span class="kw">proc</span> (app: <span class="kw">var</span> App, event: UiEvent): EventResponse =
  <span class="kw">if</span> event.kind == uiAgent:
    view.apply(event.agent)
    app.invalidate()
    <span class="kw">return</span> eventHandled
  eventIgnored&#10;&#10;app.run()</code></pre>
      </div>
      <div class="landing-grid">
        <article class="landing-card">
          <span class="landing-card-index">01</span>
          <h3>Compose the UI tree</h3>
          <p>Stack panels, cards, columns, and scroll regions around text, input, menus, and transcript views.</p>
        </article>
        <article class="landing-card">
          <span class="landing-card-index">02</span>
          <h3>Own the event loop</h3>
          <p>Run the built-in <code>App</code> loop or integrate timers and sources into a host-owned loop when you need finer control.</p>
        </article>
        <article class="landing-card">
          <span class="landing-card-index">03</span>
          <h3>Pick a backend</h3>
          <p>Use the platform backend on POSIX or Windows, or plug in a custom terminal bridge for headless tests.</p>
        </article>
        <article class="landing-card">
          <span class="landing-card-index">04</span>
          <h3>Assert on output</h3>
          <p>Render to a canvas in tests and compare cells, styles, and actions without driving a real terminal session.</p>
        </article>
      </div>
    </div>
    <div class="landing-links">
      <a href="/guides/quickstart/" class="landing-link"><span>Quickstart</span><small>Build an interactive terminal app in a few lines.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/agent-frontends/" class="landing-link"><span>Agent frontends</span><small>Render streamed lifecycle events without a provider dependency.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/widgets/" class="landing-link"><span>Widgets</span><small>Compose panels, inputs, menus, questions, and transcripts.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/application-loop/" class="landing-link"><span>Application loop</span><small>Connect timers, sources, and host-owned event loops.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/styling-and-themes/" class="landing-link"><span>Styling and themes</span><small>Use semantic styles and load JSON palettes.</small><span aria-hidden="true">↗</span></a>
    </div>
  </section>

  <section class="landing-section landing-split" aria-labelledby="landing-interfaces-title">
    <div>
      <p class="landing-kicker">One library, several entry points</p>
      <h2 id="landing-interfaces-title">Use the layer that fits the job</h2>
      <p class="landing-section-intro">The same widget tree can run in a fullscreen session, a compact panel, or a deterministic test harness with the same event and action model.</p>
    </div>
    <div class="landing-links">
      <a href="/guides/quickstart/" class="landing-link"><span>newApp</span><small>Create the application shell, backend, and root widget.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/agent-frontends/" class="landing-link"><span>newTranscript</span><small>Retain streamed agent output across runs and steps.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/input-and-events/" class="landing-link"><span>onAction</span><small>Handle submit, select, and answer results from widgets.</small><span aria-hidden="true">↗</span></a>
      <a href="/guides/testing/" class="landing-link"><span>Canvas tests</span><small>Assert on rendered cells and events without a live terminal.</small><span aria-hidden="true">↗</span></a>
    </div>
  </section>

  <section class="landing-start" aria-labelledby="landing-start-title">
    <div>
      <p class="landing-kicker">Start in a few lines</p>
      <h2 id="landing-start-title">Compose the UI. Run it in the terminal.</h2>
      <p>Install nimterm with Nimble, create a small app file, and compile it into a binary you can run from any interactive terminal session.</p>
    </div>
    <pre><code><span class="landing-prompt">$</span> nimble install nimterm
<span class="landing-prompt">$</span> nim c -r hello.nim</code></pre>
  </section>

  <p class="landing-footer-link"><a href="/introduction/">Get Started</a> or <a href="https://github.com/martineastwood/nimterm">view nimterm on GitHub</a>.</p>
</div>
