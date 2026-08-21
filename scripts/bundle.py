#!/usr/bin/env python3
import argparse
import base64
import pathlib

def b64(path):
    return base64.b64encode(path.read_bytes()).decode("ascii")

def safe_inline_js(text):
    return text.replace("</script", r"<\/script")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True)
    ap.add_argument("--obsolete-front", required=True)
    ap.add_argument("--obsolete-factory", required=True)
    ap.add_argument("--obsolete-wasm", required=True)
    ap.add_argument("--aac-front", required=True)
    ap.add_argument("--aac-factory", required=True)
    ap.add_argument("--aac-wasm", required=True)
    ap.add_argument("--output-front", required=True)
    ap.add_argument("--output-factory", required=True)
    ap.add_argument("--output-wasm", required=True)
    ap.add_argument("--bridge", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    P = pathlib.Path
    template = P(args.template).read_text(encoding="utf-8")
    marker = "<!-- __EMBED_RUNTIME__ -->"
    if template.count(marker) != 1:
        raise SystemExit("ERROR: expected exactly one __EMBED_RUNTIME__ marker")

    input_front = safe_inline_js(P(args.obsolete_front).read_text(encoding="utf-8"))
    output_front = safe_inline_js(P(args.output_front).read_text(encoding="utf-8"))
    bridge = safe_inline_js(P(args.bridge).read_text(encoding="utf-8"))

    obsolete_factory_b64 = b64(P(args.obsolete_factory))
    obsolete_wasm_b64 = b64(P(args.obsolete_wasm))
    aac_factory_b64 = b64(P(args.aac_factory))
    aac_wasm_b64 = b64(P(args.aac_wasm))
    output_factory_b64 = b64(P(args.output_factory))
    output_wasm_b64 = b64(P(args.output_wasm))

    setup = '''<script>
window.__LIBAV_OFFLINE_EMBEDDED__ = true;
window.__APP_VERSION__ = "v1.33";

window.__libavB64Bytes = function(s) {
  const raw = atob(s);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
};
window.__libavBlobURL = function(b64, type) {
  return URL.createObjectURL(new Blob([window.__libavB64Bytes(b64)], {type}));
};
</script>'''

    input_front_block = "<script>\n" + input_front + "\n</script>"

    input_capture = '''<script>
// Critical: keep the input frontend object alive, then clear the global slot.
// The next frontend must create a DIFFERENT LibAV object instead of mutating
// the input frontend in place.
window.LibAVInput54 = window.LibAV;
window.__LIBAV_INPUT_IDENTITY__ = {
  VER: window.LibAVInput54 && window.LibAVInput54.VER,
  CONFIG: window.LibAVInput54 && window.LibAVInput54.CONFIG
};
window.LibAV = undefined;

window.__LIBAV_MP3_FACTORY_URL__ = window.__libavBlobURL("__MP3_FACTORY__", "text/javascript");
window.__LIBAV_MP3_WASM_URL__ = window.__libavBlobURL("__MP3_WASM__", "application/wasm");
window.__LIBAV_AAC_FACTORY_URL__ = window.__libavBlobURL("__AAC_FACTORY__", "text/javascript");
window.__LIBAV_AAC_WASM_URL__ = window.__libavBlobURL("__AAC_WASM__", "application/wasm");
</script>'''
    input_capture = (input_capture
        .replace("__MP3_FACTORY__", obsolete_factory_b64)
        .replace("__MP3_WASM__", obsolete_wasm_b64)
        .replace("__AAC_FACTORY__", aac_factory_b64)
        .replace("__AAC_WASM__", aac_wasm_b64))

    output_front_block = "<script>\n" + output_front + "\n</script>"

    output_capture = '''<script>
window.LibAVOutput = window.LibAV;
window.__LIBAV_OUTPUT_IDENTITY__ = {
  VER: window.LibAVOutput && window.LibAVOutput.VER,
  CONFIG: window.LibAVOutput && window.LibAVOutput.CONFIG
};
if (window.LibAVInput54 === window.LibAVOutput) {
  throw new Error("v1.33 runtime isolation failed: input/output LibAV frontend objects are identical");
}
window.__LIBAV_OUTPUT_FACTORY_URL__ = window.__libavBlobURL("__OUT_FACTORY__", "text/javascript");
window.__LIBAV_OUTPUT_WASM_URL__ = window.__libavBlobURL("__OUT_WASM__", "application/wasm");

const __outputOrig = window.LibAVOutput.LibAV.bind(window.LibAVOutput);
window.LibAVOutput.LibAV = (opts={}) => __outputOrig(Object.assign({}, opts, {
  noworker: true,
  toImport: window.__LIBAV_OUTPUT_FACTORY_URL__,
  wasmurl: window.__LIBAV_OUTPUT_WASM_URL__
}));
</script>'''
    output_capture = (output_capture
        .replace("__OUT_FACTORY__", output_factory_b64)
        .replace("__OUT_WASM__", output_wasm_b64))

    bridge_block = "<script>\n" + bridge + "\n</script>"

    runtime = setup + input_front_block + input_capture + output_front_block + output_capture + bridge_block

    out = P(args.out)
    out.write_text(template.replace(marker, runtime), encoding="utf-8", newline="\n")
    print("Created:", out)
    print("HTML size: %.2f MiB" % (out.stat().st_size / 1024 / 1024))

if __name__ == "__main__":
    main()
