# Splash website integration

The iPhone and iPad update splash opens a configured HTTPS page in its own
WebKit view. Once the page reports completion, the app runs the standard
**Next** action or **Done** on the last slide. It saves splash progress before
advancing or opening the app.

## Configure and test on one device

1. Open **Account → Settings → Developer → Splash Screen Studio** and choose
   **Update**.
2. Open an additional slide after **Release notes**. Under **Slide type**,
   select **Website** and paste the HTTPS address into **Website URL**.
3. Return to the walkthrough editor and choose **Preview**. A blank URL
   opens the local test page. Its **Complete test page** button uses the same
   message handler as a hosted website.

The local draft keeps the URL when saved or exported. An enabled announcement
with a website requires both the target version and exact build number. The
bundled example is disabled. **Developer → Always Show Splash → Update**
lets you run that example locally with separate test progress.

## HTTPS request and completion message

For a configured URL such as `https://survey.example.org/form?locale=en`, the
app opens a URL of this form in the web view.

```text
https://survey.example.org/form?locale=en#splashSession=<uuid>
```

The HTTPS request is `GET /form?locale=en`. The UUID is passed to the webpage
in the fragment, which stays in the browser. The configured URL may include
query parameters and must leave the fragment free for the app. Top-level
navigation stays on the configured HTTPS origin, including its port.

Read the fragment on load, remove it from the address, and keep the UUID in
page memory until completion. Use the same document for the flow so it can
keep that value through form steps. A full page reload discards page memory.
Exclude the UUID from form submissions, browser storage, and logs.

Use this JavaScript when the page determines that its work is complete. The
local simulator test page uses the same fragment parser and message payload.

```js
let id = new URLSearchParams(location.hash.slice(1)).get("splashSession");

if (id) {
  history.replaceState(null, "", location.pathname + location.search);
}

function completeSplashStep() {
  const completion = window.webkit?.messageHandlers?.splashCompletion;
  if (!completion || !id) return;
  completion.postMessage({ type: "completed", id });
  id = null;
}
```

Call `completeSplashStep()` from the top-level page. The app accepts the
`completed` message once when it comes from the active web view and matches
the main frame, configured HTTPS origin, and current UUID. `postMessage`
goes to WebKit in the app. This connection requires only the initial HTTPS
page request.

## Closed pages and retries

- Return HTTP `410 Gone` for the embedded page if the website is closed.
  The app shows **Continue to update**.
- On a temporary page-load failure, the app offers **Retry** and **Continue
  to update**. The initial load has a 15-second limit. Retry starts a fresh
  web session and UUID. Leaving the slide also clears the session.
- If the app cannot save progress after a valid completion, its native
  **Retry** button retries the saved action. The website has already finished
  its part of the exchange.
