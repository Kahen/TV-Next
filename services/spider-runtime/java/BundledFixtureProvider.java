import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Audited, compile-time bundled fixture. No plugin loading or network access. */
public final class BundledFixtureProvider implements ProviderSpi {
    @Override public String providerId() { return "bundled-fixture-v1"; }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> objects(Object value) {
        if (!(value instanceof List<?> raw)) throw new ProviderFailure("invalid-input");
        List<Map<String, Object>> output = new ArrayList<>();
        for (Object element : raw) {
            if (!(element instanceof Map<?, ?> map)) throw new ProviderFailure("invalid-input");
            for (Object key : map.keySet()) if (!(key instanceof String)) throw new ProviderFailure("invalid-input");
            output.add((Map<String, Object>) map);
        }
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

    @Override
    public Map<String, Object> handle(String method, Map<String, Object> args,
                                       Map<String, Object> catalog) {
        List<Map<String, Object>> categories = objects(catalog.get("categories"));
        List<Map<String, Object>> items = objects(catalog.get("items"));
        List<Map<String, Object>> summaries = items.stream().map(BundledFixtureProvider::summary).toList();

        if ("home".equals(method)) return Map.of("categories", categories, "items", summaries);
        if ("category".equals(method)) {
            String id = limited(args.get("categoryId"), 200);
            if (id.isEmpty()) throw new ProviderFailure("missing-category");
            return Map.of("categories", categories, "items", items.stream()
                .filter(x -> id.equals(x.get("categoryId")))
                .map(BundledFixtureProvider::summary).toList());
        }
        if ("search".equals(method)) {
            String query = limited(args.get("query"), 120).toLowerCase(Locale.ROOT);
            if (query.isEmpty()) throw new ProviderFailure("missing-query");
            return Map.of("items", items.stream()
                .filter(x -> {
                    Object name = x.get("name");
                    return name instanceof String text &&
                        text.toLowerCase(Locale.ROOT).contains(query);
                })
                .map(BundledFixtureProvider::summary).toList());
        }
        String id = limited(args.get("vodId"), 200);
        Map<String, Object> item = items.stream().filter(x -> id.equals(x.get("id")))
            .findFirst().orElseThrow(() -> new ProviderFailure("unknown-item"));
        if ("detail".equals(method)) return item;
        if (!"player".equals(method)) throw new ProviderFailure("unsupported-method");
        Object index = args.get("episodeIndex");
        List<Map<String, Object>> episodes = objects(item.get("episodes"));
        if (!(index instanceof Long n) || n < 0 || n >= episodes.size())
            throw new ProviderFailure("unknown-episode");
        return episodes.get(n.intValue());
    }
}
