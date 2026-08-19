# AlgebraUNC

Warm, showcase-style ephemeral network messenger built with GitHub Pages + Supabase.

## New room model

- **Main** — everyone who opens AlgebraUNC is automatically added to one shared room.
- **DMs** — exactly one direct-message conversation exists for each pair of usernames.
- **Online Now** — click anyone currently connected to open their existing DM.
- **Username Connect** — type a username to open the same DM even if that person is offline.
- **Groups** — make a named group from online users and/or add people by username.
- **60-minute messages** — message rows expire and your existing cron cleanup removes them.

## REQUIRED database upgrade

Before using this version:

1. Open **Supabase → SQL Editor → New Query**.
2. Open `algebraunc_features.sql` from this ZIP.
3. Paste the entire SQL file.
4. Click **Run**.
5. Wait for `Success. No rows returned`.
6. Replace your hosted `index.html` with the new one.

The SQL migration also deduplicates any old duplicate two-person DMs and creates a database unique index so duplicate DMs cannot happen again.

## GitHub Pages

Upload/replace `index.html` at the repository root. No Node server is required.

## Security model

The browser uses only the Supabase publishable key. Conversation creation now happens through `SECURITY DEFINER` RPC functions rather than permissive direct membership inserts. RLS still protects message reads/writes.

Anonymous identities are still browser-bound in this version: clearing site storage/signing out loses that anonymous identity.
