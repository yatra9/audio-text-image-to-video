libav.js AAC/MP3 single-HTML builder for Windows + WSL
======================================================

使い方
------
1. このフォルダを、書き込み可能な場所へ解凍します。
2. build.cmd をダブルクリックするか、PowerShellで build.ps1 を実行します。
3. 管理者権限の確認(UAC)が出たら許可します。
4. 初回だけ、WSL自体が未導入ならWindows再起動を要求される場合があります。
   その場合は再起動後、もう一度 build.cmd / build.ps1 を実行します。
5. 完了すると、このフォルダ直下に次のファイルができます。

   webcodecs-libav-slides-v8.1-aac-mp3-offline.html

   これは libav.js のJS、AAC/MP3対応カスタムWASM、出力mux用libav.js、
   WebCodecs bridgeを内部に埋め込んだ単一HTMLです。

WSL
---
現在のWSLで次の名前のDebianを作成します。

   libav-wasm-dev

既に存在する場合は再利用します。ビルドキャッシュはWSL内の
/opt/libav-wasm-dev に残すので、2回目以降は初回より速くなります。

ビルド内容
----------
libav.js: v5.4.6.1.1
Emscripten: 3.1.55（このlibav.jsリリースのupstream CIと同じ）

カスタムvariantはupstreamの obsolete と aac-af の構成を合成します。
主な機能:
- MP3 decode/demux
- AAC decode + raw AAC/ADTS
- MP4/M4A demux
- Opus encode/decode
- FLAC/WAV
- audio filters / resample
- WebM mux

ネット接続
----------
ビルド時には必要です。git clone、Emscripten、FFmpeg等のsource、npm packageを取得します。
完成した単一HTMLの使用時には、これらの外部ライブラリ取得は不要です。

ライセンス注意
--------------
libav.js/FFmpeg等のライセンス条件は、完成HTMLを第三者へ配布する場合にも適用されます。
特にlibav.js upstreamは、compiled versionを配布する場合に対応sourceを提供する必要があると
説明しています。ビルドに使ったsource checkoutはWSL内 /opt/libav-wasm-dev/libav.js に残ります。
AAC等については、利用地域・用途に応じて特許/ライセンス面も各自確認してください。

削除
----
ビルド環境が不要になったら、管理者PowerShellで:

   wsl --unregister libav-wasm-dev

を実行すると専用Debianを削除できます。


v1.1 note
---------
build.ps1 and build.cmd are intentionally ASCII-only.
This avoids Windows PowerShell 5.1 source-encoding corruption on Japanese Windows.
If v1.0 produced mojibake such as "縺...", delete that copy and use this v1.1 folder.


v1.2 note
---------
If WSL_E_VM_MODE_INVALID_STATE appears, build.ps1 now enables:
- Microsoft-Windows-Subsystem-Linux
- VirtualMachinePlatform
- hypervisorlaunchtype=auto
- WSL default version 2

If Windows needs a reboot, the script exits with a reboot message instead of
reporting BUILD FAILED. After reboot, run build.cmd again. The existing
libav-wasm-dev Debian installation is reused.


v1.3 note
---------
Fixed Windows-to-WSL project path conversion.
The script no longer passes C:\... through wslpath, because some wsl.exe
command-line paths lose their backslashes. It converts drive-letter paths
directly, for example:
    C:\Users\name\project -> /mnt/c/Users/name/project


v1.4 note
---------
Fixed npm dependency installation for libav.js v5.4.6.1.1.
That upstream tag has no package-lock.json, so a fresh checkout must use:
    npm install --no-audit --no-fund
The builder now uses npm ci only if a lock file actually exists.
The existing /opt/libav-wasm-dev/libav.js checkout is reused.


v1.5 note
---------
App version: v8.2.0
Final output file: index.html

Audio File/Blob input no longer uses mkreadaheadfile. It now uses the libav.js
block-reader device API:
    mkblockreaderdev + onblockread + ff_block_reader_dev_send

