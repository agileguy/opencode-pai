/**
 * API handler using callbacks. Refactor to async/await.
 * Must preserve the same behavior.
 */
import { readFile } from "fs";
import { join } from "path";

type Callback = (err: Error | null, data?: string) => void;

export function getConfig(key: string, cb: Callback): void {
  readFile(join(__dirname, "config.json"), "utf-8", (err, raw) => {
    if (err) {
      cb(new Error("Config file not found"));
      return;
    }
    try {
      const config = JSON.parse(raw);
      if (key in config) {
        cb(null, config[key]);
      } else {
        cb(new Error(`Key "${key}" not found in config`));
      }
    } catch (e) {
      cb(new Error("Invalid JSON in config"));
    }
  });
}

export function getUser(id: string, cb: Callback): void {
  getConfig("apiUrl", (err, url) => {
    if (err) {
      cb(err);
      return;
    }
    // Simulated fetch
    setTimeout(() => {
      if (id === "404") {
        cb(new Error("User not found"));
      } else {
        cb(null, JSON.stringify({ id, name: "Test User", url }));
      }
    }, 10);
  });
}
