import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

/** Owned integrity tests. This entry point does not initialize provider classes. */
public final class VerificationSmoke {
    private static void rejects(Path jar, Path report, String code) throws Exception {
        try { ApprovedSpiderLoader.verify(jar, report); throw new AssertionError("Accepted invalid pin"); }
        catch (ProviderFailure failure) { if (!code.equals(failure.getMessage())) throw failure; }
    }
    public static void main(String[] ignored) throws Exception {
        Path jar = Path.of("/worker/approved.jar"), report = Path.of("/worker/approved.json");
        ApprovedSpiderLoader.verify(jar, report);
        Path changedJar = Files.createTempFile("changed-", ".jar");
        Path changedReport = Files.createTempFile("changed-", ".json");
        try {
            byte[] bytes = Files.readAllBytes(jar);
            bytes[bytes.length - 1] ^= 1;
            Files.write(changedJar, bytes);
            rejects(changedJar, report, "jar-integrity");
            Files.writeString(changedReport, Json.stringify(Map.of("version",1,"status","unsupported","sha256","a".repeat(64))));
            rejects(jar, changedReport, "jar-preflight");
            Files.writeString(changedReport, Json.stringify(Map.of("version",1,"status","pure-jvm-candidate","sha256","../unapproved")));
            rejects(jar, changedReport, "jar-integrity");
            Files.writeString(changedReport, "not-json");
            rejects(jar, changedReport, "jar-preflight");
            System.out.println("JAR mutation, denied preflight and malformed pin rejection passed");
        } finally { Files.deleteIfExists(changedJar); Files.deleteIfExists(changedReport); }
    }
}
