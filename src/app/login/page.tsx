"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

const inputStyle = { display: "block", width: "100%", margin: "0.5rem 0", padding: "0.5rem" };

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    const res = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    if (res.ok) router.push("/tasks");
    else setError((await res.json()).error ?? "Login failed");
  }

  return (
    <main>
      <h1>Log in</h1>
      <form onSubmit={submit}>
        <input type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} required style={inputStyle} />
        <input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required style={inputStyle} />
        <button type="submit" style={{ padding: "0.5rem 1rem" }}>Log in</button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      <p>
        No account? <Link href="/register">Register</Link>
      </p>
    </main>
  );
}
