#!/usr/bin/env python
# -*- coding: utf-8 -*-
# SessionStart: впрыскивает компактное оглавление вики в контекст + запоминает HEAD сессии.
# Оглавление генерируется из docs/wiki/index.md, поэтому не устаревает.
#
# Кроссплатформенно (Windows-only проект, реального `python3` нет — вызывается как `python`).
# Скрипт сам находит корень репозитория через __file__, поэтому не зависит от cwd.
# Ввод: JSON на stdin ({session_id}). Вывод: JSON hookSpecificOutput на stdout.
import sys, os, io, re, json, subprocess, tempfile
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

def main():
    root = Path(__file__).resolve().parents[2]
    idx = root / "docs" / "wiki" / "index.md"

    # session_id со stdin (может отсутствовать)
    sid = "default"
    try:
        raw = sys.stdin.read()
        if raw.strip():
            sid = str(json.loads(raw).get("session_id") or "default")
    except Exception:
        pass

    # запомнить HEAD на старте сессии — Stop-хук сравнит с ним, чтобы увидеть
    # коммиты, сделанные за сессию (а не только незакоммиченные правки)
    tmp = Path(tempfile.gettempdir())
    try:
        head = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=8,
        ).stdout.strip()
        if head:
            (tmp / f"claude-wiki-head-{sid}").write_text(head, encoding="utf-8")
    except Exception:
        pass
    try:
        (tmp / f"claude-wiki-stopped-{sid}").unlink()
    except Exception:
        pass

    if not idx.is_file():
        return

    rows = []
    row_re = re.compile(r"^\|\s*\[\[([^\]]+)\]\]\s*\|\s*(.+?)\s*\|\s*$")
    for line in idx.read_text(encoding="utf-8").splitlines():
        m = row_re.match(line)
        if m:
            rows.append(f"  {m.group(1)}.md — {m.group(2)}")
    if not rows:
        return

    toc = "\n".join(rows)
    msg = (
        "Вики проекта (docs/wiki/, живое состояние — читать вместо вывода из кода/прозы):\n"
        f"{toc}\n"
        "Каталог: docs/wiki/index.md · Хронология: log.md · "
        "Датированные первоисточники (не редактировать): docs/superpowers/"
    )
    print(json.dumps({
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg},
        "suppressOutput": True,
    }, ensure_ascii=False))

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # хук никогда не должен ронять сессию
    sys.exit(0)
