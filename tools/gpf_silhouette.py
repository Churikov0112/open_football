# Метрика соответствия силуэта референсу.
#
# Зачем. «Похоже / не похоже» на глаз — плохая обратная связь: за один заход
# 2026-08-03 я трижды подряд ухудшил модель, считая что улучшаю. Метрика
# превращает подгонку в число, которое можно минимизировать автономно.
#
# Что меряется. Не общий IoU (он мало что говорит: 82 % — это где именно?),
# а ПРОФИЛЬ ШИРИН — ширина силуэта на фиксированных долях роста. Тогда ответ
# звучит как «талия уже референса на 12 % на высоте 0.55», и сразу понятно,
# какое число править.
#
# Ширина берётся по ЦЕНТРАЛЬНОМУ сегменту строки: на фронтальном виде руки
# отведены и дают свои сегменты по краям, торс — тот, что содержит ось фигуры.
#
# Запускается внутри Blender (numpy и загрузка PNG есть только там).

import numpy as np

BG_TOLERANCE = 0.045     # порог отличия от фона; костюм на референсе почти в тон
LEVELS = 24              # число уровней по высоте


def load_mask(path):
    """PNG → булева маска тела. Фон определяется по углам изображения."""
    import bpy

    image = bpy.data.images.load(path, check_existing=False)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)
    pixels = pixels[::-1]                      # Blender отдаёт снизу вверх
    rgb = pixels[:, :, :3]

    corners = np.concatenate([
        rgb[:12, :12].reshape(-1, 3), rgb[:12, -12:].reshape(-1, 3),
        rgb[-12:, :12].reshape(-1, 3), rgb[-12:, -12:].reshape(-1, 3),
    ])
    background = np.median(corners, axis=0)

    mask = np.abs(rgb - background).max(axis=2) > BG_TOLERANCE
    bpy.data.images.remove(image)
    return mask


def _row_segments(row):
    """[(начало, конец)] непрерывных участков тела в строке."""
    idx = np.flatnonzero(row)
    if idx.size == 0:
        return []
    breaks = np.flatnonzero(np.diff(idx) > 1)
    starts = np.concatenate(([idx[0]], idx[breaks + 1]))
    ends = np.concatenate((idx[breaks], [idx[-1]]))
    return list(zip(starts.tolist(), ends.tolist()))


def width_profile(mask, levels=LEVELS):
    """[(доля высоты, ширина торса, полная ширина)] в долях РОСТА фигуры.

    Обе величины нормированы на рост, поэтому сравнимы между картинками
    любого разрешения и между референсом и рендером.
    """
    rows = np.flatnonzero(mask.any(axis=1))
    cols = np.flatnonzero(mask.any(axis=0))
    if rows.size == 0 or cols.size == 0:
        return []

    top, bottom = rows[0], rows[-1]
    height = float(bottom - top + 1)
    axis_x = 0.5 * (cols[0] + cols[-1])

    out = []
    for i in range(levels):
        t = (i + 0.5) / levels                  # 0 — макушка, 1 — стопы
        y = int(round(top + t * (height - 1)))
        segments = _row_segments(mask[y])
        if not segments:
            out.append((t, 0.0, 0.0))
            continue

        full = (max(e for _s, e in segments) - min(s for s, _e in segments) + 1) / height
        # Самый широкий сегмент, а не центральный: ниже паха по центру строки
        # проходит ЩЕЛЬ между расставленными ногами, и «центральный» сегмент
        # вырождается в край ноги (референс давал там ширину 0.0007).
        core = max(segments, key=lambda se: se[1] - se[0])
        out.append((t, (core[1] - core[0] + 1) / height, full))
    return out


def compare(reference, ours, labels=None):
    """Печатает расхождение по уровням и возвращает суммарную ошибку."""
    print("%-6s %8s %8s %8s | %8s %8s %8s  %s"
          % ("h", "реф", "модель", "разн", "реф.полн", "мод.полн", "разн", "зона"))
    total = 0.0
    count = 0
    for i, ((t, ref_core, ref_full), (_t2, our_core, our_full)) in enumerate(
            zip(reference, ours)):
        if ref_core <= 0.001:
            continue
        # Уровень ненадёжен, если сегмент почти равен полной ширине: значит
        # рука ещё слита с торсом и меряется не торс, а торс вместе с рукой.
        if ref_core > 0.9 * ref_full or our_core > 0.9 * our_full:
            print("%-6.3f %8.4f %8.4f %7s | %8.4f %8.4f %7.1f%%  %s  (руки слиты)"
                  % (t, ref_core, our_core, "—", ref_full, our_full,
                     (our_full - ref_full) / ref_full * 100.0 if ref_full > 0 else 0.0,
                     labels[i] if labels and i < len(labels) else ""))
            continue
        delta = (our_core - ref_core) / ref_core
        delta_full = (our_full - ref_full) / ref_full if ref_full > 0.001 else 0.0
        total += abs(delta)
        count += 1
        label = labels[i] if labels and i < len(labels) else ""
        flag = "" if abs(delta) < 0.08 else ("  ШИРЕ" if delta > 0 else "  УЖЕ")
        print("%-6.3f %8.4f %8.4f %7.1f%% | %8.4f %8.4f %7.1f%%  %s%s"
              % (t, ref_core, our_core, delta * 100.0,
                 ref_full, our_full, delta_full * 100.0, label, flag))
    print("среднее расхождение по телу: %.1f%%" % (total / max(1, count) * 100.0))
    return total


