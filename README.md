# AlgebraUNC V3 — Calls + Showcase UI

This version adds LiveKit voice/video calls and a major UI/scrollability upgrade.

## New features

- Voice call button on every room
- Video call button on every room
- Main-room calls, DMs calls, and group calls all map to the current AlgebraUNC conversation
- Microphone mute/unmute
- Camera on/off
- Leave call
- Floating call stage that can be minimized
- Participant video tiles
- Speaking indicators
- Connection/reconnection status
- Adaptive stream + dynacast
- 360p default camera capture to reduce bandwidth on constrained networks
- Browser audio-unlock prompt when autoplay is blocked
- No screen sharing
- No recording
- Visible scrollbars for:
  - conversations
  - Online Now
  - messages
  - modals
  - group member lists
  - call participant stage
- Major cream/orange editorial UI upgrade

## Before using calls

You should already have:

1. LiveKit Cloud project
2. Supabase Edge Function secrets:
   - `LIVEKIT_URL`
   - `LIVEKIT_API_KEY`
   - `LIVEKIT_API_SECRET`
3. A deployed Supabase Edge Function named exactly:
   - `livekit-token`

A copy of the Edge Function is included at:

`livekit-token/index.ts`

If your deployed function already works, you do not need to change it just to test the frontend.

## Deploy

Replace the `index.html` at the root of your GitHub Pages repository with the new one.

No extra SQL is required for the call UI itself. Calls use the same `conversation_members` access model that text rooms already use.

## Call behavior

- Press **Voice**: joins the current conversation's LiveKit room and requests microphone access.
- Press **Video**: joins the same room and requests microphone + camera.
- Anyone else in that AlgebraUNC room can press the same call button to join.
- Switching to a different room's call asks you to leave the current call first.
- Calls are not stored or recorded by this app.

## Note on restrictive networks

LiveKit Cloud handles media routing and fallback. The frontend uses adaptive streaming, dynacast, and a modest default camera resolution so it behaves better when bandwidth is constrained. Network administrators can still intentionally block realtime-media services.
