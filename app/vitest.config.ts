import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// Separate from vite.config.ts (which is tuned for `tauri dev`/`tauri build`) so `vitest run`
// never touches the Tauri-specific dev server settings (fixed port, HMR host, etc.).
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./src/setupTests.ts"],
    globals: true,
  },
});
