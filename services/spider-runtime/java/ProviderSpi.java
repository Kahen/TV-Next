import java.util.Map;

/**
 * Pure-JVM, synchronous read-only provider contract, v1.
 *
 * This interface intentionally has no Android APIs, filesystem handles, network
 * client, dynamic class loading hooks, or mutable application Context.
 * Implementations are only bundled after source review at Docker image build time.
 */
public interface ProviderSpi {
    String providerId();

    Map<String, Object> handle(
        String method, Map<String, Object> arguments, Map<String, Object> fixture
    );
}
