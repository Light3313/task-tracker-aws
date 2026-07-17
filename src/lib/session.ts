import { createHmac, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";
import { config } from "./config";

// Stateless signed session cookie:  base64url(payload) "." HMAC-SHA256(payload, secret)
//
// The signing secret is resolved at runtime, never baked into the image or passed on the
// container command line (which the instance system log would capture):
//   - local/dev: SESSION_SECRET from the environment.
//   - AWS: fetched once from SSM Parameter Store using the instance role
//     (ssm:GetParameter + kms:Decrypt on /task-tracker/*), then cached for the process.
// Rotating the secret invalidates all sessions.

const COOKIE_NAME = "session";
const MAX_AGE_SECONDS = 60 * 60 * 24 * 7; // 7 days
const SECRET_PARAM = "/task-tracker/SESSION_SECRET";

type SessionPayload = { userId: number; exp: number };

let cachedSecret: string | undefined;

async function getSecret(): Promise<string> {
  if (cachedSecret) return cachedSecret;

  const fromEnv = process.env.SESSION_SECRET;
  if (fromEnv && fromEnv.trim() !== "") {
    cachedSecret = fromEnv;
    return cachedSecret;
  }

  const ssm = new SSMClient({ region: config.awsRegion });
  const res = await ssm.send(
    new GetParameterCommand({ Name: SECRET_PARAM, WithDecryption: true }),
  );
  const value = res.Parameter?.Value;
  if (!value) throw new Error(`Missing session secret: ${SECRET_PARAM} not found in SSM`);
  cachedSecret = value;
  return cachedSecret;
}

async function sign(data: string): Promise<string> {
  const secret = await getSecret();
  return createHmac("sha256", secret).update(data).digest("base64url");
}

async function createToken(userId: number): Promise<string> {
  const payload: SessionPayload = {
    userId,
    exp: Math.floor(Date.now() / 1000) + MAX_AGE_SECONDS,
  };
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${body}.${await sign(body)}`;
}

async function verifyToken(token: string | undefined): Promise<SessionPayload | null> {
  if (!token) return null;
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;

  const expected = await sign(body);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  // constant-time compare to avoid leaking signature validity via timing
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as SessionPayload;
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

export async function setSessionCookie(userId: number): Promise<void> {
  const store = await cookies();
  store.set(COOKIE_NAME, await createToken(userId), {
    httpOnly: true, // JS can't read it -> mitigates token theft via XSS
    secure: process.env.NODE_ENV === "production", // HTTPS-only in production (once TLS is in front)
    sameSite: "lax", // CSRF mitigation
    path: "/",
    maxAge: MAX_AGE_SECONDS,
  });
}

export async function clearSessionCookie(): Promise<void> {
  const store = await cookies();
  store.delete(COOKIE_NAME);
}

export async function getSessionUserId(): Promise<number | null> {
  const store = await cookies();
  const payload = await verifyToken(store.get(COOKIE_NAME)?.value);
  return payload?.userId ?? null;
}
