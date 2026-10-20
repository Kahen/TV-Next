import fs from "node:fs";
import net from "node:net";

const fixture = JSON.parse(fs.readFileSync("/worker/catalog.json", "utf8"));
const METHODS = new Set(["home", "category", "search", "detail", "player"]);
const TEST_METHODS = new Set(["__probe_network", "__probe_write", "__probe_policy", "__probe_output", "__crash", "__sleep"]);

function fail(code) {
  process.stdout.write(JSON.stringify({ version: 1, status: "error", code }) + "\n");
  process.exitCode = 2;
}

function getText(value, max = 200) {
  return typeof value === "string" && value.length <= max ? value.trim() : "";
}

function networkProbe() {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (status) => {
      if (!settled) {
        settled = true;
        socket.destroy();
        resolve(status);
      }
    };
    const socket = net.createConnection({ host: "1.1.1.1", port: 53 });
    socket.setTimeout(900);
    socket.on("connect", () => finish("unexpected-success"));
    socket.on("timeout", () => finish("blocked"));
    socket.on("error", () => finish("blocked"));
  });
}

async function handle(message) {
  if (!message || message.version !== 1 || !message.args ||
      typeof message.args !== "object" || Array.isArray(message.args) ||
      typeof message.method !== "string") throw new Error("invalid-request");
  const { method, args } = message;
  if (TEST_METHODS.has(method)) {
    if (process.env.TVNEXT_TEST_HOOKS !== "1") throw new Error("unsupported-method");
    if (method === "__probe_network") return { network: await networkProbe() };
    if (method === "__probe_write") {
      try { fs.writeFileSync("/worker/probe", "x"); return { readonly: false }; }
      catch { return { readonly: true }; }
    }
    if (method === "__probe_policy") {
      const read = (path) => {
        try { return fs.readFileSync(path, "utf8").trim(); } catch { return null; }
      };
      return {
        uid: process.getuid?.() ?? -1,
        hostSecretVisible: Object.hasOwn(process.env, "TVNEXT_HOST_SECRET_TEST"),
        memoryMax: read("/sys/fs/cgroup/memory.max"),
        pidsMax: read("/sys/fs/cgroup/pids.max"),
        cpuMax: read("/sys/fs/cgroup/cpu.max")
      };
    }
    if (method === "__probe_output") return { filler: "x".repeat(20_000) };
    if (method === "__crash") process.exit(17);
    if (method === "__sleep") {
      await new Promise((resolve) => setTimeout(resolve, 30_000));
      return { slept: true };
    }
  }
  if (!METHODS.has(method)) throw new Error("unsupported-method");
  const categories = fixture.categories;
  const items = fixture.items;
  if (method === "home") return { categories, items: items.map(({ episodes, ...item }) => item) };
  if (method === "category") {
    const id = getText(args.categoryId);
    if (!id) throw new Error("missing-category");
    return { categories, items: items.filter((item) => item.categoryId === id)
      .map(({ episodes, ...item }) => item) };
  }
  if (method === "search") {
    const query = getText(args.query, 120).toLowerCase();
    if (!query) throw new Error("missing-query");
    return { items: items.filter((item) => item.name.toLowerCase().includes(query))
      .map(({ episodes, ...item }) => item) };
  }
  const item = items.find((entry) => entry.id === getText(args.vodId));
  if (!item) throw new Error("unknown-item");
  if (method === "detail") return item;
  const index = args.episodeIndex;
  if (!Number.isInteger(index) || index < 0 || index >= item.episodes.length) {
    throw new Error("unknown-episode");
  }
  return { name: item.episodes[index].name, url: item.episodes[index].url };
}

async function main() {
  try {
    const chunks = [];
    let length = 0;
    for await (const chunk of process.stdin) {
      length += chunk.length;
      if (length > 16_384) throw new Error("request-too-large");
      chunks.push(chunk);
    }
    const request = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const result = await handle(request);
    process.stdout.write(JSON.stringify({
      version: 1, status: "ok", runtime: "node", data: result
    }) + "\n");
  } catch (error) {
    const known = new Set([
      "invalid-request", "unsupported-method", "request-too-large",
      "missing-category", "missing-query", "unknown-item", "unknown-episode"
    ]);
    fail(known.has(error?.message) ? error.message : "invalid-input");
  }
}
await main();
