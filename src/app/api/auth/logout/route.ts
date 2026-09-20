import { NextResponse } from "next/server";
import { clearSessionCookie } from "@/lib/session";
import { withRequestLog } from "@/lib/request-log";

export const dynamic = "force-dynamic";

async function logout() {
  await clearSessionCookie();
  return NextResponse.json({ status: "logged-out" });
}

export const POST = withRequestLog("/api/auth/logout", logout);
