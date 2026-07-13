import { NextRequest, NextResponse } from "next/server";
import { createUser, findUserByEmail } from "@/lib/auth";
import { setSessionCookie } from "@/lib/session";
import { logger } from "@/lib/logger";
import { httpRequests } from "@/lib/metrics";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  const route = "/api/auth/register";
  try {
    const { email, password } = await req.json();

    if (
      typeof email !== "string" ||
      typeof password !== "string" ||
      !email.includes("@") ||
      password.length < 8
    ) {
      httpRequests.inc({ method: "POST", route, status: "400" });
      return NextResponse.json(
        { error: "Invalid email or password (min 8 chars)" },
        { status: 400 },
      );
    }

    if (await findUserByEmail(email)) {
      httpRequests.inc({ method: "POST", route, status: "409" });
      return NextResponse.json({ error: "Email already registered" }, { status: 409 });
    }

    const user = await createUser(email, password);
    await setSessionCookie(user.id);
    logger.info({ event: "user_registered", userId: user.id }, "user registered");
    httpRequests.inc({ method: "POST", route, status: "201" });
    return NextResponse.json({ id: user.id, email: user.email }, { status: 201 });
  } catch (err) {
    logger.error({ err }, "register failed");
    httpRequests.inc({ method: "POST", route, status: "500" });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
