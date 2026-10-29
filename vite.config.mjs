import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  plugins: [
    {
      name: "capacitor-mobile-entry",
      transformIndexHtml(html) {
        return {
          html,
          tags: [
            {
              tag: "script",
              children: "window.__KZAUTO_SB__ = sb;",
              injectTo: "body",
            },
            {
              tag: "script",
              attrs: { type: "module", src: "./assets/nativeAuth.js" },
              injectTo: "body",
            },
          ],
        };
      },
    },
  ],
  build: {
    outDir: "www",
    rollupOptions: {
      input: {
        index: "index.html",
        nativeAuth: "mobile/native-auth.js",
      },
      output: {
        entryFileNames: "assets/[name].js",
      },
    },
  },
});