This follows the upstream libav.js demuxing block-device test and avoids the
"Invalid data found when processing input" / "Could not open source file"
failure seen in the first custom AAC/MP3 build.


v1.6 note
---------
Builder ZIP version and app version are now both v1.6.
Final output remains index.html.

Fixed block-reader callback path handling:
- Do not compare callback requestedName with the original device name.
- Send data back using the callback's requestedName, matching libav.js upstream.
- Log the first block-read request to the browser console for diagnostics.


v1.7 note
---------
Builder and app version: v1.7
Output: index.html

Audio input changes:
1. Block-reader callback now exactly follows libav.js documentation:
   ff_block_reader_dev_send() is NOT awaited or returned.
2. If block-reader open still fails, the app automatically retries by loading
   the File into libav's simple virtual filesystem with writeFile().
3. The build verifies that the custom FFmpeg configuration contains MP3/AAC
   demuxers/decoders, WebM muxer, and libopus encoder.


v1.8 note
---------
Builder version and app version are both v1.8.
Final output is index.html.

Major architecture change:
- The merged custom input variant was removed.
- MP3 / Opus / FLAC / WAV use the upstream "obsolete" variant unchanged.
- AAC / ADTS / M4A / MP4 use the upstream "aac-af" variant unchanged.
- Both locally-built WASM runtimes are embedded into the same index.html.
- The app selects the appropriate input runtime from the chosen file.

This makes the MP3 path match the known-good upstream obsolete configuration
instead of the custom merged configuration that returned AVERROR_INVALIDDATA.


v1.9 note
---------
Builder and app version: v1.9
Output: index.html

MP3 reliability change:
- MP3/Opus/FLAC/WAV no longer use a locally rebuilt obsolete runtime.
- build.cmd downloads and embeds the exact published libav.js@5.4.6
  libav-5.4.6.1.1-obsolete frontend/factory/WASM from UNPKG.
- This is the same published obsolete runtime family that successfully read
  MP3 in the earlier v8.0.4 offline prototype.
- AAC/ADTS/M4A remains a locally compiled upstream aac-af runtime.

The published files are cached under /opt/libav-wasm-dev/published-obsolete.


v1.10 note
----------
Builder and app version: v1.10
Output: index.html

Fixed v1.9 build failure:
- PUBLISHED_DIR incorrectly referenced undefined WORK_DIR.
- It now correctly uses the existing WORK_ROOT:
    /opt/libav-wasm-dev/published-obsolete


v1.11 note
----------
Builder and app version: v1.11
Output: index.html

MP3 path reset to the known-good v8.0.4 architecture:
- published obsolete frontend/factory/WASM
- mkreadaheadfile(File)
- ff_init_demuxer_file()
- the same createInputLibAV option shape used by v8.0.4
- AAC factory is NOT evaluated during MP3 startup; AAC initialization is lazy

The browser console also prints the first 16 bytes of the selected audio as:
    [v1.11 audio head]
This confirms the browser File itself contains the expected MP3/AAC header.


v1.13 note
----------
Builder and app version: v1.13
Output: index.html

MP3 runtime is now arranged in the exact v8.0.4 offline order:
  input frontend -> input factory -> input WASM wrapper
  output frontend -> output factory -> output WASM wrapper
  WebCodecs bridge
Only after that is AAC lazy support registered.

Other changes:
- Removed strict mode from the embedded runtime wrapper.
- Reverted MP3 input to the original File + mkreadaheadfile path.
- Added [v1.13 libav diagnostic] console output.


v1.14 note
----------
Builder and app version: v1.14
Output: index.html

Important architecture correction:
The only confirmed working baseline is the ONLINE v8.0.4 edition.

v1.14 follows its native libav.js loading path:
  frontend.LibAV({
    toImport: <factory JavaScript URL>,
    wasmurl: <WASM URL>
  })

For offline use, factory JavaScript and WASM are embedded as Base64 and exposed
through local blob: URLs. The factory is no longer eval'ed and injected through
a custom factory option.

