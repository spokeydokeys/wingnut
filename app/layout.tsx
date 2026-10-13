import type { Metadata, Viewport } from "next";
import { IBM_Plex_Mono, IBM_Plex_Sans } from "next/font/google";
import "./globals.css";

// The wireframes' typeface. Plex Mono carries every number in the app, so the
// 500 weight is loaded for it and nothing lighter.
const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  weight: ["400", "500", "600"],
  subsets: ["latin"],
  display: "swap",
});

const plexMono = IBM_Plex_Mono({
  variable: "--font-plex-mono",
  weight: ["500"],
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Wingnut",
  description: "Flight time, snags, maintenance and billing for co-owners.",
};

// `viewportFit: "cover"` plus the safe-area padding in the tab bar is what keeps
// the bottom nav clear of the iPhone home indicator.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#f3f4f6",
  viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${plexSans.variable} ${plexMono.variable} h-full antialiased`}
    >
      <body className="flex min-h-full flex-col bg-screen font-sans text-ink">
        {children}
      </body>
    </html>
  );
}
