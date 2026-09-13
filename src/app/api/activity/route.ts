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

export async function GET(request: Request) {
  try {
    if (!supabaseService) {
      console.error("/api/activity: Supabase not configured");
      return NextResponse.json({ items: [] });
    }

    const token = readCookie(request.headers.get("cookie"), "sb_session");
    if (!token) return NextResponse.json({ items: [] });
    const tokenHash = createHash("sha256").update(token).digest("hex");
    const { data: sess } = await supabaseService
      .from("user_sessions")
      .select("user_id,expires_at")
      .eq("token_hash", tokenHash)
      .order("id", { ascending: false })
      .limit(1)
      .single();
    if (!sess || new Date(sess.expires_at) <= new Date()) return NextResponse.json({ items: [] });

    // Load wallet for this user
    const { data: user } = await supabaseService
      .from("users")
      .select("wallet_address")
      .eq("id", sess.user_id)
      .single();
    if (!user || !user.wallet_address) return NextResponse.json({ items: [] });

    // Fetch recent commitments for this wallet
    const { data: commits, error } = await supabaseService
      .from("commitments")
      .select("mint,name,symbol,created_at")
      .eq("creator_wallet", user.wallet_address)
      .order("created_at", { ascending: false })
      .limit(25);
    if (error || !commits) return NextResponse.json({ items: [] });

    const items = commits.map((c: any, idx: number) => ({
      id: idx + 1,
      type: "coin_created",
      created_at: c.created_at,
      coin: { id: idx + 1, name: c.name, symbol: c.symbol, mint_address: c.mint },
    }));

    return NextResponse.json({ items });
  } catch (e: unknown) {
    console.error("/api/activity: exception", e);
    return NextResponse.json({ items: [] });
  }
}
