import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** No dynamic classloading, arbitrary JARs, reflection, script evaluation or network fetch. */
public final class Worker {
    private static final int MAX_REQUEST = 16_384;
    private static final String CATALOG = "/worker/catalog.json";
    private static final List<String> METHODS = List.of("home", "category", "search", "detail", "player");
    private static final List<String> DIAGNOSTICS = List.of(
        "__probe_network", "__probe_write", "__probe_policy", "__probe_output", "__crash", "__sleep"
    );

    private Worker() {}

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asObject(Object value) {
        if (!(value instanceof Map<?, ?> raw)) throw new WorkerError("invalid-request");
        for (Object key : raw.keySet()) if (!(key instanceof String)) throw new WorkerError("invalid-request");
        return (Map<String, Object>) raw;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> objects(Object value) {
        if (!(value instanceof List<?> raw)) throw new WorkerError("invalid-input");
        List<Map<String, Object>> output = new ArrayList<>();
        for (Object element : raw) output.add(asObject(element));
        return output;
    }

    private static String limited(Object value, int length) {
        return value instanceof String str && str.length() <= length ? str.trim() : "";
    }

    private static Map<String, Object> summary(Map<String, Object> item) {
        Map<String, Object> copy = new LinkedHashMap<>(item);
        copy.remove("episodes");
        return copy;
    }

    private static Map<String, Object> execute(
        String method, Map<String, Object> args, Map<String, Object> catalog
    ) throws Exception {
        if (DIAGNOSTICS.contains(method)) {
            if (!"1".equals(System.getenv("TVNEXT_TEST_HOOKS"))) throw new WorkerError("unsupported-method");
            return switch (method) {
                case "__probe_network" -> {
                    try (Socket socket = new Socket()) {
                        socket.connect(new InetSocketAddress("1.1.1.1", 53), 900);
                        yield Map.of("network", "unexpected-success");
                    } catch (IOException e) {
                        yield Map.of("network", "blocked");
                    }
                }
                case "__probe_write" -> {
                    boolean readonly;
                    try {
                        Files.writeString(Path.of("/worker/probe"), "x");
                        readonly = false;
                    } catch (IOException | SecurityException e) {
                        readonly = true;
                    }
                    yield Map.of("readonly", readonly);
                }
                case "__probe_policy" -> {
                    String status = Files.readString(Path.of("/proc/self/status"));
                    java.util.regex.Matcher matcher = java.util.regex.Pattern
                        .compile("(?m)^Uid:\\s*(\\d+)").matcher(status);
                    int uid = matcher.find() ? Integer.parseInt(matcher.group(1)) : -1;
                    Map<String, Object> info = new LinkedHashMap<>();
                    info.put("uid", uid);
                    info.put("hostSecretVisible", System.getenv().containsKey("TVNEXT_HOST_SECRET_TEST"));
                    info.put("memoryMax", cgroup("memory.max"));
                    info.put("pidsMax", cgroup("pids.max"));
                    info.put("cpuMax", cgroup("cpu.max"));
                    yield info;
                }
                case "__probe_output" -> Map.of("filler", "x".repeat(20_000));
                case "__crash" -> { Runtime.getRuntime().halt(17); yield Map.of(); }
                case "__sleep" -> { Thread.sleep(30_000); yield Map.of("slept", true); }
                default -> throw new WorkerError("unsupported-method");
            };
        }
        if (!METHODS.contains(method)) throw new WorkerError("unsupported-method");
        List<Map<String, Object>> categories = objects(catalog.get("categories"));
        List<Map<String, Object>> items = objects(catalog.get("items"));
        List<Map<String, Object>> summaries = items.stream().map(Worker::summary).toList();

        if ("home".equals(method)) return Map.of("categories", categories, "items", summaries);
        if ("category".equals(method)) {
            String id = limited(args.get("categoryId"), 200);
            if (id.isEmpty()) throw new WorkerError("missing-category");
            return Map.of("categories", categories, "items", items.stream()
                .filter(x -> id.equals(x.get("categoryId"))).map(Worker::summary).toList());
        }
        if ("search".equals(method)) {
            String query = limited(args.get("query"), 120).toLowerCase(Locale.ROOT);
            if (query.isEmpty()) throw new WorkerError("missing-query");
            return Map.of("items", items.stream()
                .filter(x -> ((String) x.get("name")).toLowerCase(Locale.ROOT).contains(query))
                .map(Worker::summary).toList());
        }
        String id = limited(args.get("vodId"), 200);
        Map<String, Object> item = items.stream().filter(x -> id.equals(x.get("id")))
            .findFirst().orElseThrow(() -> new WorkerError("unknown-item"));
        if ("detail".equals(method)) return item;
        Object index = args.get("episodeIndex");
        List<Map<String, Object>> episodes = objects(item.get("episodes"));
        if (!(index instanceof Long n) || n < 0 || n >= episodes.size())
            throw new WorkerError("unknown-episode");
        return episodes.get(n.intValue());
    }

    private static String cgroup(String file) {
        try { return Files.readString(Path.of("/sys/fs/cgroup", file)).trim(); }
        catch (IOException | SecurityException e) { return null; }
    }

    public static void main(String[] args) {
        try {
            byte[] wire = System.in.readNBytes(MAX_REQUEST + 1);
            if (wire.length > MAX_REQUEST) throw new WorkerError("request-too-large");
            Object payload = Json.parse(new String(wire, StandardCharsets.UTF_8));
            Map<String, Object> req = asObject(payload);
            if (!(req.get("version") instanceof Long version) || version != 1L ||
                !(req.get("method") instanceof String method) ||
                !(req.get("args") instanceof Map<?, ?>)) throw new WorkerError("invalid-request");
            Map<String, Object> catalog = asObject(Json.parse(
                Files.readString(Path.of(CATALOG), StandardCharsets.UTF_8)));
            Map<String, Object> data = execute(method, asObject(req.get("args")), catalog);
            System.out.println(Json.stringify(Map.of("version", 1, "status", "ok",
                "runtime", "java", "data", data)));
        } catch (Exception e) {
            String code = e instanceof WorkerError err ? err.getMessage() : "invalid-input";
            System.out.println(Json.stringify(Map.of("version", 1, "status", "error", "code", code)));
            System.exit(2);
        }
    }

    private static final class WorkerError extends RuntimeException {
        WorkerError(String code) { super(code); }
    }
}
