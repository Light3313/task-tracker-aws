import bcrypt from "bcryptjs";
import { query } from "./db";
import { getSessionUserId } from "./session";

// bcryptjs (pure JS) is used deliberately instead of native `bcrypt`: no native
// compilation step, so it builds cleanly in Alpine / distroless images.

export type User = { id: number; email: string };

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, 10);
}

export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}

export async function createUser(email: string, password: string): Promise<User> {
  const passwordHash = await hashPassword(password);
  const rows = await query<User>(
    "INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email",
    [email.toLowerCase(), passwordHash],
  );
  return rows[0];
}

export async function findUserByEmail(email: string) {
  const rows = await query<{ id: number; email: string; password_hash: string }>(
    "SELECT id, email, password_hash FROM users WHERE email = $1",
    [email.toLowerCase()],
  );
  return rows[0] ?? null;
}

export async function getCurrentUser(): Promise<User | null> {
  const userId = await getSessionUserId();
  if (!userId) return null;
  const rows = await query<User>("SELECT id, email FROM users WHERE id = $1", [userId]);
  return rows[0] ?? null;
}
