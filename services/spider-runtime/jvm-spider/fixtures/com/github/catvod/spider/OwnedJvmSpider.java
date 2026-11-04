package com.github.catvod.spider;

import com.github.catvod.crawler.Spider;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Original TV-Next-owned GPL fixture, not a downloaded third-party provider. */
public class OwnedJvmSpider extends Spider {
    @Override public String homeContent(boolean filter) {
        return json(Map.of("class", List.of(Map.of("type_id", "owned", "type_name", "Owned")),
            "list", List.of(Map.of("vod_id", "opaque$1", "vod_name", "Owned reference")),
            "filter", filter, "siteKey", siteKey));
    }
    @Override public String categoryContent(String tid, String pg, boolean filter, HashMap<String, String> extend) {
        return json(Map.of("list", List.of(), "page", Integer.parseInt(pg), "category", tid, "filters", extend));
    }
    @Override public String detailContent(List<String> ids) {
        return json(Map.of("list", List.of(Map.of("vod_id", ids.get(0), "vod_name", "Owned detail",
            "vod_play_from", "Owned", "vod_play_url", "Episode$https://example.invalid/owned.mp4")), "ids", ids));
    }
    @Override public String searchContent(String key, boolean quick) {
        return json(Map.of("list", List.of(), "query", key, "quick", quick, "overload", "legacy"));
    }
    @Override public String playerContent(String flag, String id, List<String> vipFlags) {
        return json(Map.of("url", "https://example.invalid/owned.mp4", "parse", 0, "flag", flag, "id", id, "vipFlags", vipFlags));
    }

    protected static String json(Object value) {
        if (value instanceof String s) {
            StringBuilder out = new StringBuilder("\"");
            for (char c : s.toCharArray()) {
                if (c == '"' || c == '\\') out.append('\\').append(c);
                else if (c < 32) out.append(String.format("\\u%04x", (int)c));
                else out.append(c);
            }
            return out.append('"').toString();
        }
        if (value instanceof Map<?, ?> m) return "{" + String.join(",", m.entrySet().stream()
            .map(e -> json(e.getKey()) + ":" + json(e.getValue())).toList()) + "}";
        if (value instanceof List<?> l) return "[" + String.join(",", l.stream().map(OwnedJvmSpider::json).toList()) + "]";
        if (value instanceof Boolean || value instanceof Number) return value.toString();
        throw new IllegalArgumentException();
    }
}
