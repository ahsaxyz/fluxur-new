import { supabaseService } from "@/server/supabase";
import { NextResponse } from "next/server";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ mint: string }> },
) {
  const { mint } = await params;

  if (!mint || typeof mint !== "string") {
    return NextResponse.json(
      { error: "Missing mint address" },
      { status: 400 },
    );
  }

  if (!supabaseService) {
    return NextResponse.json({ error: "Service unavailable" }, { status: 503 });
  }

  try {
    const { data, error } = await supabaseService
      .from("commitments")
      .select(
        "mint,name,symbol,metadata_uri,created_at,creator_wallet,image_url,website,twitter,telegram,escrow_address,custody_wallet,payout_wallet",
      )
      .eq("mint", mint)
      .single();

    if (error || !data) {
      return NextResponse.json(
        { error: "Commitment not found" },
        { status: 404 },
      );
    }

    return NextResponse.json({
      mint: data.mint,
      name: data.name,
      symbol: data.symbol,
      metadataUri: data.metadata_uri || "",
      createdAt: data.created_at,
      escrowAddress: data.escrow_address,
      custodyWallet: data.custody_wallet,
      creatorPayoutWallet: data.payout_wallet,
      creatorWallet: data.creator_wallet,
      imageUrl: data.image_url,
      website: data.website,
      twitter: data.twitter,
      telegram: data.telegram,
    });
  } catch (e: unknown) {
    console.error("/api/commitment/[mint]: exception", e);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
