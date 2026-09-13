import { NextResponse } from "next/server";
import { supabaseService } from "@/server/supabase";
import { createHash } from "crypto";

function readCookie(header: string | null, key: string): string | null {
  if (!header) return null;
  const parts = header.split(/;\s*/);
  for (const p of parts) {
    const [k, ...rest] = p.split("=");
    if (k === key) return rest.join("=");
  }
  return null;
}

async function getUserIdFromRequest(request: Request): Promise<number | null> {
  if (!supabaseService) return null;
  const token = readCookie(request.headers.get("cookie"), "sb_session");
  if (!token) return null;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const { data: sess, error } = await supabaseService
    .from("user_sessions")
    .select("id, user_id, expires_at")
    .eq("token_hash", tokenHash)
    .order("id", { ascending: false })
    .limit(1)
    .single();
  if (error) {
    console.error("/api/coins/create: session lookup error", error);
    return null;
  }
  if (!sess || new Date(sess.expires_at) <= new Date()) return null;
  return sess.user_id as number;
}

export async function POST(request: Request) {
  try {
    if (!supabaseService) {
      console.error("/api/coins/create: Supabase not configured");
      return NextResponse.json({ error: "Supabase not configured" }, { status: 500 });
    }
    const userId = await getUserIdFromRequest(request);
    if (!userId) {
      console.error("/api/coins/create: unauthorized (no session)");
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    const { name, symbol } = await request.json();
    if (!name || !symbol) {
      console.error("/api/coins/create: missing fields", { name, symbol });
      return NextResponse.json({ error: "Missing fields" }, { status: 400 });
    }

    const { data: coin, error: coinErr } = await supabaseService
      .from("coins")
      .insert({ name, symbol, creator_user_id: userId })
      .select("id, name, symbol, creator_user_id")
      .single();
    if (coinErr || !coin) {
      console.error("/api/coins/create: coin insert error", coinErr);
      return NextResponse.json({ error: coinErr?.message || "Insert failed" }, { status: 500 });
    }

    const { error: actErr } = await supabaseService
      .from("activity")
      .insert({ type: "coin_created", user_id: userId, coin_id: coin.id });
    if (actErr) {
      console.error("/api/coins/create: activity insert error", actErr);
      return NextResponse.json({ error: actErr.message }, { status: 500 });
    }

    return NextResponse.json({ ok: true, coin });
  } catch (e: unknown) {
    console.error("/api/coins/create: exception", e);
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
