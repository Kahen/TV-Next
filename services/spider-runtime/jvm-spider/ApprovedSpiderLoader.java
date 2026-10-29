import com.github.catvod.crawler.Spider;
import java.io.IOException;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;

/** A fixed image-owned registry, never a caller-supplied path/class or upload. */
final class ApprovedSpiderLoader implements AutoCloseable {
    private static final Map<String, String> VARIANTS = Map.ofEntries(
        Map.entry("owned-paged", "Paginated"), Map.entry("owned-fallback", "HomeFallback"),
        Map.entry("owned-throwing", "Throwing"), Map.entry("owned-invalid", "BadOutput"),
        Map.entry("owned-cleanup", "DestroyFailure"), Map.entry("owned-timeout", "Timeout"),
        Map.entry("owned-output", "Output"), Map.entry("owned-oom", "OutOfMemory"),
        Map.entry("owned-processes", "Processes"), Map.entry("owned-policy", "Policy"));
    private final URLClassLoader classes;
    final Spider spider;

    ApprovedSpiderLoader(String provider, String extend) throws Exception {
        String entry = "com.github.catvod.spider.OwnedJvmSpider";
        if (!provider.equals("owned-reference")) {
            if (!"1".equals(System.getenv("TVNEXT_TEST_HOOKS")) || !VARIANTS.containsKey(provider)) {
                throw new ProviderFailure("provider-not-approved");
            }
            entry = "com.github.catvod.spider.OwnedVariants$" + VARIANTS.get(provider);
        }
        Path jar = Path.of("/worker/approved.jar");
        if (Files.size(jar) > 16 * 1024 * 1024) throw new ProviderFailure("jar-integrity");
        Map<?, ?> manifest = (Map<?, ?>) Json.parse(Files.readString(Path.of("/worker/approved.json")));
        if (!"pure-jvm-candidate".equals(manifest.get("status"))) throw new ProviderFailure("jar-preflight");
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(jar));
        if (!(manifest.get("sha256") instanceof String expected) || !expected.matches("[a-f0-9]{64}") ||
            !MessageDigest.isEqual(digest, HexFormat.of().parseHex(expected))) throw new ProviderFailure("jar-integrity");
        classes = new URLClassLoader(new URL[] { jar.toUri().toURL() }, ClassLoader.getPlatformClassLoader()) {
            @Override protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
                // Share exactly the host contract. Provider-owned classes cannot
                // shadow it or load the default-package worker/JSON implementation.
                if (name.equals("com.github.catvod.crawler.Spider") || name.equals("android.content.Context")) {
                    return ApprovedSpiderLoader.class.getClassLoader().loadClass(name);
                }
                return super.loadClass(name, resolve);
            }
        };
        Spider candidate = null;
        try {
            candidate = Class.forName(entry, true, classes).asSubclass(Spider.class).getConstructor().newInstance();
            candidate.siteKey = provider;
            candidate.init(null, extend); // No Android Context instance is supplied.
            spider = candidate;
        } catch (Throwable failure) {
            if (candidate != null) {
                try { candidate.destroy(); } catch (Throwable ignored) { }
            }
            classes.close();
            throw failure;
        }
    }

    @Override public void close() throws IOException {
        try { spider.destroy(); }
        finally { classes.close(); }
    }
}
