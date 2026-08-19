import { withSupabase } from "npm:@supabase/server@^1";
import { AccessToken } from "npm:livekit-server-sdk@2.17.0";

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    try {
      if (req.method !== "POST") {
        return Response.json({ error: "Method not allowed" }, { status: 405 });
      }

      const {
        data: { user },
        error: userError,
      } = await ctx.supabase.auth.getUser();

      if (userError || !user) {
        return Response.json({ error: "Not authenticated" }, { status: 401 });
      }

      const body = await req.json();
      const conversationId = body?.conversationId;

      if (typeof conversationId !== "string" || conversationId.length < 10) {
        return Response.json(
          { error: "conversationId is required" },
          { status: 400 },
        );
      }

      const { data: membership, error: membershipError } =
        await ctx.supabase
          .from("conversation_members")
          .select("conversation_id,user_id")
          .eq("conversation_id", conversationId)
          .eq("user_id", user.id)
          .maybeSingle();

      if (membershipError) {
        console.error("Membership lookup failed:", membershipError);
        return Response.json(
          { error: "Could not verify conversation membership" },
          { status: 500 },
        );
      }

      if (!membership) {
        return Response.json(
          { error: "You are not a member of this conversation" },
          { status: 403 },
        );
      }

      const { data: profile, error: profileError } =
        await ctx.supabase
          .from("profiles")
          .select("username")
          .eq("id", user.id)
          .single();

      if (profileError || !profile) {
        return Response.json({ error: "Profile not found" }, { status: 404 });
      }

      const livekitUrl = Deno.env.get("LIVEKIT_URL");
      const apiKey = Deno.env.get("LIVEKIT_API_KEY");
      const apiSecret = Deno.env.get("LIVEKIT_API_SECRET");

      if (!livekitUrl || !apiKey || !apiSecret) {
        return Response.json(
          { error: "LiveKit is not configured" },
          { status: 500 },
        );
      }

      const roomName = `algebraunc-${conversationId}`;

      const accessToken = new AccessToken(apiKey, apiSecret, {
        identity: user.id,
        name: profile.username,
        ttl: "30m",
        metadata: JSON.stringify({
          username: profile.username,
          conversationId,
        }),
      });

      accessToken.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      const token = await accessToken.toJwt();

      return Response.json({
        token,
        url: livekitUrl,
        roomName,
        username: profile.username,
      });
    } catch (error) {
      console.error("livekit-token error:", error);
      return Response.json(
        {
          error:
            error instanceof Error
              ? error.message
              : "Failed to create call token",
        },
        { status: 500 },
      );
    }
  }),
};
