import com.github.catvod.crawler.Spider;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** RPC v2 for the approved pure-JVM FongMi method subset; one isolated invocation. */
public final class JvmSpiderWorker {
    private static final int LIMIT = 16_384;
    private static final Set<String> METHODS = Set.of("home", "category", "search", "detail", "player");
    private static final Set<String> ERRORS = Set.of("invalid-request", "provider-not-approved", "jar-integrity",
        "jar-preflight", "unsupported-api", "unsupported-method", "unsupported-pagination", "provider-execution",
        "invalid-provider-response", "provider-cleanup-failed", "provider-resource-limit", "request-too-large", "output-too-large");

    @SuppressWarnings("unchecked")
    static Map<String, Object> object(Object value) {
        if (!(value instanceof Map<?, ?> map) || !map.keySet().stream().allMatch(String.class::isInstance)) invalid();
        return (Map<String, Object>) value;
    }
    private static void invalid() { throw new ProviderFailure("invalid-request"); }
    private static String string(Map<String,Object> args, String key, int max, String fallback) {
        Object value = args.getOrDefault(key, fallback);
        if (!(value instanceof String text) || text.length() > max) { invalid(); return ""; }
        return text;
    }
    private static boolean bool(Map<String,Object> args, String key, boolean fallback) {
        Object value = args.getOrDefault(key, fallback);
        if (!(value instanceof Boolean)) invalid();
        return (Boolean) value;
    }
    private static long page(Map<String,Object> args) {
        Object value = args.getOrDefault("page", 1L);
        if (!(value instanceof Long number) || number < 1 || number > 1000) invalid();
        return (Long)value;
    }
    private static List<String> strings(Object value, int count, int size) {
        if (!(value instanceof List<?> raw) || raw.size() > count) { invalid(); return List.of(); }
        List<String> result = new ArrayList<>();
        for (Object item : (List<?>)value) {
            if (!(item instanceof String text) || text.isEmpty() || text.length() > size) invalid();
            result.add((String)item);
        }
        return result;
    }
    private static Map<String,Object> result(String raw) {
        if (raw == null || raw.getBytes(StandardCharsets.UTF_8).length > LIMIT) throw new ProviderFailure("invalid-provider-response");
        try { return object(Json.parse(raw)); }
        catch (Exception e) { throw new ProviderFailure("invalid-provider-response"); }
    }
    private static Map<String,Object> invoke(Spider spider, String method, Map<String,Object> args) throws Exception {
        return switch (method) {
            case "home" -> {
                Map<String,Object> home = new LinkedHashMap<>(result(spider.homeContent(bool(args,"filter",true))));
                if (!(home.get("list") instanceof List<?> list) || list.isEmpty()) {
                    String fallback = spider.homeVideoContent();
                    if (fallback != null && !fallback.isBlank()) home.put("list", result(fallback).getOrDefault("list", List.of()));
                }
                yield home;
            }
            case "category" -> {
                String tid = string(args,"categoryId",256,"");
                if (tid.isEmpty()) invalid();
                Map<String,Object> values = object(args.getOrDefault("filters",Map.of()));
                if (values.size() > 32) invalid();
                HashMap<String,String> filters = new HashMap<>();
                for (Map.Entry<String,Object> e : values.entrySet()) {
                    if (e.getKey().length() > 64 || !(e.getValue() instanceof String text) || text.length() > 512) invalid();
                    filters.put(e.getKey(), (String)e.getValue());
                }
                yield result(spider.categoryContent(tid,Long.toString(page(args)),bool(args,"filter",true),filters));
            }
            case "search" -> {
                String query=string(args,"query",200,"");
                if (query.isBlank()) invalid();
                long page=page(args);
                boolean paged=spider.getClass().getMethod("searchContent",String.class,boolean.class,String.class).getDeclaringClass()!=Spider.class;
                if (!paged && page!=1) throw new ProviderFailure("unsupported-pagination");
                yield result(paged ? spider.searchContent(query,bool(args,"quick",false),Long.toString(page))
                                  : spider.searchContent(query,bool(args,"quick",false)));
            }
            case "detail" -> {
                List<String> ids=strings(args.get("ids"),20,1024);
                if (ids.isEmpty()) invalid();
                yield result(spider.detailContent(ids));
            }
            case "player" -> {
                String id=string(args,"id",2048,"");
                if (id.isEmpty()) invalid();
                yield result(spider.playerContent(string(args,"flag",256,""), id,
                    strings(args.getOrDefault("vipFlags",List.of()),32,256)));
            }
            default -> throw new ProviderFailure("unsupported-method");
        };
    }

    public static void main(String[] ignored) {
        PrintStream protocol=System.out;
        // Plugin prints never become protocol output, error details or host logs.
        System.setOut(new PrintStream(OutputStream.nullOutputStream()));
        System.setErr(new PrintStream(OutputStream.nullOutputStream()));
        Map<String,Object> output;
        int exit=0;
        try {
            byte[] input=System.in.readNBytes(LIMIT+1);
            if (input.length>LIMIT) throw new ProviderFailure("request-too-large");
            Map<String,Object> request;
            try {
                String json=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(input)).toString();
                request=object(Json.parse(json));
            } catch (Exception e) { throw new ProviderFailure("invalid-request"); }
            if (!request.keySet().equals(Set.of("version","provider","method","args")) ||
                !(request.get("version") instanceof Long version) || version!=2L) invalid();
            String method=string(request,"method",32,"");
            if (!METHODS.contains(method)) throw new ProviderFailure("unsupported-method");
            String provider=string(request,"provider",64,"");
            Map<String,Object> args=object(request.get("args"));
            Map<String,Object> data;
            ApprovedSpiderLoader loader = new ApprovedSpiderLoader(provider,string(args,"extend",2048,""));
            try { data=invoke(loader.spider,method,args); }
            finally {
                try { loader.close(); }
                catch (Throwable e) { throw new ProviderFailure("provider-cleanup-failed"); }
            }
            output=Map.of("version",2,"status","ok","runtime","java-spider","data",data);
            if (Json.stringify(output).getBytes(StandardCharsets.UTF_8).length>LIMIT) throw new ProviderFailure("output-too-large");
        } catch (Throwable error) {
            for (int i=0; i<4 && error instanceof java.lang.reflect.InvocationTargetException wrapped; i++) {
                if (wrapped.getTargetException()==null) break;
                error=wrapped.getTargetException();
            }
            String code=error instanceof ProviderFailure && ERRORS.contains(error.getMessage()) ? error.getMessage() :
                error instanceof LinkageError ? "unsupported-api" :
                error instanceof OutOfMemoryError ? "provider-resource-limit" : "provider-execution";
            // Code is selected locally; exceptions and reflection targets are not serialized.
            output=Map.of("version",2,"status","error","code",code);
            exit=2;
        }
        protocol.println(Json.stringify(output));
        protocol.flush();
        System.exit(exit);
    }
}
