# Canonical project location

- Treat `D:\Projects\Mobile App` as the only authoritative workspace for this project.
- Read, create, edit, build, test, commit, and save generated artifacts only within `D:\Projects\Mobile App` and its subdirectories.
- Do not use, synchronize from, or modify any OneDrive copy of this project.
- Before changing files, verify that the working directory resolves to `D:\Projects\Mobile App`.
- Use the GitHub `main` branch as the remote source when the local checkout needs synchronization or recovery.
- After verified project changes, commit only the intended files and push the commit from this D-drive repository to `origin/main`, unless the user explicitly asks not to push.
- Never include unrelated or untracked files in a commit without confirming that they belong to the requested change.

# Admin panel widgets

- Open new admin widgets as views inside `LeadloopShell` via `OwnerWorkspaceView`. They must share the existing orange Selvan Steel House header with the logo, theme switch, and logout. Do not replace it with a widget-specific app bar or a route that hides the header.
- Include the absolute D: paths of changed files in the handoff.