The libav frontend JavaScript itself is emitted as a normal inline <script>
instead of eval(), matching normal browser script execution more closely.


v1.15 note
----------
Builder and app version: v1.15
Output: index.html

The working ONLINE v8.0.4 input initialization was checked directly.
It does not pass noes6:true or nosimd:true.

v1.15 input initialization is now:
  LibAV({
    noworker: true,
    toImport: <embedded factory blob URL>,
    wasmurl: <embedded WASM blob URL>
  })

New diagnostic:
  [v1.15 libav diagnostic]

It performs actual runtime lookups for:
  av_find_input_format("mp3")
  avcodec_find_decoder_by_name("mp3")
  avcodec_find_decoder_by_name("mp3float")

A non-zero numeric result means that component is actually registered in WASM.


v1.16 note
----------
Builder and app version: v1.16
Output: index.html

MP3 now uses a locally built upstream obsolete runtime, loaded through the
native toImport/wasmurl path. The build verifies the obsolete config enables
the MP3 demuxer and decoder. The browser also performs a runtime self-check.


v1.17 note
----------
Builder and app version: v1.17
Output: index.html

Critical frontend isolation fix:
libav.js frontend scripts use the global LibAV object. Loading a second frontend
without clearing that global can mutate/replace fields on the first frontend.

v1.17 now does:
  1. load obsolete input frontend
  2. save its object as window.LibAVInput54
  3. set window.LibAV = undefined
  4. load output frontend, forcing a new independent object
  5. assert LibAVInput54 !== LibAVOutput

The console diagnostic now includes:
  inputFrontVER / inputFrontCONFIG
  outputFrontVER / outputFrontCONFIG
  sameFrontendObject

For a correct build:
  sameFrontendObject must be false
  inputFrontCONFIG should identify obsolete
  outputFrontCONFIG should identify webcodecs


v1.18 note
----------
Builder and app version: v1.18
Output: index.html

Fixed video-generation startup:
The audio probe path had already been migrated to:
    createInputLibAV(inputFactory)
but makeVideo() still called the old:
    inputFactory.LibAV(...)

In v1.17 inputFactory is a descriptor object with:
    front / toImport / wasmurl
so inputFactory.LibAV is intentionally not a function.

v1.18 makes probe and makeVideo use the same createInputLibAV() path.


v1.19 note
----------
Builder and app version: v1.19
Output: index.html

Fix for video-generation hang:
The audio pipeline uses:
    aresample=48000,asetnsamples=n=<opus frame size>:p=1

The locally built obsolete runtime had aresample but did not include
the asetnsamples filter, causing:
    No such filter: 'asetnsamples'
    Error creating filters

v1.19 explicitly adds:
    --enable-filter=asetnsamples
to the obsolete FFmpeg config and force-rebuilds the obsolete dist files.

The existing EAGAIN handling is unchanged.


v1.20 note
----------
Builder and app version: v1.20
Output: index.html

Fix for v1.19 patch failure:
- The force-build flag was removed.
- Generated libav.js build/ artifacts are deleted before rebuilding so FFmpeg,
  LAME, and other dependency patches are applied to fresh extracted sources.
- asetnsamples remains explicitly enabled.
- A normal make is used; upstream ffmpeg.mk already tracks ffmpeg-config.txt
  as a configure dependency.


v1.21 note
----------
Builder and app version: v1.21
Output: index.html

AAC video-generation fix:
The AAC input runtime (aac-af) was missing the same asetnsamples filter that
was added to obsolete for MP3.

v1.21 now adds:
    --enable-filter=asetnsamples
to both obsolete and aac-af configurations.

The aac-af dist files are deleted before a normal make so the AAC runtime is
rebuilt with the filter. make -B is NOT used.


v1.22 note
----------
Builder and app version: v1.22
Output: index.html

File picker fix:
- Changed audio input accept from audio/* to audio/*,.aac
- Windows file dialogs may not map raw .aac into audio/*, so the extension is now explicit.
