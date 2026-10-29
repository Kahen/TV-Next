package com.github.catvod.spider;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/** Owned negative/instrumentation fixtures, enabled only in diagnostic mode. */
public final class OwnedVariants {
    private OwnedVariants() {}
    public static class Paginated extends OwnedJvmSpider {
        @Override public String searchContent(String key, boolean quick, String page) {
            return json(Map.of("list", List.of(), "query", key, "quick", quick, "page", Integer.parseInt(page), "overload", "paged"));
        }
    }
    public static class HomeFallback extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) { return "{\"class\":[{\"type_id\":\"owned\",\"type_name\":\"Owned\"}]}"; }
        @Override public String homeVideoContent() { return "{\"list\":[{\"vod_id\":\"fallback\",\"vod_name\":\"Fallback\"}]}"; }
    }
    public static class Throwing extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) { throw new IllegalStateException("https://secret.invalid/?token=do-not-log"); }
    }
    public static class BadOutput extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) { return "not-json"; }
    }
    public static class DestroyFailure extends OwnedJvmSpider {
        @Override public void destroy() { throw new IllegalStateException("secret-cleanup-detail"); }
    }
    public static class Timeout extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) {
            try { Thread.sleep(60_000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            return super.homeContent(filter);
        }
    }
    public static class Output extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) {
            System.out.println("private-provider-stdout"); System.err.println("private-provider-stderr");
            return super.homeContent(filter);
        }
    }
    public static class OutOfMemory extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) { return new String(new byte[256 * 1024 * 1024]); }
    }
    public static class Processes extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) {
            try { for (int i=0; i<100; i++) new ProcessBuilder("sleep", "60").start(); }
            catch (IOException e) { throw new IllegalStateException(e); }
            throw new IllegalStateException("process quota was not enforced");
        }
    }
    public static class Policy extends OwnedJvmSpider {
        @Override public String homeContent(boolean filter) {
            try {
                boolean blocked;
                try (Socket socket = new Socket()) {
                    socket.connect(new InetSocketAddress("1.1.1.1", 53), 500); blocked = false;
                } catch (IOException e) { blocked = true; }
                boolean readonly;
                try { Files.writeString(Path.of("/worker/probe"), "x"); readonly = false; }
                catch (IOException e) { readonly = true; }
                boolean hidden;
                try { Class.forName("Json"); hidden = false; } catch (ClassNotFoundException e) { hidden = true; }
                String status = Files.readString(Path.of("/proc/self/status"));
                return json(Map.of("networkBlocked", blocked, "readonly", readonly, "workerClassesHidden", hidden,
                    "hostSecretVisible", System.getenv().containsKey("TVNEXT_HOST_SECRET_TEST"),
                    "nonroot", !status.contains("Uid:\t0\t"),
                    "memoryMax", Files.readString(Path.of("/sys/fs/cgroup/memory.max")).trim(),
                    "pidsMax", Files.readString(Path.of("/sys/fs/cgroup/pids.max")).trim()));
            } catch (IOException e) { throw new IllegalStateException(e); }
        }
    }
}
