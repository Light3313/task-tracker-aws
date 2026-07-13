import { NextRequest, NextResponse } from "next/server";
import { findUserByEmail, verifyPassword } from "@/lib/auth";
import { setSessionCookie } from "@/lib/session";
import { logger } from "@/lib/logger";
import { httpRequests } from "@/lib/metrics";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  const route = "/api/auth/login";
  try {
    const { email, password } = await req.json();
    const user =
      typeof email === "string" && typeof password === "string"
        ? await findUserByEmail(email)
        : null;

    // Same generic error whether the email is unknown or the password is wrong,
    // so the endpoint doesn't reveal which emails are registered (user enumeration).
    const ok = user ? await verifyPassword(String(password), user.password_hash) : false;
    if (!user || !ok) {
      // This log line is what a detection rule keys on
      // ("repeated login_failed from one IP" -> brute-force alert).
      logger.warn({ event: "login_failed", email }, "failed login");
      httpRequests.inc({ method: "POST", route, status: "401" });
      return NextResponse.json({ error: "Invalid credentials" }, { status: 401 });
    }

    await setSessionCookie(user.id);
    logger.info({ event: "login_success", userId: user.id }, "login success");
    httpRequests.inc({ method: "POST", route, status: "200" });
    return NextResponse.json({ id: user.id, email: user.email });
  } catch (err) {
    logger.error({ err }, "login failed");
    httpRequests.inc({ method: "POST", route, status: "500" });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
