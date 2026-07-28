#!/usr/bin/env python
# -*- coding: utf-8 -*-
# PreToolUse (Edit|Write): по пути правимого файла подсказывает страницу(ы) вики.
# Ввод: JSON на stdin ({tool_input:{file_path}}). Вывод: JSON hookSpecificOutput.additionalContext.
# Если добавляешь подсистему — впиши сюда маппинг basename → страница вики.
import sys, os, io, json
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# basename исходника → страницы вики (через пробел)
PAGES = {
    # --- ядро / оркестрация ---
    "match_manager.gd":       "архитектура подкат-и-падение конвенции",
    "match_referee.gd":       "архитектура стандарты-и-intent-seam",
    "referee_logic.gd":       "архитектура стандарты-и-intent-seam",
    "boundary_logic.gd":      "вбрасывание архитектура",
    # --- локомоция / мяч ---
    "player_motor.gd":        "локомоция",
    "ball_controller.gd":     "мяч-и-дриблинг",
    # --- пас / удар ---
    "pass_system.gd":         "пас",
    "pass_params.gd":         "пас",
    "action_executor.gd":     "пас удар",
    "shot_system.gd":         "удар",
    # --- сетка ---
    "goal_net.gd":            "сетка-ворот",
    "net_sim.gd":             "сетка-ворот",
    # --- вратарь ---
    "keeper_ai.gd":               "вратарь",
    "keeper_logic.gd":            "вратарь пенальти",
    "keeper_play_logic.gd":       "вратарь",
    "keeper_intent.gd":           "вратарь пенальти стандарты-и-intent-seam",
    "human_keeper_intent.gd":     "вратарь пенальти",
    "ai_keeper_intent.gd":        "вратарь пенальти",
    "keeper_hands_intent.gd":     "вратарь",
    "human_keeper_hands_intent.gd": "вратарь",
    "ai_keeper_hands_intent.gd":  "вратарь",
    # --- стандарты ---
    "penalty_controller.gd":  "пенальти",
    "penalty_logic.gd":       "пенальти",
    "free_kick_controller.gd":"штрафной стандарты-и-intent-seam",
    "free_kick_logic.gd":     "штрафной угловой вбрасывание начальный-удар",
    "corner_controller.gd":   "угловой",
    "corner_logic.gd":        "угловой",
    "goal_kick_controller.gd":"ввод-от-ворот",
    "goal_kick_logic.gd":     "ввод-от-ворот",
    "goal_kick_plan.gd":      "ввод-от-ворот",
    "ai_goal_kick_intent.gd": "ввод-от-ворот",
    "throw_in_controller.gd": "вбрасывание",
    "throw_in_logic.gd":      "вбрасывание",
    "throw_in_plan.gd":       "вбрасывание",
    "ai_throw_in_intent.gd":  "вбрасывание",
    "kickoff_controller.gd":  "начальный-удар",
    "kickoff_logic.gd":       "начальный-удар",
    # --- intent-шов ---
    "kicker_intent.gd":         "стандарты-и-intent-seam",
    "human_kicker_intent.gd":   "стандарты-и-intent-seam",
    "ai_kicker_intent.gd":      "стандарты-и-intent-seam",
    "ai_kickoff_intent.gd":     "начальный-удар стандарты-и-intent-seam",
    "set_piece_presentation.gd":"стандарты-и-intent-seam",
    # --- презентация / ассеты ---
    "player_visual.gd":       "презентация-и-ассеты",
    "merge_mixamo.py":        "презентация-и-ассеты подкат-и-падение",
    # --- фабрика / ростер / мозги ---
    "player_factory.gd":      "фабрика-игроков",
    "team.gd":                "фабрика-игроков",
    "player_config.gd":       "фабрика-игроков",
    "brain.gd":               "фабрика-игроков архитектура",
    "player.gd":              "фабрика-игроков",
    "simple_ai.gd":           "фабрика-игроков подкат-и-падение",
    "teammate_ai.gd":         "фабрика-игроков пас",
    "ragdoll_skeleton.gd":    "подкат-и-падение",
    # --- камера / константы ---
    "match_camera.gd":        "поле-и-камера",
    "football_constants.gd":  "константы",
}

def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    f = (data.get("tool_input") or {}).get("file_path") or ""
    if not f:
        return
    base = os.path.basename(f.replace("\\", "/"))
    pages = PAGES.get(base)
    if not pages:
        return

    root = Path(__file__).resolve().parents[2]
    lines = [f"Правится {base}. Актуальное описание этой подсистемы — в вики "
             "(читай ПЕРЕД правкой, если ещё не читал):"]
    for p in pages.split():
        if (root / "docs" / "wiki" / f"{p}.md").is_file():
            lines.append(f"  - docs/wiki/{p}.md")
    lines.append("Пороги и константы не выводи из прозы — они в docs/wiki/константы.md.")
    lines.append("После правки обнови затронутые страницы вики (правило в CLAUDE.md).")

    print(json.dumps({
        "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "\n".join(lines)},
    }, ensure_ascii=False))

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
