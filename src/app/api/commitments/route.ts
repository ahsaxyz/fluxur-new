import { NextResponse } from "next/server";
import { supabaseService } from "@/server/supabase";

export async function GET(req: Request) {
  if (!supabaseService) {
    console.error("Supabase service client not configured");
    return NextResponse.json({ error: "Supabase not configured" }, { status: 500 });
  }
  const { searchParams } = new URL(req.url);
  const limitParam = searchParams.get("limit") || "50";
  const limit = Number(limitParam);
  const lockedOnly = searchParams.get("locked") === "true";

  try {
    if (lockedOnly) {
      // Get commitments that have an active fee lock
      const { data: locks, error: locksErr } = await supabaseService
        .from("fee_locks")
        .select("mint")
        .eq("status", "active");

      if (locksErr) {
        console.error("Fee locks fetch error:", locksErr);
        return NextResponse.json({ error: locksErr.message }, { status: 500 });
      }

      const lockedMints = (locks || []).map((l) => l.mint);

      if (lockedMints.length === 0) {
        return NextResponse.json({ items: [] });
      }

      const { data, error } = await supabaseService
        .from("commitments")
        .select("mint,name,symbol,image_url,website,twitter,telegram,created_at")
        .in("mint", lockedMints)
        .order("created_at", { ascending: false })
        .limit(Number.isNaN(limit) ? 50 : limit);

      if (error) {
        console.error("Commitments fetch error:", error);
        return NextResponse.json({ error: error.message }, { status: 500 });
      }

      return NextResponse.json({ items: data || [] });
    }

    // Default: return all commitments
    const { data, error } = await supabaseService
      .from("commitments")
      .select("mint,name,symbol,image_url,website,twitter,telegram,created_at")
      .order("created_at", { ascending: false })
      .limit(Number.isNaN(limit) ? 50 : limit);

    if (error) {
      console.error("Commitments fetch error:", error);
      return NextResponse.json(
        { error: error.message, code: (error as any).code, details: (error as any).details },
        { status: 500 },
      );
    }

    return NextResponse.json({ items: data || [] });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("Commitments route exception:", msg);
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
