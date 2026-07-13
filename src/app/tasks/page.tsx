import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth";
import TasksClient from "./tasks-client";

export const dynamic = "force-dynamic";

export default async function TasksPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login"); // server-side auth gate
  return <TasksClient email={user.email} />;
}
