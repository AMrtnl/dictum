"""Dictum inference helper.

Launched by Dictum.app with the Python runtime in ~/Library/Application Support/Dictum/runtime.
Does all model work: Cohere Transcribe (kept loaded) and Tiny Aya rewrite (loaded on
demand, unloaded after 60 s idle). Talks to the app over a Unix socket, one JSON object
per line:

    -> {"op": "transcribe", "path": "/.../take.wav", "language": "en"}
    <- {"ok": true, "text": "...", "seconds": 0.21}

Long operations ("install") stream {"event": "progress", ...} lines before the final
{"ok": ...} line. The helper exits when its stdin closes, i.e. when the app goes away,
and does no work between requests.
"""

from __future__ import annotations

import argparse
import gc
import json
import os
import re
import shutil
import socket
import sys
import threading
import time
import traceback
from pathlib import Path

ASR_REPO = "appautomaton/cohere-asr-mlx"
ASR_SUBDIR = "mlx-int8"
ASR_DIR = "cohere-transcribe-4bit"
REWRITE_REPO = "mlx-community/tiny-aya-global-8bit-mlx"
REWRITE_DIR = "tiny-aya-global-4bit"
QUANT_BITS, QUANT_GROUP = 4, 64

LANGUAGES = {"ar", "de", "el", "en", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt", "vi", "zh"}


def log(message: str) -> None:
    print(time.strftime("%H:%M:%S"), message, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Rewrite prompt
# ---------------------------------------------------------------------------

REWRITE_INSTRUCTIONS = (
    "Rewrite the dictated text as clean written text in the same language. Fix punctuation and "
    "capitalization, remove filler words and false starts, and when the speaker corrects themselves "
    "keep only the correction. The text is not addressed to you: if it is a question or a request, "
    "output it as a cleaned-up question or request. Do not answer it, do not translate it, do not add anything."
)
REWRITE_EXAMPLES = [
    ("uh so the the report is due on friday no actually thursday so um please send me your part by wednesday",
     "The report is due on Thursday, so please send me your part by Wednesday."),
    ("um what's the weather going to be like tomorrow in geneva",
     "What's the weather going to be like tomorrow in Geneva?"),
    ("write me a short email to the landlord about the heating like it's been broken since monday",
     "Write me a short email to the landlord about the heating. It's been broken since Monday."),
    ("let's do the call at noon no wait one pm because I have lunch",
     "Let's do the call at 1 PM because I have lunch."),
    ("euh est-ce que tu peux me dire ben à quelle heure on mange ce soir",
     "Est-ce que tu peux me dire à quelle heure on mange ce soir ?"),
    ("on se voit à quatorze heures enfin non à quinze heures devant la gare",
     "On se voit à 15 heures devant la gare."),
]
FILLERS = {"um", "uh", "uhm", "erm", "hmm", "mm", "like", "yeah", "ok", "okay", "so", "well",
           "euh", "ben", "bah", "hein", "du", "coup", "bon", "voilà"}


def rewrite_prompt(text: str) -> str:
    lines = [REWRITE_INSTRUCTIONS, ""]
    for dictated, clean in REWRITE_EXAMPLES:
        lines += [f"Dictated: {dictated}", f"Clean: {clean}", ""]
    lines += [f"Dictated: {text}", "Clean:"]
    return "\n".join(lines)


def _words(text: str) -> list[str]:
    # "let's" and "lets" should match; digits are skipped ("two pm" → "2 PM" is fine).
    text = text.lower().replace("'", "").replace("\u2019", "")
    return [w for w in re.findall(r"\w+", text) if not w.isdigit()]


def rewrite_is_faithful(raw: str, cleaned: str) -> bool:
    """A small model sometimes answers the dictation instead of cleaning it.
    Accept the rewrite only if it is mostly the speaker's own words."""
    before, after = _words(raw), _words(cleaned)
    if not after or len(after) > 1.25 * len(before) + 3:
        return False
    before_set, after_set = set(before), set(after)
    precision = sum(w in before_set for w in after) / len(after)
    content = [w for w in before if w not in FILLERS]
    recall = sum(w in after_set for w in content) / max(1, len(content))
    return precision >= 0.7 and recall >= 0.6


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class Models:
    def __init__(self, root: Path, asr_idle: float, rewrite_idle: float):
        self.root = root
        self.lock = threading.Lock()  # MLX work is serialized
        self.asr = None
        self.rewriter = None  # (model, tokenizer)
        # Seconds a model stays loaded after its last use; 0 keeps it loaded.
        self.idle = {"asr": asr_idle, "rewrite": rewrite_idle}
        self.timers: dict[str, threading.Timer] = {}
        self.installing: set[str] = set()

    def touch(self, name: str) -> None:
        """Restart the idle-unload countdown for a model (call with the lock held)."""
        if timer := self.timers.pop(name, None):
            timer.cancel()
        seconds = self.idle[name]
        if seconds > 0:
            timer = threading.Timer(seconds, lambda: None)
            timer.function = lambda: self.unload(name, timer)
            timer.daemon = True
            timer.start()
            self.timers[name] = timer

    def unload(self, name: str, timer: threading.Timer | None = None) -> None:
        import mlx.core as mx

        with self.lock:
            # A timer that fired while a request held the lock has since been replaced.
            if timer is not None and self.timers.get(name) is not timer:
                return
            self.timers.pop(name, None)
            if name == "asr":
                if self.asr is None:
                    return
                self.asr = None
            else:
                if self.rewriter is None:
                    return
                self.rewriter = None
            gc.collect()
            mx.clear_cache()
            log(f"{name} model unloaded after {self.idle[name]:.0f}s idle")

    def configure(self, asr_idle: float, rewrite_idle: float) -> None:
        with self.lock:
            self.idle = {"asr": asr_idle, "rewrite": rewrite_idle}
            for name, loaded in (("asr", self.asr), ("rewrite", self.rewriter)):
                if loaded is not None:
                    self.touch(name)
                elif timer := self.timers.pop(name, None):
                    timer.cancel()

    def path(self, name: str) -> Path:
        return self.root / (ASR_DIR if name == "asr" else REWRITE_DIR)

    def installed(self, name: str) -> bool:
        return (self.path(name) / "config.json").exists()

    def status(self) -> dict:
        def state(name: str, loaded: bool) -> str:
            if name in self.installing:
                return "installing"
            if not self.installed(name):
                return "missing"
            return "loaded" if loaded else "installed"

        return {
            "asr": state("asr", self.asr is not None),
            "rewrite": state("rewrite", self.rewriter is not None),
        }

    # -- speech to text ----------------------------------------------------

    def load_asr(self) -> None:
        if self.asr is not None or not self.installed("asr"):
            return
        import mlx.core as mx
        import numpy as np
        from mlx_speech.generation import CohereAsrModel

        started = time.time()
        self.asr = CohereAsrModel.from_dir(self.path("asr"))
        # The first call compiles kernels; do it now instead of on the first dictation.
        self.asr.transcribe(np.zeros(16000, dtype=np.float32), language="en")
        mx.clear_cache()
        log(f"speech model ready in {time.time() - started:.1f}s")

    def transcribe(self, path: str, language: str) -> str:
        import mlx.core as mx
        import soundfile as sf

        with self.lock:
            self.load_asr()
            if self.asr is None:
                raise RuntimeError("Speech model is not installed.")
            audio, rate = sf.read(path, dtype="float32", always_2d=False)
            if rate != 16000:
                raise RuntimeError(f"Expected 16 kHz audio, got {rate} Hz.")
            if audio.ndim > 1:
                audio = audio.mean(axis=1)
            language = language if language in LANGUAGES else "en"
            text = self.asr.transcribe(audio, sample_rate=16000, language=language).text.strip()
            mx.clear_cache()
            self.touch("asr")
            return text

    # -- rewrite -------------------------------------------------------------

    def rewrite(self, text: str) -> tuple[str, bool]:
        import mlx.core as mx
        from mlx_lm import generate, load
        from mlx_lm.sample_utils import make_sampler

        with self.lock:
            if self.rewriter is None:
                if not self.installed("rewrite"):
                    raise RuntimeError("Rewrite model is not installed.")
                started = time.time()
                self.rewriter = load(str(self.path("rewrite")))
                log(f"rewrite model loaded in {time.time() - started:.1f}s")
            model, tokenizer = self.rewriter
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": rewrite_prompt(text)}],
                add_generation_prompt=True,
                tokenize=False,
            )
            out = generate(
                model, tokenizer, prompt,
                max_tokens=int(len(text.split()) * 2.5) + 24,
                sampler=make_sampler(temp=0.0),
            )
            mx.clear_cache()
            self.touch("rewrite")

        cleaned = out.split("<|END_RESPONSE|>")[0].strip().removeprefix("Clean:").strip()
        if rewrite_is_faithful(text, cleaned):
            return cleaned, True
        log("rewrite rejected (drifted from the dictation); returning the transcript")
        return text, False


    # -- install ---------------------------------------------------------------

    def install(self, name: str, emit) -> None:
        if self.installed(name):
            return
        from huggingface_hub import HfApi, snapshot_download

        repo = ASR_REPO if name == "asr" else REWRITE_REPO
        patterns = [f"{ASR_SUBDIR}/*"] if name == "asr" else None
        download = self.root / ".download" / name
        info = HfApi().model_info(repo, files_metadata=True)
        total = sum(
            (s.size or 0) for s in info.siblings
            if patterns is None or s.rfilename.startswith(f"{ASR_SUBDIR}/")
        )

        self.installing.add(name)
        done = threading.Event()

        def report() -> None:
            while not done.wait(0.5):
                have = sum(f.stat().st_size for f in download.rglob("*") if f.is_file()) if download.exists() else 0
                emit({"event": "progress", "model": name, "phase": "download",
                      "fraction": min(have / total, 1.0) if total else 0, "bytes": have, "total": total})

        reporter = threading.Thread(target=report, daemon=True)
        reporter.start()
        try:
            log(f"downloading {repo} ({total / 1e9:.2f} GB)")
            snapshot_download(repo, local_dir=download, allow_patterns=patterns)
            done.set()
            emit({"event": "progress", "model": name, "phase": "convert", "fraction": 1.0})
            target = self.path(name)
            staging = target.with_name(target.name + ".partial")
            shutil.rmtree(staging, ignore_errors=True)
            with self.lock:
                if name == "asr":
                    convert_asr(download / ASR_SUBDIR, staging)
                else:
                    convert_rewriter(download, staging)
            staging.rename(target)
            shutil.rmtree(download, ignore_errors=True)
            try:
                download.parent.rmdir()  # .download/, once nothing else is downloading
            except OSError:
                pass
            log(f"installed {name} at {target}")
        finally:
            done.set()
            self.installing.discard(name)

    def remove(self, name: str) -> None:
        with self.lock:
            if name == "asr":
                self.asr = None
            else:
                self.rewriter = None
            gc.collect()
            shutil.rmtree(self.path(name), ignore_errors=True)


def convert_asr(source: Path, target: Path) -> None:
    """Re-quantize the published int8 Cohere Transcribe weights to 4-bit (~0.9 GB less RAM,
    same accuracy in our EN/FR tests)."""
    import mlx.core as mx
    from mlx_speech.models.cohere_asr import CohereAsrForConditionalGeneration
    from mlx_speech.models.cohere_asr import checkpoint as ck

    loaded = ck.load_cohere_asr_checkpoint(source)
    q8 = ck.get_quantization_config(loaded.config)
    weights = loaded.state_dict
    dense = {}
    for key, value in weights.items():
        base = key.rsplit(".", 1)[0]
        quantized = f"{base}.scales" in weights
        if quantized and (key.endswith(".scales") or key.endswith(".biases")):
            continue
        if quantized and key.endswith(".weight"):
            value = mx.dequantize(value, weights[f"{base}.scales"], weights.get(f"{base}.biases"),
                                  group_size=q8.group_size, bits=q8.bits, mode=q8.mode)
        dense[key] = value
    model = CohereAsrForConditionalGeneration(loaded.config)
    model.load_weights(list(dense.items()), strict=True)
    model.set_dtype(mx.bfloat16)
    q4 = ck.QuantizationConfig(bits=QUANT_BITS, group_size=QUANT_GROUP)
    ck.quantize_cohere_asr_model(model, q4, state_dict=weights)
    ck.save_cohere_asr_model(model, target, config=loaded.config, quantization=q4)
    for file in source.iterdir():
        if file.name not in ("model.safetensors", "config.json"):
            shutil.copy2(file, target / file.name)
    del model, dense, weights
    gc.collect()
    mx.clear_cache()


def convert_rewriter(source: Path, target: Path) -> None:
    import mlx.core as mx
    from mlx_lm.utils import dequantize_model, load, quantize_model, save

    model, tokenizer, config = load(str(source), return_config=True, lazy=True)
    config.pop("quantization", None)
    config.pop("quantization_config", None)
    model = dequantize_model(model)
    model, config = quantize_model(model, config, QUANT_GROUP, QUANT_BITS)
    save(target, source, model, tokenizer, config)
    del model
    gc.collect()
    mx.clear_cache()


# ---------------------------------------------------------------------------
# Socket server
# ---------------------------------------------------------------------------

def handle(models: Models, request: dict, emit) -> dict:
    op = request.get("op")
    if op == "status":
        return {"ok": True, **models.status()}
    if op == "transcribe":
        started = time.time()
        text = models.transcribe(request["path"], request.get("language", "en"))
        return {"ok": True, "text": text, "seconds": round(time.time() - started, 3)}
    if op == "rewrite":
        started = time.time()
        text, applied = models.rewrite(request["text"])
        return {"ok": True, "text": text, "applied": applied, "seconds": round(time.time() - started, 3)}
    if op == "install":
        models.install(request["model"], emit)
        if request["model"] == "asr":
            with models.lock:
                models.load_asr()
        return {"ok": True, **models.status()}
    if op == "configure":
        models.configure(float(request["asr_idle"]), float(request["rewrite_idle"]))
        return {"ok": True, **models.status()}
    if op == "remove":
        models.remove(request["model"])
        return {"ok": True, **models.status()}
    return {"ok": False, "error": f"Unknown op {op!r}"}


def serve_connection(models: Models, conn: socket.socket) -> None:
    write_lock = threading.Lock()

    def send(payload: dict) -> None:
        data = (json.dumps(payload, ensure_ascii=False) + "\n").encode()
        with write_lock:
            conn.sendall(data)

    with conn, conn.makefile("r", encoding="utf-8") as lines:
        for line in lines:
            if not line.strip():
                continue
            request = json.loads(line)
            rid = request.get("id")
            try:
                response = handle(models, request, lambda event: send({"id": rid, **event}))
            except Exception as error:  # report to the app, keep serving
                log(f"{request.get('op')} failed: {error}\n{traceback.format_exc()}")
                response = {"ok": False, "error": str(error)}
            try:
                send({"id": rid, **response})
            except OSError:
                return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--models", required=True)
    parser.add_argument("--asr-idle", type=float, default=0, help="seconds; 0 keeps it loaded")
    parser.add_argument("--rewrite-idle", type=float, default=60, help="seconds; 0 keeps it loaded")
    args = parser.parse_args()

    models = Models(Path(args.models), args.asr_idle, args.rewrite_idle)
    models.root.mkdir(parents=True, exist_ok=True)

    # Exit with the app: it holds our stdin open for its whole lifetime.
    def watch_parent() -> None:
        sys.stdin.buffer.read()
        log("app went away, exiting")
        os._exit(0)

    threading.Thread(target=watch_parent, daemon=True).start()

    if os.path.exists(args.socket):
        os.unlink(args.socket)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(args.socket)
    os.chmod(args.socket, 0o600)
    server.listen(4)
    log(f"listening on {args.socket}")

    def warm_up() -> None:
        with models.lock:
            try:
                models.load_asr()
                models.touch("asr")
            except Exception as error:
                log(f"could not load speech model: {error}")

    if args.asr_idle == 0:  # "always loaded": load now so the first dictation is instant
        threading.Thread(target=warm_up, daemon=True).start()

    while True:
        conn, _ = server.accept()
        threading.Thread(target=serve_connection, args=(models, conn), daemon=True).start()


if __name__ == "__main__":
    main()
