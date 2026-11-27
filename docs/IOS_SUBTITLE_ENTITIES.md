# Native iOS subtitle entity compatibility

The owned SRT/WebVTT parser now decodes decimal (`&#20013;`) and hexadecimal (`&#x6587;`) Unicode character references, plus the common named references `&quot;`, `&apos;` and `&nbsp;`. Existing `&amp;`, `&lt;` and `&gt;` handling remains. This improves rendering of provider-generated text-only subtitles without requiring an external HTML parser.

Only valid Unicode scalars outside the control-character set are decoded. Invalid numeric references (surrogates, out-of-range values, controls, malformed digits) remain literal. The existing 1 MiB file bound, 5,000-cue cap, and 2,000-character cue limit still apply. No HTML execution, network loading, remote plugins or new source bundles are introduced.

Unit coverage: `NativeCaptionTests.testNumericAndNamedEntitiesInWebVTTAndSRT` and `testMalformedNumericEntitiesRemainLiteralAndCannotInjectControls`. Xcode/iPhone/iPad simulator tests and complete CI are required before merge; this PR does not claim physical-device compatibility.
