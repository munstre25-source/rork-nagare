import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Jojo Insights",
  robots: { index: false, follow: false, nocache: true },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
