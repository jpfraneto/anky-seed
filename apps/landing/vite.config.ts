import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "node:path";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, "index.html"),
        youForgotMe: resolve(
          import.meta.dirname,
          "anky/you-forgot-me/index.html",
        ),
      },
    },
  },
  server: {
    allowedHosts: ["miniapp.anky.app"],
  },
});
