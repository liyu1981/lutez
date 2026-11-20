# CommonMark spec corpus

`commonmark-spec.json` is copied verbatim from the pinned upstream submodule
(`v1.7.8`, `56b87cda10fb394981849aa8de19b8491aea62b4`):

    upstream/lute/test/commonmark-spec.json

- 652 examples, CommonMark 0.31.2.
- SHA-256: `d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20`
- Upstream file is MIT/CC-BY-SA-4.0 licensed; see the upstream `test/commonmark-spec.md`
  header. This copy is test data only and is not linked into `liblutez`.

Do not hand-edit. Refresh from the pinned submodule and update the SHA above:

    git submodule update --init
    cp upstream/lute/test/commonmark-spec.json test/spec/commonmark-spec.json
    sha256sum test/spec/commonmark-spec.json

See `doc/UPSTREAM.md` “Bump procedure” for when this is required.
