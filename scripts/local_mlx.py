"""Offline inference shared by author sessions and the opt-in evaluator."""
import json
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Generation:
    text: str
    prompt_tokens: int
    generation_tokens: int
    reached_token_limit: bool


class OfflineMLX:
    """Load existing weights only; retain no prompts, outputs, or reports."""

    def __init__(self, path, seed=0):
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        path = Path(path).resolve(strict=True)
        config = json.loads((path / "config.json").read_text())
        if config.get("model_file") or config.get("auto_map"):
            raise RuntimeError("custom model code is outside this local runtime")
        import mlx.core as mx
        from mlx_lm import load
        if not mx.metal.is_available():
            raise RuntimeError("MLX Metal device is required")
        mx.set_default_device(mx.gpu)
        mx.random.seed(seed)
        self.mx = mx
        self.model, self.tokenizer = load(
            str(path), tokenizer_config={"trust_remote_code": False})

    def generate(self, messages, max_tokens=1600, max_context_tokens=None):
        from mlx_lm import stream_generate
        from mlx_lm.sample_utils import make_sampler
        prompt = self.tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True, enable_thinking=False)
        tokens = self.tokenizer.encode(prompt, add_special_tokens=False)
        if max_context_tokens is not None and len(tokens) + max_tokens > max_context_tokens:
            raise RuntimeError("conversation exceeds the configured context limit; start a fresh session")
        text, last = "", None
        for part in stream_generate(self.model, self.tokenizer, tokens,
                                    max_tokens=max_tokens, sampler=make_sampler(temp=0.0)):
            text += part.text
            last = part
        if last is None:
            raise RuntimeError("model returned no tokens")
        return Generation(text, last.prompt_tokens, last.generation_tokens,
                          last.generation_tokens >= max_tokens)
