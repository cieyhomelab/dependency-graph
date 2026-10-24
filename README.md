# GitHub Issue Dependency Graph

A local tool that draws a [Mermaid](https://mermaid.js.org/) graph of GitHub issue dependencies ("blocked by" / "blocking"), so you can see what is blocked, by what, and which issues to tackle first.

Everything runs on your machine. No server, no hosting — data only travels between your computer and GitHub.

The page makes exactly one kind of network request: to your GitHub API (`api.github.com`, or `https://<your-host>/api/graphql` for GitHub Enterprise). The Mermaid library ([v11.17.2](https://github.com/mermaid-js/mermaid), MIT license) is embedded in `issue-graph.html`, so nothing is loaded from a CDN and the page works without internet access to anything other than GitHub. That is why the file is about 3.5 MB. `issue-graph-cdn.html` is the lightweight alternative that loads Mermaid from a CDN instead.

**Your token is sent only to the host in the repository field.** Paste the repository URL straight from your browser to avoid typos in the domain.

## Files

| File | Purpose |
|---|---|
| `issue-graph.html` | The viewer, with Mermaid built in (~3.5 MB, fully offline). Open it in a browser (token mode), or use it as the template for the script. |
| `issue-graph-cdn.html` | Same viewer and design, but loads Mermaid from a CDN link (~30 KB). See [Which HTML version?](#which-html-version) |
| `issue-graph.sh` | Fetches issues using your `gh` login and generates a ready-to-open HTML file. |

Keep both files in the same folder.

## Option A — use your `gh` login (recommended)

No token needs to be created or pasted; the token never reaches the browser.

**Requirements:** [GitHub CLI](https://cli.github.com) logged in (`gh auth login`), bash (macOS, Linux, or Git Bash / WSL on Windows).

```bash
chmod +x issue-graph.sh          # first time only
./issue-graph.sh org/repo        # open issues only
./issue-graph.sh org/repo --all  # include closed issues

# GitHub Enterprise Server: pass the full URL
./issue-graph.sh https://github.example.com/org/repo
```

For GitHub Enterprise, log in to that host once: `gh auth login --hostname github.example.com`.

The script writes `issue-graph-org_repo.html` in the current folder and opens it in your browser.

| Option | Description |
|---|---|
| `--all` | Include closed issues (default: open only). |
| `-o FILE`, `--out FILE` | Output file name. |
| `--no-open` | Don't open the result in the browser. |
| `--cdn` | Build from `issue-graph-cdn.html` — a small output file that loads Mermaid from the CDN. |
| `-h`, `--help` | Show usage. |

To refresh the data, run the script again. The generated file is self-contained, but it **contains the text of your issues**, so treat it like the repository itself when sharing.

## Option B — open the HTML directly with a token

1. Double-click `issue-graph.html` (or `issue-graph-cdn.html`).
2. Enter the repository as `org/repo`, or paste its URL. For **GitHub Enterprise Server** always paste the full URL (e.g. `https://github.example.com/org/repo`) so the page knows which server to call.
3. Paste a token. Either:
   - run `gh auth token` (Enterprise: `gh auth token --hostname github.example.com`) and paste the output, or
   - create a fine-grained token on the same GitHub host as the repository: GitHub → Settings → Developer settings → Fine-grained tokens → Resource owner = your organization, select the repository, permission **Issues: Read-only**.
4. Click **Fetch & draw**.

Tick **remember in this browser** to store the token in the browser's local storage on this machine. Leave it unticked on shared computers.

## Which HTML version?

Both files look and work the same; they differ only in where the Mermaid drawing library comes from.

| | `issue-graph.html` | `issue-graph-cdn.html` |
|---|---|---|
| Mermaid | built into the file | loaded from `cdn.jsdelivr.net` |
| File size | ~3.5 MB | ~30 KB |
| Network access needed | GitHub only | GitHub + jsDelivr CDN |
| Works when the CDN is blocked | yes | only with a local `mermaid.min.js` next to it |
| Easy to email / attach | larger | yes |

The CDN version pins the exact version (11.17.2) and uses an [integrity hash](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity): if the file served by the CDN were ever altered, the browser refuses to run it. If the CDN can't be reached, the page tries `mermaid.min.js` in the same folder ([download v11.17.2](https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js)).

## Reading the graph

- **Arrow A → B** means *A blocks B*.
- **Dashed arrow** — the blocker is already closed (resolved dependency).
- **Arrow labeled "from description"** — dependency parsed from issue text. The label appears only when the graph mixes native GitHub links and text-based ones.
- **Colors:**
  - red — blocked by at least one open issue
  - yellow — not blocked, and blocks other open issues (good candidates to start)
  - grey — open, no open dependencies in either direction
  - green — closed
- Click a node to open the issue on GitHub.
- **Dashed violet frames** group issues by epic (see *group by epic* below).
- Issues from other repositories are shown as `org/other-repo#N`.

Side panels:
- **Blocked** — every blocked issue with its open blockers.
- **Do these first** — unblocked issues sorted by how many open issues they unblock, including indirectly.

## Controls

| Control | What it does |
|---|---|
| Direction | Horizontal (→) or vertical (↓) layout. |
| open only | Hide closed issues. In token mode it also fetches only open issues; change it and fetch again to load closed ones. |
| only issues with dependencies | Hide issues with no links. |
| also read "Depends on / Blocked by" from descriptions | On by default. Reads dependency lines in issue text — `Depends on:`, `Blocked by:`, `Requires:`, `Dependencies:` (plus Polish `Zależy od:`, `Zablokowane przez:`). Every issue reference after the keyword on that line counts: `#12`, Markdown links like `[#12](https://…/issues/12) (E01-S01)`, issue URLs and `org/repo#12`. Other lines (e.g. `Epic: #21`) are ignored. |
| group by epic | On by default. Draws a dashed frame around issues of the same epic, taken from an `Epic:` line in the description (also `Parent:` / `Parent issue:` / `Epik:`), e.g. `Epic: [#21](https://…/issues/21) (E02)`. The frame shows the code in parentheses, the epic number and the epic issue's title. Issues without an `Epic:` line stay outside frames. |
| Focus on # | Show only the chain connected to one issue (everything it depends on and everything that depends on it). |
| Redraw | Re-render with the current options without fetching again. |
| − / Fit / + | Zoom. Ctrl + mouse wheel also zooms. |
| Download SVG | Save the graph as an image. |
| Mermaid source | View and copy the generated Mermaid code (e.g. to paste into a GitHub issue or README, where GitHub renders it natively). |

## Setting dependencies on GitHub

On an issue page, in the right sidebar, use **Relationships → Mark as blocked by / blocking**. These native links are what the tool reads by default.

## Troubleshooting

| Problem | Fix |
|---|---|
| `401 – token is invalid or expired` | Create a new token or run `gh auth token` again. |
| Error mentioning SAML / SSO | The organization requires SSO. For `gh`: run `gh auth refresh -h github.com` and approve in the browser. For a fine-grained token: Settings → Tokens → Configure SSO → Authorize. Your org admin may also need to approve the token. |
| "Repository not found" | Check the `org/repo` spelling and that your account has access. |
| `gh is not logged in` | Run `gh auth login`. |
| Script says `--slurp` is unknown | Update GitHub CLI (version 2.48 or newer). |
| "Cannot reach …/api/graphql (network or CORS error)" | Connect to the company network/VPN. If it still fails, your Enterprise server blocks browser requests from local files — use `issue-graph.sh` instead. |
| "does not support native issue dependencies" | Older GitHub Enterprise Server versions lack blocked-by links. The tool falls back to reading `blocked by #N` from issue descriptions automatically. |
| "Mermaid library could not be loaded from cdn.jsdelivr.net" (CDN version) | The company network blocks the CDN. Use `issue-graph.html` instead, or save `mermaid.min.js` v11.17.2 next to the CDN file. |
| Graph is empty | Untick "only issues with dependencies", or check that issues actually have blocked-by links. |
| Graph is huge | Use **Focus on #** to show a single chain, or switch the layout direction. |

## Limits

- Up to 50 blockers per issue are read (GitHub's per-request limit used here).
- Large repositories are fetched 100 issues per request; thousands of issues may take a little while.
- Text parsing only links issues within the same repository and only to issues that were fetched.
