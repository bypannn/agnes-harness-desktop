# libvips codec provenance and source access

The unmodified application payload contains `@img/sharp-libvips-darwin-arm64` 1.2.4, used through sharp 0.34.5. Its package manifest declares LGPL-3.0-or-later. The library is a separate dynamically loaded file at:

`Contents/Resources/runtime/node_modules/@img/sharp-libvips-darwin-arm64/lib/libvips-cpp.8.17.3.dylib`

The desktop shell's Apache-2.0 license does not replace this library's license. There is no restriction in this project on modification of LGPL components or reverse engineering for debugging such modifications. Replacing a library will invalidate the local application signature, which must be regenerated for local use.

The npm package's recorded source revision is `20b5e899954907a3039d6e3d4c200aaa0ec52c4c` in lovell/sharp-libvips. The following upstream materials provide the corresponding dependency versions, source download locations, patches and build instructions:

- [Package metadata](https://registry.npmjs.org/@img%2fsharp-libvips-darwin-arm64/1.2.4)
- [Build source at the recorded revision](https://github.com/lovell/sharp-libvips/tree/20b5e899954907a3039d6e3d4c200aaa0ec52c4c)
- [Download that build source](https://codeload.github.com/lovell/sharp-libvips/tar.gz/20b5e899954907a3039d6e3d4c200aaa0ec52c4c)
- [Pinned source downloads and patches](https://github.com/lovell/sharp-libvips/blob/20b5e899954907a3039d6e3d4c200aaa0ec52c4c/build/posix.sh)
- [Version pins](https://github.com/lovell/sharp-libvips/blob/20b5e899954907a3039d6e3d4c200aaa0ec52c4c/versions.properties)
- [libvips 8.17.3 source](https://github.com/libvips/libvips/releases/download/v8.17.3/vips-8.17.3.tar.xz)
- [sharp 0.34.5 source](https://github.com/lovell/sharp/tree/v0.34.5)

`versions.json` in this directory records the versions from the distributed binary package; `THIRD-PARTY-NOTICES.md` retains the upstream dependency and license table. GPLv3 and LGPLv3 license texts accompany this document. The application resources also retain the Agnes, Node.js and other bundled component notices.

The Release provides a separate copy of the upstream build-source archive, `sharp-libvips-1.2.4-build-source.tar.gz`, alongside the application download. This is the upstream build recipe repository; the library source download URLs and patches it uses are recorded in its scripts.
