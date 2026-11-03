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

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname === "/download" || pathname === "/download/") {
      return Response.redirect(await latestDownloadURL(), 302);
    }
    return env.ASSETS.fetch(request);
  },
};
