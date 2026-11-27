# Native FongMi search target

The iPhone/iPad subscription screen now allows an explicit search target: all currently authorized/searchable sites (first 16 unique valid provider keys), or one chosen site. A chosen site beyond the default first-16 cap is reachable without issuing requests to the others. The selected key is an opaque provider identity, not a display name.

Selection affects only new cross-site searches. Failed-site retry continues to use the original request snapshot. A missing, hidden, unauthorized or malformed selected key fails closed without silently searching all providers. Loading another subscription resets the target to All. No remote Spider/JAR/JS/Python is executed by this feature.

Unit tests cover the default cap, duplicate keys, explicit late-provider selection and stale/malformed keys. Xcode simulator/CI must pass before merge; this is not real-provider acceptance.
