#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Stop: если за сессию менялся код подсистем, описанных вики, а docs/wiki — нет,
# один раз возвращает агента дописать вики. Второй Stop проходит всегда.
# Ввод: JSON на stdin ({session_id}). Вывод: {"decision":"block","reason":...} либо ничего.
import sys, os, io, re, json, subprocess, tempfile
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# код, который вики реально описывает (служебные .uid/.import/.godot не считаем)
CODE_RE = re.compile(r"^(scripts/.*\.gd|tests/check_.*\.gd|tools/.*\.(py|gd))$")

def _changed_paths(root, base):
    changed = set()
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain"],
            capture_output=True, text=True, timeout=8,
        ).stdout
        for line in out.splitlines():
            if len(line) < 4:
                continue
            p = line[3:]
            if " -> " in p:            # переименование
                p = p.split(" -> ", 1)[1]
            changed.add(p.strip().strip('"'))
    except Exception:
        pass
    # коммиты, сделанные за сессию (base..HEAD)
    if base:
        try:
            ok = subprocess.run(
                ["git", "-C", str(root), "cat-file", "-e", base + "^{commit}"],
                capture_output=True, timeout=8,
            ).returncode == 0
            if ok:
                out = subprocess.run(
                    ["git", "-C", str(root), "diff", "--name-only", base, "HEAD"],
                    capture_output=True, text=True, timeout=8,
                ).stdout
                for p in out.splitlines():
                    if p.strip():
                        changed.add(p.strip())
        except Exception:
            pass
    return changed

def main():
    root = Path(__file__).resolve().parents[2]
    sid = "default"
    try:
        raw = sys.stdin.read()
        if raw.strip():
            sid = str(json.loads(raw).get("session_id") or "default")
    except Exception:
        pass

    tmp = Path(tempfile.gettempdir())
    sentinel = tmp / f"claude-wiki-stopped-{sid}"
    if sentinel.exists():
        return  # уже срабатывал в этой сессии — не зацикливаемся

    base = ""
    try:
        base = (tmp / f"claude-wiki-head-{sid}").read_text(encoding="utf-8").strip()
    except Exception:
        pass

    changed = _changed_paths(root, base)
    if not changed:
        return

    code = sorted(p for p in changed if CODE_RE.match(p.replace("\\", "/")))
    if not code:
        return
    wiki = [p for p in changed if p.replace("\\", "/").startswith("docs/wiki/")]
    if wiki:
        return  # вики тронута — всё в порядке

    try:
        sentinel.write_text("1", encoding="utf-8")
    except Exception:
        pass

    listed = "\n".join(f"  - {p}" for p in code[:8])
    reason = (
        "За сессию менялся код, а docs/wiki — нет:\n"
        f"{listed}\n\n"
        "Правило из CLAUDE.md: обнови страницу(ы) вики для затронутой подсистемы — "
        "не создавай новый датированный документ. Если менялся порог — поправь "
        "docs/wiki/константы.md; если что-то стало (не)подтверждено — docs/wiki/открытые-вопросы.md; "
        "если это веха — допиши строку в log.md.\n\n"
        "Если обновление вики в этот раз не нужно (тривиальная правка, эксперимент, откат) — "
        "просто скажи это одной строкой и завершай. Повторно этот хук за сессию не сработает."
    )
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
