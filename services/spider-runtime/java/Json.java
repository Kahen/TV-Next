import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** A small strict JSON codec for fixed local fixtures and bounded stdin messages only.
 * This is deliberately not a general Spider/JAR plugin loader. No reflection or eval.
 */
final class Json {
    private Json() {}

    static Object parse(String text) {
        Parser parser = new Parser(text);
        Object value = parser.value(0);
        parser.space();
        if (parser.index != text.length()) throw new IllegalArgumentException("trailing-input");
        return value;
    }

    static String stringify(Object value) {
        StringBuilder out = new StringBuilder();
        write(out, value, 0);
        return out.toString();
    }

    private static void write(StringBuilder out, Object value, int depth) {
        if (depth > 32) throw new IllegalArgumentException("nesting-limit");
        if (value == null) out.append("null");
        else if (value instanceof String str) {
            out.append('"');
            for (int i = 0; i < str.length(); i++) {
                char c = str.charAt(i);
                switch (c) {
                    case '"' -> out.append("\\\"");
                    case '\\' -> out.append("\\\\");
                    case '\b' -> out.append("\\b");
                    case '\f' -> out.append("\\f");
                    case '\n' -> out.append("\\n");
                    case '\r' -> out.append("\\r");
                    case '\t' -> out.append("\\t");
                    default -> {
                        if (c < 32) out.append(String.format("\\u%04x", (int) c));
                        else out.append(c);
                    }
                }
            }
            out.append('"');
        } else if (value instanceof Number || value instanceof Boolean) out.append(value);
        else if (value instanceof Map<?, ?> map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (!(entry.getKey() instanceof String)) throw new IllegalArgumentException("object-key");
                if (!first) out.append(',');
                write(out, entry.getKey(), depth + 1);
                out.append(':');
                write(out, entry.getValue(), depth + 1);
                first = false;
            }
            out.append('}');
        } else if (value instanceof List<?> items) {
            out.append('[');
            for (int i = 0; i < items.size(); i++) {
                if (i > 0) out.append(',');
                write(out, items.get(i), depth + 1);
            }
            out.append(']');
        } else throw new IllegalArgumentException("unserializable");
    }

    private static final class Parser {
        final String text;
        int index;
        Parser(String text) { this.text = text; }
        void space() {
            while (index < text.length()) {
                char c = text.charAt(index);
                if (c != ' ' && c != '\r' && c != '\n' && c != '\t') break;
                index++;
            }
        }
        boolean eat(char expected) {
            space();
            if (index < text.length() && text.charAt(index) == expected) {
                index++;
                return true;
            }
            return false;
        }
        void need(char c) {
            if (!eat(c)) throw new IllegalArgumentException("invalid-json");
        }
        Object value(int depth) {
            if (depth > 32) throw new IllegalArgumentException("nesting-limit");
            space();
            if (index >= text.length()) throw new IllegalArgumentException("invalid-json");
            char c = text.charAt(index);
            if (c == '"') return string();
            if (c == '{') {
                index++;
                Map<String, Object> obj = new LinkedHashMap<>();
                if (eat('}')) return obj;
                do {
                    space();
                    if (index >= text.length() || text.charAt(index) != '"')
                        throw new IllegalArgumentException("invalid-object-key");
                    String key = string();
                    need(':');
                    Object child = value(depth + 1);
                    if (obj.putIfAbsent(key, child) != null)
                        throw new IllegalArgumentException("duplicate-key");
                    // A duplicate with a null first value is still a duplicate.
                    if (child == null && obj.containsKey(key)) { /* null allowed */ }
                    if (eat('}')) return obj;
                    need(',');
                } while (true);
            }
            if (c == '[') {
                index++;
                List<Object> list = new ArrayList<>();
                if (eat(']')) return list;
                do {
                    list.add(value(depth + 1));
                    if (eat(']')) return list;
                    need(',');
                } while (true);
            }
            if (text.startsWith("true", index)) { index += 4; return true; }
            if (text.startsWith("false", index)) { index += 5; return false; }
            if (text.startsWith("null", index)) { index += 4; return null; }
            if (c == '-' || (c >= '0' && c <= '9')) return number();
            throw new IllegalArgumentException("invalid-json");
        }
        private Object number() {
            int start = index;
            if (text.charAt(index) == '-') index++;
            if (index >= text.length()) throw new IllegalArgumentException("invalid-number");
            if (text.charAt(index) == '0') index++;
            else {
                if (text.charAt(index) < '1' || text.charAt(index) > '9')
                    throw new IllegalArgumentException("invalid-number");
                while (index < text.length() && Character.isDigit(text.charAt(index))) index++;
            }
            boolean integer = true;
            if (index < text.length() && text.charAt(index) == '.') {
                integer = false;
                index++;
                int digits = index;
                while (index < text.length() && Character.isDigit(text.charAt(index))) index++;
                if (digits == index) throw new IllegalArgumentException("invalid-number");
            }
            if (index < text.length() && (text.charAt(index) == 'e' || text.charAt(index) == 'E')) {
                integer = false;
                index++;
                if (index < text.length() && (text.charAt(index) == '+' || text.charAt(index) == '-')) index++;
                int digits = index;
                while (index < text.length() && Character.isDigit(text.charAt(index))) index++;
                if (digits == index) throw new IllegalArgumentException("invalid-number");
            }
            String raw = text.substring(start, index);
            try {
                if (integer) return Long.parseLong(raw);
                double value = Double.parseDouble(raw);
                if (!Double.isFinite(value)) throw new IllegalArgumentException("invalid-number");
                return value;
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("invalid-number", e);
            }
        }
        private String string() {
            if (text.charAt(index++) != '"') throw new IllegalArgumentException("invalid-string");
            StringBuilder out = new StringBuilder();
            while (index < text.length()) {
                char c = text.charAt(index++);
                if (c == '"') return out.toString();
                if (c < 32) throw new IllegalArgumentException("control-character");
                if (c != '\\') { out.append(c); continue; }
                if (index >= text.length()) throw new IllegalArgumentException("invalid-escape");
                char escape = text.charAt(index++);
                switch (escape) {
                    case '"' -> out.append('"');
                    case '\\' -> out.append('\\');
                    case '/' -> out.append('/');
                    case 'b' -> out.append('\b');
                    case 'f' -> out.append('\f');
                    case 'n' -> out.append('\n');
                    case 'r' -> out.append('\r');
                    case 't' -> out.append('\t');
                    case 'u' -> {
                        if (index + 4 > text.length()) throw new IllegalArgumentException("invalid-unicode");
                        try { out.append((char) Integer.parseInt(text.substring(index, index + 4), 16)); }
                        catch (NumberFormatException e) { throw new IllegalArgumentException("invalid-unicode"); }
                        index += 4;
                    }
                    default -> throw new IllegalArgumentException("invalid-escape");
                }
            }
            throw new IllegalArgumentException("unterminated-string");
        }
    }
}
