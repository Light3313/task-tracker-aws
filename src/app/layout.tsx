import type { ReactNode } from "react";

export const metadata = {
  title: "Task Tracker",
  description: "Task tracker application",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body
        style={{
          fontFamily: "system-ui, sans-serif",
          maxWidth: 640,
          margin: "2rem auto",
          padding: "0 1rem",
          color: "#222",
        }}
      >
        {children}
      </body>
    </html>
  );
}
