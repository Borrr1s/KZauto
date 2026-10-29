import { App } from "@capacitor/app";
import { Capacitor } from "@capacitor/core";
import { Browser } from "@capacitor/browser";

const NATIVE_REDIRECT_URL = "kzauto://auth/callback";
const supabase = window.__KZAUTO_SB__;

if (Capacitor.isNativePlatform()) {
  const handledAuthUrls = new Set();

  const showAuthError = (error) => {
    const message = document.getElementById("authMessage");
    if (message) {
      message.textContent = error?.message || "Не удалось войти через Google";
      message.className = "auth-message";
    }
  };

  const handleAuthUrl = async (url) => {
    const callback = new URL(url);
    if (
      callback.protocol !== "kzauto:" ||
      callback.hostname !== "auth" ||
      callback.pathname !== "/callback"
    ) {
      return;
    }
    if (handledAuthUrls.has(url)) return;
    handledAuthUrls.add(url);

    const params = new URLSearchParams(callback.hash.slice(1));
    const authError =
      callback.searchParams.get("error_description") ||
      callback.searchParams.get("error") ||
      params.get("error_description") ||
      params.get("error");
    if (authError) {
      showAuthError(new Error(authError));
      return;
    }

    let error;
    const code = callback.searchParams.get("code");
    if (code) {
      ({ error } = await supabase.auth.exchangeCodeForSession(url));
    } else {
      const access_token = params.get("access_token");
      const refresh_token = params.get("refresh_token");
      if (!access_token || !refresh_token) return;
      ({ error } = await supabase.auth.setSession({ access_token, refresh_token }));
    }

    if (error) {
      showAuthError(error);
      return;
    }

    await Browser.close();
  };

  window.__nativeGoogleSignIn = async () => {
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: NATIVE_REDIRECT_URL,
        skipBrowserRedirect: true,
      },
    });
    if (error) throw error;
    if (!data.url) throw new Error("Не удалось открыть страницу Google");
    await Browser.open({ url: data.url });
  };

  App.addListener("appUrlOpen", ({ url }) => {
    handleAuthUrl(url).catch(showAuthError);
  });

  App.getLaunchUrl()
    .then((launch) => {
      if (launch?.url) return handleAuthUrl(launch.url);
    })
    .catch(showAuthError);
}
