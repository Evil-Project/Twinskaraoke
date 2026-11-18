# Splash website integration

The iPhone and iPad update splash opens a configured HTTPS page in a nonpersistent
WebKit session. The website owns its form, submission, and cancellation. The app
stores only installation-local per-slide status, never form answers or handshake IDs.

## Configure and test on one device

1. Open **Account → Settings → Developer → Splash Screen Studio → Update**.
2. Open a slide after **Release notes**, select **Website**, and paste an HTTPS
   address into **Website URL**. Save/export/import preserves the URL. **Standard slide settings** remains available on website slides so any invalid native field can be repaired without clearing the URL.
3. Choose **Preview**. A blank URL opens the bundled test page, with optional
   feedback and buttons for simulated submission failure, completion, and cancellation.
   Preview keeps its status in memory and never schedules real reminders. Its recovery dialog describes advancing or closing Preview rather than promising a future reminder.

A release-enabled website slide requires the exact app version and build number.
The bundled example stays disabled. **Developer → Always Show Splash → Update**
tests it with separate local history. Normal launches retain the existing eligibility
rules and show install onboarding first.

## HTTPS request and terminal callbacks

For `https://survey.example.org/form?locale=en`, the app opens:

```text
https://survey.example.org/form?locale=en#splashSession=<uuid>
```

The request is `GET /form?locale=en`. The fragment stays in the browser and is not
part of the HTTPS request. There is no callback HTTP POST endpoint. The configured
URL may contain query parameters, but must not contain credentials or a fragment.
Top-level navigation stays on the configured HTTPS origin, including its port.

Read the fragment into page memory, then remove it from the address. Keep the same
document throughout the form flow. Exclude the ID from submissions, logs, browser
storage, and analytics. A full reload loses page memory; native Retry opens a fresh
session and ID. The local test page exercises this exact handshake:

```js
let id = new URLSearchParams(location.hash.slice(1)).get("splashSession");
history.replaceState(null, "", location.pathname + location.search);

function finish(type) {
  const bridge = window.webkit?.messageHandlers?.splashCompletion;
  if (!bridge || !id) return;
  bridge.postMessage({ type, id });
  id = null;
}

// Call only after the website confirms successful submission:
// finish("completed");

// Call after the user explicitly cancels the form permanently:
// finish("canceled");
```

Send terminal messages from the top-level page. The app verifies the active web
view's controller, main frame, configured HTTPS origin, and current UUID. It accepts
only `completed` and `canceled`, consumes the ID once, and clears the session when
leaving the page. Unrecognized, duplicate, stale, and foreign-origin messages do
nothing. Each terminal callback resolves only the slide that opened that session.

## Native recovery

**Having trouble?** stays available while loading and after the page loads. It starts
in its initial recovery bar. Tapping elsewhere collapses it into a floating
bottom-right question-mark bubble. The collapsed control reserves no page height
and opens the same recovery options.
Pinch/double-tap magnification is disabled, and pull overscroll is suppressed. Normal
scrolling remains available for long forms, large text, and keyboard access. It offers:

- **Retry website**: discard the current web session and create a fresh ID. Unsent
  answers may be lost; the dialog explains this before retrying.
- **Continue for now**: leave the form pending and continue into the update or app.
- **Keep filling out**: dismiss the dialog without reloading or changing answers.

The app does not need to detect a failed AJAX request to offer recovery. A temporary
initial-load failure also offers Retry and Continue for now. Initial loading has a
15-second timeout. Return HTTP `410 Gone` for a permanently closed page: the app
records that slide as closed and offers native continuation. Closing one form does
not resolve other pending forms.

## Reminders and navigation

Before first displaying each website, the app saves pending status keyed by the
announcement ID, content fingerprint, and slide ID. Only encountered forms become
pending; websites the user has never reached are not added to the reminder queue.

During the original uninterrupted update, a terminal callback follows the standard
Next/Done transition. Continue for now follows that transition while leaving the
form unresolved. Finishing the native update enters the app, but the announcement
remains incomplete while any eligible website slides are pending.

On a later cold launch or return from the background, the app displays pending
websites alone, in slide order, without repeating changelog or native update pages.
Control Center and similar inactive transitions do not trigger a reminder. An already
visible form keeps its live page when switching to website-only continuation.

In website-only mode, completion or cancellation resolves that form and opens the
next pending form. The announcement completes and the app opens only when no
eligible website slides remain pending. Continue for now opens the app and leaves
all unresolved forms for the next opening. Remaining native slides are skipped.
A closed page's native continuation also proceeds to any other pending form.

Back navigation to a resolved website shows its completed state. Persistence Retry
repeats the same failed save without asking the website for another callback. The
app saves status and navigation together before advancing. Replaced, disabled, or
version/build-ineligible announcements retire their old reminders. Status is local
to this installation and is excluded from backups; there is no cross-device sync.

Same-origin server redirects are classified using the final navigation response, including HTTP 410. Developer cold launches retain website-only continuation for pending forms; finishing a developer run clears that run’s resolved outcomes so the next forced run opens fresh forms. Unchanged background restoration does not write state or replace the live webpage. UI automation always uses synthetic website responses.
