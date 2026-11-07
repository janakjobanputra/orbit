// Serves try-orbit.app: the static site in site/, plus /download, which redirects to the newest
// release's versioned disk image (Orbit-vX.Y.Z.dmg) so downloads are saved under that name.

const LATEST_RELEASE = "https://api.github.com/repos/janakjobanputra/orbit/releases/latest";
const FALLBACK = "https://github.com/janakjobanputra/orbit/releases/latest/download/Orbit.dmg";

export async function latestDownloadURL(fetchImpl = fetch) {
  try {
    const response = await fetchImpl(LATEST_RELEASE, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "try-orbit.app" },
      // GitHub allows 60 unauthenticated requests an hour, so cache the answer at the edge.
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    if (!response.ok) return FALLBACK;
    const release = await response.json();
    const image = release.assets?.find((asset) => /^Orbit-v\d+(\.\d+)*\.dmg$/.test(asset.name));
    return image?.browser_download_url ?? FALLBACK;
  } catch {
    return FALLBACK;
  }
}

const MAX_REPORT_BYTES = 256 * 1024;
const VERSION = /^\d+(\.\d+){0,3}$/;
const USAGE_OPTIONS = {
  arch: ["arm64", "x86_64"],
  eventsView: ["day", "agenda"],
  menuBarStyle: ["classic", "minimal", "agenda", "info", "icon", "custom"],
  textSize: ["small", "standard", "large", "extraLarge"],
  eventDensity: ["compact", "cozy", "airy"],
  calendars: ["0", "1-3", "4-9", "10+"],
};

/// Only known values get in, so a report can't carry anything but what the app's privacy text says it does.
export function validUsage(report) {
  if (!report || !VERSION.test(report.version) || !VERSION.test(report.os)) return false;
  return Object.entries(USAGE_OPTIONS).every(([key, options]) => options.includes(report[key]));
}

export function validCrash(report) {
  if (!report || !VERSION.test(report.version) || !VERSION.test(report.os)) return false;
  if (!/^\d{1,20}$/.test(report.build) || !USAGE_OPTIONS.arch.includes(report.arch)) return false;
  if (typeof report.callStack !== "string" || report.callStack.length === 0) return false;
  return [report.exceptionType, report.exceptionCode, report.signal].every((n) => n == null || Number.isInteger(n));
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

async function readReport(request) {
  const text = await request.text();
  if (text.length > MAX_REPORT_BYTES) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export async function handleReport(request, env, pathname) {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  if (!env.DB) return new Response(null, { status: 503 });
  const report = await readReport(request);

  if (pathname === "/api/usage") {
    if (!validUsage(report)) return new Response(null, { status: 400 });
    await env.DB.prepare(
      `INSERT INTO usage_daily (day, version, os, arch, events_view, menu_bar_style, text_size, event_density, calendars, reports)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
       ON CONFLICT (day, version, os, arch, events_view, menu_bar_style, text_size, event_density, calendars)
       DO UPDATE SET reports = reports + 1`
    )
      .bind(today(), report.version, report.os, report.arch, report.eventsView, report.menuBarStyle, report.textSize, report.eventDensity, report.calendars)
      .run();
  } else {
    if (!validCrash(report)) return new Response(null, { status: 400 });
    await env.DB.prepare(
      `INSERT INTO crashes (day, version, build, os, arch, exception_type, exception_code, signal, call_stack)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
      .bind(today(), report.version, report.build, report.os, report.arch, report.exceptionType ?? null, report.exceptionCode ?? null, report.signal ?? null, report.callStack)
      .run();
  }
  return new Response(null, { status: 204 });
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname === "/api/usage" || pathname === "/api/crash") {
      return handleReport(request, env, pathname);
    }
    if (pathname === "/download" || pathname === "/download/") {
      return Response.redirect(await latestDownloadURL(), 302);
    }
    return env.ASSETS.fetch(request);
  },
};