def landmarks(mask):
    """(y плеч, y паха) в пикселях — опорные точки для честного сравнения.

    Нормировать уровни по полному росту нельзя: голова у референса крупнее,
    и на одной и той же доле высоты у него окажется грудь, а у модели рёбра.
    Плечи ищем по максимуму полной ширины в верхней половине, пах — по первой
    сверху строке, где силуэт распадается на две ноги.
    """
    rows = np.flatnonzero(mask.any(axis=1))
    top, bottom = rows[0], rows[-1]
    height = bottom - top + 1

    # Плечи ищем ОТ ШЕИ, а не по максимуму ширины: в A-позе отведённые руки
    # расходятся книзу, полная ширина монотонно растёт, и «максимум» всегда
    # упирался в нижнюю границу поиска — плечи находились на середине фигуры.
    def row_width(y):
        segments = _row_segments(mask[y])
        if not segments:
            return 0
        return max(e for _s, e in segments) - min(s for s, _e in segments)

    neck_y, neck_w = top, 10 ** 9
    for y in range(top + int(0.06 * height), top + int(0.30 * height)):
        width = row_width(y)
        if 0 < width < neck_w:
            neck_w, neck_y = width, y

    best_y = neck_y
    for y in range(neck_y, top + int(0.45 * height)):
        if row_width(y) > neck_w * 1.75:      # плечи — резкий скачок после шеи
            best_y = y
            break

    # Пах ищем по ЩЕЛИ НА ОСИ фигуры, а не по числу сегментов: в A-позе руки
    # отделены от торса уже на уровне плеч, и «есть два сегмента» срабатывает
    # сразу же — все уровни торса схлопывались в одну строку.
    cols = np.flatnonzero(mask.any(axis=0))
    axis_x = int(round(0.5 * (cols[0] + cols[-1])))
    band = slice(max(0, axis_x - 2), axis_x + 3)

    crotch_y = top + int(0.60 * height)
    for y in range(best_y + int(0.10 * height), bottom):
        if not mask[y, band].any():
            crotch_y = y
            break
    return best_y, crotch_y, top, bottom


def anatomical_profile(mask, torso_levels=8, leg_levels=8):
    """Ширины на уровнях, привязанных к плечам, паху и стопам.

    u от 0 (плечи) до 1 (пах) — торс; от 1 до 2 (пах → стопы) — ноги.
    Правило выбора сегмента переключается по уровню: выше паха торс — тот
    сегмент, что лежит НА ОСИ фигуры (руки дают свои по краям), ниже паха
    ось проходит по щели между ногами, и там берётся самый широкий сегмент.
    Единого правила нет: «самый широкий» выше паха ловил торс вместе с рукой,
    «центральный» ниже паха вырождался в край ноги.
    """
    shoulder_y, crotch_y, top, bottom = landmarks(mask)
    height = float(bottom - top + 1)
    cols = np.flatnonzero(mask.any(axis=0))
    axis_x = 0.5 * (cols[0] + cols[-1])

    out = []
    # Уровень самих плеч пропускаем: у одних фигур руки там ещё слиты с торсом,
    # у других уже отделились, и сравнивать нечего.
    for i in range(torso_levels):
        u = 0.08 + 0.92 * i / max(1, torso_levels - 1)
        y = int(round(shoulder_y + u * (crotch_y - shoulder_y)))
        out.append((u,) + _row_widths(mask, y, height, axis_x, on_axis=True))
    for i in range(1, leg_levels + 1):
        u = 1.05 + 0.85 * i / float(leg_levels)
        y = int(round(crotch_y + (u - 1.0) * (bottom - crotch_y)))
        out.append((u,) + _row_widths(mask, min(y, bottom), height, axis_x, on_axis=False))
    return out


def _row_widths(mask, y, height, axis_x, on_axis):
    segments = _row_segments(mask[y])
    if not segments:
        return 0.0, 0.0
    full = (max(e for _s, e in segments) - min(s for s, _e in segments) + 1) / height
    if on_axis:
        covering = [se for se in segments if se[0] - 2 <= axis_x <= se[1] + 2]
        core = covering[0] if covering else min(
            segments, key=lambda se: abs(0.5 * (se[0] + se[1]) - axis_x))
    else:
        core = max(segments, key=lambda se: se[1] - se[0])
    return (core[1] - core[0] + 1) / height, full
