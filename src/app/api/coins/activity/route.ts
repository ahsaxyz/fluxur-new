import { NextResponse } from "next/server";
import { supabaseService } from "@/server/supabase";

export async function GET() {
  try {
    if (!supabaseService) return NextResponse.json({ items: [] });
    const { data, error } = await supabaseService
      .from("activity")
      .select("id,type,created_at,coin_id,user_id")
      .order("created_at", { ascending: false })
      .limit(25);
    if (error || !data) return NextResponse.json({ items: [] });

    const items = data;
    return NextResponse.json({ items });
  } catch {
    return NextResponse.json({ items: [] });
  }
}
