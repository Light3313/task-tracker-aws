import { NextRequest, NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth";
import { query } from "@/lib/db";
import { httpRequests } from "@/lib/metrics";

export const dynamic = "force-dynamic";

// GET /api/tasks — list the authenticated user's tasks.
export async function GET() {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  // authz: scoped to this user's rows only.
  const tasks = await query(
    "SELECT id, title, description, done, created_at FROM tasks WHERE user_id = $1 ORDER BY created_at DESC",
    [user.id],
  );
  httpRequests.inc({ method: "GET", route: "/api/tasks", status: "200" });
  return NextResponse.json({ tasks });
}

// POST /api/tasks — create a task owned by the authenticated user.
export async function POST(req: NextRequest) {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { title, description } = await req.json();
  if (typeof title !== "string" || title.trim() === "") {
    return NextResponse.json({ error: "Title is required" }, { status: 400 });
  }

  const rows = await query(
    "INSERT INTO tasks (user_id, title, description) VALUES ($1, $2, $3) RETURNING id, title, description, done, created_at",
    [user.id, title.trim(), typeof description === "string" ? description : ""],
  );
  httpRequests.inc({ method: "POST", route: "/api/tasks", status: "201" });
  return NextResponse.json({ task: rows[0] }, { status: 201 });
}
