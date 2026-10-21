/** Bounded provider failure code; implementation details must not reach stdout. */
public final class ProviderFailure extends RuntimeException {
    public ProviderFailure(String code) { super(code); }
}
