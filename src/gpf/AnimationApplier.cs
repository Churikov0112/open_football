using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Офсет узла — порт struct BiasedOffset (animation.hpp:46-54): насколько и куда доворачивать
    // кость поверх кадра клипа. Обычный C#-класс, через мост не ходит (как SpatialState).
    public class BiasedOffset
    {
        public float Bias;                                    // :51 — 0..1
        public Quaternion Orientation = Quaternion.Identity;  // :52
        public bool IsRelative;                               // :53

        // В C++ это struct, и `animApplyBuffer.offsets = offsets` (humanoid.cpp:780) копирует
        // записи ПО ЗНАЧЕНИЮ. Копия обязательна: Apply мутирует Orientation через
        // MakeSameNeighborhood (:427), и по ссылке мутация ушла бы в карту гуманоида.
        // Та же причина, что у PlayerCommand.Clone().
        public BiasedOffset Clone() => new BiasedOffset
        {
            Bias = Bias, Orientation = Orientation, IsRelative = IsRelative,
        };
    }

    // Применение кадра клипа на Skeleton3D — порт Animation::Apply (animation.cpp:370-721):
    // джойнты получают АБСОЛЮТНУЮ локальную ротацию, player — позицию корня. С фазы 4 (задача 5)
    // портирована и ветка сглаживания smooth/smoothFactor (:436-707): «предыдущая поза» читается
    // из скелета ДО записи (в C++ — из nodeMap), история движений — в _movementHistory.
    // С фазы 6 портирована и ветка офсетов (:424-433) — см. Offsets ниже.
    // Не портирован: updateSpatial (:720 — Godot сам).
    public partial class AnimationApplier : RefCounted
    {
        // MovementHistory (animation.hpp): предыдущая поза/позиция узла для сглаживания.
        // ШОВ: в C++ история живёт при гуманоиде и передаётся в Apply; у нас — при экземпляре
        // применителя, ключ — имя кости. Один скелет на экземпляр AnimationApplier; при
        // нескольких игроках заводить по экземпляру на игрока.
        private class MovementHistoryEntry
        {
            public Vector3 Position;
            public Quaternion Orientation;
            public int TimeDiffMs = 10;
        }
        private readonly Dictionary<string, MovementHistoryEntry> _movementHistory = new();

        // Карта офсетов, которую читает Apply (:425). ШОВ — тот же, что у _movementHistory: в C++
        // она приходит ПАРАМЕТРОМ Apply (animation.cpp:370) из animApplyBuffer.offsets, у нас
        // ставится при экземпляре применителя перед вызовом. Причина не стилистическая:
        // Dictionary<string, BiasedOffset> через мост GDScript не проходит, а Apply зовут из
        // tests/check_gpf_apply.gd — параметром метод стал бы для GDScript невидимым. Один
        // применитель на гуманоида, так что семантика та же.
        // В живой игре карта ВСЕГДА пуста: Humanoid::CalculateGeomOffsets не вызывается никогда
        // (см. HumanoidBase.CalculateGeomOffsets).
        internal Dictionary<string, BiasedOffset>? Offsets;

        // Порт HumanoidBase::SetOffset (humanoidbase.cpp:852-871) на стороне применителя: способ
        // наполнить карту, когда гуманоида нет (лаба клипов, тесты). Четыре случая оригинала
        // сворачиваются в два — запись (вставка либо перезапись) и удаление; наблюдаемо то же самое.
        // Нулевой bias именно УДАЛЯЕТ запись (:869-870), а не пишет нулевое влияние.
        public void SetOffset(string nodeName, float bias, Quaternion orientation, bool isRelative)
        {
            if (bias != 0f)
            {
                Offsets ??= new Dictionary<string, BiasedOffset>();
                Offsets[nodeName] = new BiasedOffset
                {
                    Bias = bias, Orientation = orientation, IsRelative = isRelative,
                };
            }
            else Offsets?.Remove(nodeName);
        }

        // GDScript-мост не переносит default-аргументы C# (default_args пуст на стороне GDScript),
        // поэтому из GDScript звать с полным списком из 10 аргументов.
        // smooth/smoothFactor/timeDiffMs — animation.cpp:370 (сигнатура Apply); timeDiffMs при
        // 100 Гц всегда 10.
        public void Apply(Skeleton3D skel, Animation anim, int frame, float timeOffsetMs,
                          bool noPos = false, float baseRotZ = 0f, Vector3 basePos = default,
                          bool smooth = false, float smoothFactor = 1.0f, int timeDiffMs = 10)
        {
            // :393-400 — блок smoothFrames под `if (smooth && 1 == 2)` мёртв в оригинале
            // (1 == 2), smoothFrames всегда 0 — не переносим.

            // :460-461 — биасы сглаживания (в C++ считаются в цикле, значение от узла не зависит)
            float beginBias = Mathf.Pow(
                BluntMath.Curve(1.0f - BluntMath.NormalizedClamp(frame, 0, 8), 1.0f), 0.5f); // :460
            float currentBias = 0.0f + beginBias * smoothFactor * 0.5f;                      // :461

            for (int i = 0; i < anim.GetTrackCount(); i++)
            {
                string name = anim.GetTrackName(i);
                int idx = skel.FindBone(name);
                if (idx < 0)
                {
                    GD.PushWarning($"Gpf.AnimationApplier: в скелете нет кости {name}");
                    continue;
                }

                if (name == "player")
                {
                    Vector3 pos = anim.SampleRootPosition(frame, timeOffsetMs);
                    if (noPos) { pos.X = 0; pos.Y = 0; }                       // animation.cpp:410-412 (Z остаётся)
                    else pos = BluntMath.GetRotated2D(pos, baseRotZ);           // animation.cpp:413-415 (шов 5)

                    if (smooth)                                                 // :438, ветка :641-705
                    {
                        MovementHistoryEntry entry = GetOrAddHistory(name, pos, Quaternion.Identity); // :450-458
                        Vector3 previousPosition = entry.Position;              // :643
                        Vector3 currentPosition = skel.GetBonePosePosition(idx); // :644 — поза ДО записи

                        if (timeDiffMs > 0 && beginBias > 0.01f)                // :646
                        {
                            // :648 — currentMovement вычислен и дальше не используется
                            // (потребители закомментированы в оригинале), как есть
                            Vector3 currentMovement = (currentPosition - previousPosition)
                                / (entry.TimeDiffMs * 0.001f);                  // :648
                            _ = currentMovement;

                            // smooth — только высота (:671-672)
                            pos.Z = pos.Z * (1.0f - currentBias) + currentPosition.Z * currentBias; // :672

                            // «old version, use for now» (:675-696) — ограничение вертикальной
                            // скорости корня
                            float maxMetersPerSec = 2.8f;                       // :677
                            if (anim.GetVariable("outgoing_special_state") != "")
                                maxMetersPerSec = 6.0f;                         // :678
                            float allowedDistance = maxMetersPerSec * (timeDiffMs * 0.001f); // :679

                            // :682 + запись :715 — при basePos.Z != 0 высота удвоилась бы;
                            // bug-for-bug (в оригинале basePos.Z == 0, сторож FLYING PLAYERS)
                            float newZ = pos.Z + basePos.Z;                     // :682
                            float desiredDistance = Mathf.Abs(newZ - currentPosition.Z); // :683

                            float zBias = 1.0f;                                 // :685
                            if (desiredDistance > allowedDistance)
                                zBias = allowedDistance / desiredDistance;      // :686

                            // dual biasses ^_^ (:688-689): влияние currentPosition только при
                            // beginBias > 0
                            newZ = (newZ * zBias + currentPosition.Z * (1.0f - zBias)) * beginBias
                                 + newZ * (1.0f - beginBias);                   // :688-689

                            pos = BluntMath.Get2D(pos) + new Vector3(0, 0, newZ); // :696 — только высота
                        }

                        entry.Position = currentPosition;                       // :702
                        entry.TimeDiffMs = timeDiffMs;                          // :703
                    }

                    pos += basePos;                                             // animation.cpp:715
                    skel.SetBonePosePosition(idx, pos);
                }
                else
                {
                    Quaternion q = anim.SampleRotation(name, frame, timeOffsetMs);
                    if (name == "body" && baseRotZ != 0f) // animation.cpp:417-422
                        q = (new Quaternion(new Vector3(0, 0, 1), baseRotZ) * q).Normalized();

                    // офсет узла (:424-433). В оригинале блок стоит ДО ветвления player/не-player,
                    // но у узла "player" ориентация никуда не пишется (:710-716) и в его треке лежит
                    // только позиция — поэтому здесь он в не-player ветке, наблюдаемо это одно и то же.
                    if (Offsets != null && Offsets.TryGetValue(name, out BiasedOffset? off))
                    {
                        off.Orientation = QuatUtil.SameNeighborhood(off.Orientation, q); // :427
                        q = QuatUtil.GetNormalized(off.IsRelative
                            ? QuatUtil.Lerp(q, off.Bias, off.Orientation * q)   // :429
                            : QuatUtil.Lerp(q, off.Bias, off.Orientation));     // :431
                    }

                    if (smooth)                                                 // :438, ветка :463-639
                    {
                        MovementHistoryEntry entry = GetOrAddHistory(name, Vector3.Zero, q); // :450-458
                        Quaternion previousOrientation = entry.Orientation;     // :465
                        Quaternion currentOrientation = skel.GetBonePoseRotation(idx); // :466 — поза ДО записи
                        currentOrientation = QuatUtil.SameNeighborhood(
                            currentOrientation, previousOrientation);           // :467

                        if (timeDiffMs > 0)                                     // :469
                        {
                            // :471 simpleMethod = true — ветка simpleMethod == false (:473-576)
                            // МЕРТВА в оригинале («non-simple-method bug: initial orientation
                            // seems to be off»), не переносим построчно.

                            // simpleMethod == true (:578-601)
                            q = QuatUtil.GetNormalized(
                                QuatUtil.Slerp(q, currentBias, currentOrientation)); // :580

                            // maximum rotational velocity (:582-599)
                            float dot = q.Dot(currentOrientation);              // :583 MakeSameNeighborhood
                            if (dot < 0) { q = new Quaternion(-q.X, -q.Y, -q.Z, -q.W); dot = -dot; }
                            float anglePerSecond = 2.0f * Mathf.Acos(Mathf.Clamp(dot, -1.0f, 1.0f))
                                / (timeDiffMs * 0.001f);                        // :584
                            float maxAnglePerSecond = 7.5f * Mathf.Pi;          // :585
                            if (name == "left_elbow") maxAnglePerSecond *= 1.2f;       // :587
                            else if (name == "right_elbow") maxAnglePerSecond *= 1.2f; // :588
                            else if (name == "left_knee") maxAnglePerSecond *= 1.2f;   // :589
                            else if (name == "right_knee") maxAnglePerSecond *= 1.2f;  // :590
                            else if (name == "left_ankle") maxAnglePerSecond *= 1.6f;  // :591
                            else if (name == "right_ankle") maxAnglePerSecond *= 1.6f; // :592
                            maxAnglePerSecond = (0.3f + 0.7f * (1.0f - beginBias)) * maxAnglePerSecond; // :593
                            if (anglePerSecond > maxAnglePerSecond)             // :595
                            {
                                float allowFraction = maxAnglePerSecond / anglePerSecond; // :596
                                Quaternion desiredRotation = QuatUtil.GetNormalized(
                                    QuatUtil.GetRotationTo(currentOrientation, q)); // :597
                                q = QuatUtil.GetNormalized(
                                    QuatUtil.GetRotationMultipliedBy(desiredRotation, allowFraction)
                                    * currentOrientation);                      // :598
                            }
                        }

                        entry.Orientation = currentOrientation;                 // :636
                        entry.TimeDiffMs = timeDiffMs;                          // :637
                    }

                    // запись с приведением в полусферу текущей позы (:710-713)
                    q = QuatUtil.SameNeighborhood(q, skel.GetBonePoseRotation(idx));
                    skel.SetBonePoseRotation(idx, q);
                }
            }
        }

        // :450-458 — узла ещё нет в истории: завести с вычисленной позой клипа
        private MovementHistoryEntry GetOrAddHistory(string name, Vector3 position, Quaternion orientation)
        {
            if (!_movementHistory.TryGetValue(name, out MovementHistoryEntry? entry) || entry == null)
            {
                entry = new MovementHistoryEntry
                {
                    Position = position,        // :453
                    Orientation = orientation,  // :454
                    TimeDiffMs = 10,            // :455
                };
                _movementHistory[name] = entry;
            }
            return entry;
        }
    }
}
