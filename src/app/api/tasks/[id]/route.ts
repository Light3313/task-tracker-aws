import { NextRequest, NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth";
import { query } from "@/lib/db";

export const dynamic = "force-dynamic";

// PATCH /api/tasks/:id — update one of the current user's tasks (toggle done, edit text).
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id } = await params;
  const body = await req.json();

  // The "AND user_id = $5" is the authz check: a user can only mutate their own rows.
  // Drop it and anyone could PATCH /api/tasks/<someone-else's-id> — the IDOR
  // (Insecure Direct Object Reference) class, and the reason this app is multi-user
  // in the first place.
  const rows = await query(
    `UPDATE tasks SET
       title       = COALESCE($1, title),
       description = COALESCE($2, description),
       done        = COALESCE($3, done),
       updated_at  = now()
     WHERE id = $4 AND user_id = $5
     RETURNING id, title, description, done, created_at`,
    [
      body.title ?? null,
      body.description ?? null,
      typeof body.done === "boolean" ? body.done : null,
      id,
      user.id,
    ],
  );

  if (rows.length === 0) return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json({ task: rows[0] });
}

// DELETE /api/tasks/:id — delete one of the current user's tasks.
export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id } = await params;
  const rows = await query("DELETE FROM tasks WHERE id = $1 AND user_id = $2 RETURNING id", [
    id,
    user.id,
  ]);

  if (rows.length === 0) return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json({ status: "deleted" });
}
