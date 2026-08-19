# AlgebraUNC Chat — Showcase Live

A tiny anonymous, ephemeral friend messenger built for GitHub Pages + Supabase.

## What is already configured

The included `index.html` already contains your Supabase Project URL and **publishable** key.

There are no email/password accounts. On first visit the browser creates a Supabase anonymous user and asks for a username. Supabase stores that session in browser storage.

## Features

- Username-only onboarding
- Anonymous Supabase Auth
- Live online-person directory (no search required)
- Click any online person to instantly open a DM
- Group chats
- Realtime incoming messages
- Online/offline presence
- Replies
- Emoji reactions
- Delete your own messages
- 60-minute expiration
- Responsive desktop/mobile UI
- No WebRTC or P2P

## IMPORTANT: run the final SQL patch

1. Open your Supabase project.
2. Go to **SQL Editor → New query**.
3. Open `setup_patch.sql`.
4. Paste the entire file into the query.
5. Click **Run**.

That patch schedules database cleanup every minute. It deletes rows whose 60-minute `expires_at` has passed.

The app's RLS policy already prevents expired messages from being returned, so the visible lifetime remains 60 minutes even between cleanup runs.

## Put it on GitHub Pages

1. Create a new GitHub repository.
2. Upload `index.html` to the repository root.
3. Commit the file.
4. Open the repository's **Settings → Pages**.
5. Under **Build and deployment**, choose **Deploy from a branch**.
6. Choose your main branch and `/ (root)`.
7. Save.

GitHub will give you a Pages URL after deployment.

## Security notes

- The `sb_publishable_...` value in `index.html` is intentionally public.
- Never put a Supabase secret key, `service_role` key, or database password in this repository.
- Access control is enforced by the Row Level Security policies you already installed.
- Anonymous identities are browser-bound in v1. If a user clears site storage or signs out, that identity cannot be recovered.
- This is ephemeral storage, not end-to-end encryption. Supabase is still the backend that processes/stores messages until deletion.

## Files

- `index.html` — complete website
- `setup_patch.sql` — final cleanup/index policy patch
- `README.md` — these instructions

## Live directory

The Online Now screen uses Supabase Realtime Presence. A person appears while their AlgebraUNC tab is actively connected, and disappears when their presence leaves the shared channel.
