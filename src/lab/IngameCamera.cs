using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Порт камеры матча оригинала: Match::UpdateIngameCamera (match.cpp:723-843),
    // Get/SetCameraParams (:709-721), заливка в узлы сцены из Put-фазы (:1221-1240) и
    // вступительный наезд первых двух секунд (:1051-1075).
    //
    // Слой лабы, а не `Gpf.*`: в оригинале это методы `Match`, то есть матч-собственность —
    // фаза 8 забирает файл в матч-слой ЦЕЛИКОМ (как MatchPresentation и GoalNetting).
    //
    // Три СУРРОГАТА лабы (записаны строкой швов в docs/wiki/расхождения-с-оригиналом.md,
    // снимаются фазой 8): владеющий мячом = единственный игрок; FadingTeamPossessionAmount
    // = 1.0 у обеих команд; забивший для scorer-cam = он же.
    //
    // Иерархия узлов — как у оригинала (:1221-1223, :1238): родитель `cameraNode` несёт
    // позицию и поворот, дочерняя камера — только поворот и параметры объектива. Оба узла
    // живут под `GpfSpace`: числа тут в «их» осях.
    //
    // Дрожание кормится ПРЕЗЕНТАЦИОННЫМ `GpfRng` (2 броска на тик) — геймплейный поток
    // неприкосновенен (тикет .scratch/oracle/issues/17-...).
    public partial class IngameCamera : RefCounted
    {
        // gamedefines.hpp:33-36 — дефолты пользовательских параметров. У оригинала они
        // приезжают из конфига (match.cpp:167-170), конфига в порте нет — живут дефолты.
        private float _cameraUserZoom = 0.5f;        // _default_CameraZoom
        private float _cameraUserHeight = 0.3f;      // _default_CameraHeight
        private float _cameraUserFOV = 0.4f;         // _default_CameraFOV
        private float _cameraUserAngleFactor = 0.0f; // _default_CameraAngleFactor

        private const int CamPosSize = 150; // match.cpp:30 — глубина очереди позиций

        // match.hpp:340 — std::deque<Vector3> camPos («todo: circular buffer?» оригинала)
        private readonly List<Vector3> _camPos = new();

        // match.hpp:316-321 — состояние камеры между тиком и заливкой в сцену
        private Quaternion _cameraOrientation = Quaternion.Identity;
        private Quaternion _cameraNodeOrientation = Quaternion.Identity;
        private Vector3 _cameraNodePosition;
        private float _cameraFOV;
        private float _cameraNearCap;
        private float _cameraFarCap;

        // vector3.hpp:261-268 GetLength — квирк оригинала: длина < 1e-6 обнуляется.
        private static float GetLength(Vector3 v)
        {
            float length = Mathf.Sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z);
            if (length < 0.000001f) length = 0f;
            return length;
        }

        // match.cpp:716-721
        public void SetCameraParams(float zoom, float height, float fov, float angleFactor)
        {
            _cameraUserZoom = zoom;
            _cameraUserHeight = height;
            _cameraUserFOV = fov;
            _cameraUserAngleFactor = angleFactor;
        }

        // match.cpp:709-714. Через мост GDScript `out`-параметры не ходят, поэтому четыре
        // числа отдаются вектором: zoom, height, fov, angleFactor.
        public Godot.Collections.Array<float> GetCameraParams()
            => new() { _cameraUserZoom, _cameraUserHeight, _cameraUserFOV, _cameraUserAngleFactor };

        // Очередь позиций чистится при сбросе ситуации (match.cpp:652) и при переключении
        // автообновления камеры (match.hpp:193) — иначе камера «прилетает» из прошлой сцены.
        public void ResetPositions() => _camPos.Clear();

        // Порт Match::UpdateIngameCamera (match.cpp:723-843). Матч-входы приходят
        // параметрами: у оригинала это ball, GetDesignatedPossessionPlayer(), команды,
        // IsGoalScored()/goalScoredTimer и lastGoalScorer.
        public void Update(Vector3 ballPredict0, Vector3 ballMovement,
            Vector3 playerPosition, Vector3 playerDirection,
            bool goalScored, long goalScoredTimer, Vector3 scorerPosition, Gpf.GpfRng rng)
        {
            float fov = 0.5f + _cameraUserFOV * 0.5f;  // :730
            float zoom = _cameraUserZoom;              // :731
            float height = _cameraUserHeight * 1.5f;   // :732

            float playerBias = 0.6f; // :734 — «//0.7f» в оригинале
            Vector3 ballPos = ballPredict0 * (1.0f - playerBias) + playerPosition * playerBias; // :735
            ballPos += playerDirection * 1.0f; // :737 — смотреть в сторону взгляда владеющего

            // :739 — сдвиг в сторону атаки владеющей команды. СУРРОГАТ: в лабе команд нет,
            // FadingTeamPossessionAmount = 1.0 у обеих, поэтому слагаемое зануляется
            // арифметикой формулы. Фаза 8 подставит настоящие значения и стороны.
            const float fadingPossession0 = 1.0f, fadingPossession1 = 1.0f;
            const int side0 = -1, side1 = 1;
            ballPos += new Vector3(((fadingPossession0 - 1.0f) * -side0
                + (fadingPossession1 - 1.0f) * -side1) * 4.0f, 0, 0);

            ballPos.Z *= 0.1f; // :741

            // клампы по полю (:743-746): камера не уезжает за кромку
            float maxW = GpfPitch.PitchHalfW * 0.84f * (1.0f / (zoom + 0.01f)); // :743
            float maxH = GpfPitch.PitchHalfH * 0.60f * (1.0f / (zoom + 0.01f))
                * (height * 0.75f + 0.25f); // :744 — «0.52f» в комментарии оригинала
            if (Mathf.Abs(ballPos.X) > maxW) ballPos.X = maxW * BluntMath.SignSide(ballPos.X); // :745
            if (Mathf.Abs(ballPos.Y) > maxH) ballPos.Y = maxH * BluntMath.SignSide(ballPos.Y); // :746

            // дрожание (:748-749) — два броска ГСЧ на тик, порядок бросков явный.
            // ВНИМАНИЕ на будущее (фаза 9, сведение потоков): в C++ порядок вычисления
            // аргументов Vector3(random(), random(), 0) стандартом не определён, и компиляторы
            // x86-64 обычно считают их СПРАВА НАЛЕВО — то есть у эталона первое вытянутое
            // число уходит, скорее всего, в Y, а здесь в X. На картинку это не влияет (оба
            // броска из одного распределения, число бросков то же), но при сверке потоков
            // порядок надо проверить эмпирически на собранном эталоне, а не по стандарту.
            float shudderX = rng.Uniform(-0.1f, 0.1f);
            float shudderY = rng.Uniform(-0.1f, 0.1f);
            Vector3 shudder = new Vector3(shudderX, shudderY, 0)
                * (GetLength(ballMovement) * 0.8f + 6.0f);
            shudder *= 0.2f; // :749

            // :750 — доля дрожания растёт по мере заполнения очереди (size ДО вставки)
            _camPos.Add(ballPos + shudder * ((float)_camPos.Count / (float)CamPosSize));
            if (_camPos.Count > CamPosSize) _camPos.RemoveAt(0); // :751

            // взвешенное среднее очереди (:753-767): «здоровая смесь свежего и среднего»
            Vector3 average = Vector3.Zero;
            float count = 0;
            float indexSize = _camPos.Count;
            for (int index = 0; index < _camPos.Count; index++)
            {
                float weight = Mathf.Sin((index / indexSize - 0.3f) * 1.4f * Mathf.Pi) * 0.5f + 0.5f; // :759
                weight *= Mathf.Pow(1.0f - index / indexSize, 0.3f); // :760 — резкий срез у самого свежего:
                                                                     // оператор не может «предвидеть» текущий момент
                average += _camPos[index] * weight; // :761
                count += weight;                    // :762
            }

            average /= count; // :767

            float angleFac = 1.0f - _cameraUserAngleFactor * 0.4f; // :769 — 0.0 = 90°, 1.0 = вид с бровки

            int camMethod = 1; // :773 — 1 == wide, 2 == birds-eye, 3 == tele; захардкожен в 1

            if (!goalScored || (goalScored && goalScoredTimer < 1000)) // :775
            {
                if (camMethod == 1) // :777
                {
                    // wide cam (:779-791)

                    zoom = (0.6f + zoom * 1.0f) * (1.0f / fov); // :781
                    height = 4.0f + height * 10;               // :782

                    float distRot = average.Y / 800.0f; // :784

                    _cameraOrientation = QuatUtil.AngleAxis(
                        distRot + (0.42f - height * 0.01f) * Mathf.Pi, new Vector3(1, 0, 0)); // :786
                    _cameraNodeOrientation = QuatUtil.AngleAxis(
                        (-average.X / GpfPitch.PitchHalfW) * (1.0f - angleFac) * 0.25f * Mathf.Pi * 1.24f,
                        new Vector3(0, 0, 1)); // :787
                    _cameraNodePosition = average * new Vector3(
                            1.0f * (1.0f - _cameraUserAngleFactor * 0.2f) * (1.0f - _cameraUserZoom * 0.3f),
                            0.9f - _cameraUserZoom * 0.3f,
                            0.2f)
                        + new Vector3(0,
                            -41.4f - (_cameraUserFOV * 3.7f) + Mathf.Pow(height, 1.2f) * 0.46f,
                            10.0f + height) * zoom; // :788
                    _cameraFOV = (fov * 28.0f) - (_cameraNodePosition.Y / 30.0f); // :789
                    _cameraNearCap = _cameraNodePosition.Z; // :790 — ближняя плоскость режет трибуну перед камерой
                    _cameraFarCap = 200;                    // :791
                }
                else if (camMethod == 2) // :793 — МЁРТВАЯ ветка, перенесена дословно
                {
                    // birds-eye cam (:795-802)

                    _cameraOrientation = Quaternion.Identity;     // :797
                    _cameraNodeOrientation = Quaternion.Identity; // :798
                    _cameraNodePosition = average * new Vector3(1, 1, 0)
                        + new Vector3(0, 0, 50 + zoom * 20.0f);   // :799
                    _cameraFOV = 28;                              // :800
                    _cameraNearCap = 40 + height - 5;             // :801
                    _cameraFarCap = 250;                          // :802 — «65 + height * 1.2; doesn't work wtf?»
                }
                else if (camMethod == 3) // :804 — МЁРТВАЯ ветка, перенесена дословно
                {
                    // tele cam (:806-816)

                    zoom = (0.6f + zoom * 1.0f) * (1.0f / fov); // :808

                    _cameraOrientation = QuatUtil.AngleAxis(
                        0.3f * Mathf.Pi * height + 0.4f * Mathf.Pi * (1.0f - height), new Vector3(1, 0, 0)); // :810
                    _cameraNodeOrientation = Quaternion.Identity; // :811
                    Vector3 offset = new Vector3(0, -175.0f, 125.0f) * height
                        + new Vector3(0, -230.0f, 65.0f) * (1.0f - height); // :812
                    _cameraNodePosition = average * new Vector3(0.9f, 0.7f, 0.2f)
                        + offset * zoom * 0.4f; // :813
                    _cameraFOV = 15.0f;              // :814
                    _cameraNearCap = 50 + zoom * 10.0f; // :815
                    _cameraFarCap = 300;             // :816
                }
            }
            else
            {
                // scorer cam (:822-841) — облёт забившего с нарастающим поворотом

                Vector3 targetPos = BluntMath.Get2D(ballPredict0); // :824
                targetPos = scorerPosition; // :825-827 — СУРРОГАТ: забивший в лабе есть всегда

                float rot = (float)goalScoredTimer * 0.0005f; // :829
                _cameraOrientation = QuatUtil.AngleAxis(0.45f * Mathf.Pi, new Vector3(1, 0, 0)); // :830
                _cameraNodeOrientation = QuatUtil.AngleAxis(rot, new Vector3(0, 0, 1));          // :831
                _cameraNodePosition = targetPos
                    + BluntMath.GetRotated2D(new Vector3(0, -1, 0), rot) * 15.0f
                    + new Vector3(0, 0, 3); // :832
                _cameraFOV = 35.0f;   // :833
                _cameraNearCap = 1;   // :835
                _cameraFarCap = 220;  // :836

                // шов (:838-841): на goalScoredTimer == 6000 оригинал ставит паузу и шлёт
                // sig_OnExtendedReplayMoment — ни паузы, ни реплея в лабе нет (фазы 8 и 10)
            }
        }

        // match.cpp:1051-1075 — наезд первых двух секунд: сцена начинается видом сверху и
        // съезжает в wide-камеру. Живой код оригинала, идёт СРАЗУ ПОСЛЕ UpdateIngameCamera.
        public void ApplyIntroZoom(long actualTimeMs)
        {
            const int zoomTime = 2000; // :1052
            const int startTime = 0;   // :1053
            if (actualTimeMs >= zoomTime + startTime) return; // :1054

            Quaternion initialOrientation = QuatUtil.AngleAxis(0.0f * Mathf.Pi, new Vector3(1, 0, 0)); // :1056-1057
            // :1058-1059 — zOrientation единичный, умножение ничего не меняет
            Vector3 initialPosition = new Vector3(0.0f, 0.0f, 60.0f); // :1061

            float subTime = Mathf.Clamp(actualTimeMs - startTime, 0, zoomTime); // :1063
            float bias = subTime / (float)zoomTime;                             // :1064
            bias *= Mathf.Pi;                                                   // :1065
            bias = Mathf.Sin(bias - 0.5f * Mathf.Pi) * -0.5f + 0.5f;            // :1066

            _cameraOrientation = QuatUtil.Slerp(_cameraOrientation, bias, Quaternion.Identity);      // :1068
            _cameraNodeOrientation = QuatUtil.Slerp(_cameraNodeOrientation, bias, initialOrientation); // :1069
            _cameraNodePosition = _cameraNodePosition * (1.0f - bias) + initialPosition * bias;      // :1070
            _cameraFOV = _cameraFOV * (1.0f - bias) + 40 * bias;                                     // :1071
            _cameraNearCap = _cameraNearCap * (1.0f - bias) + 2.0f * bias;                           // :1072
        }

        // Put-фаза оригинала (match.cpp:1221-1240). TemporalSmoother-буферы (:1190-1195)
        // вырезаны тем же решением, что и Ball::Put — сцена читает состояние напрямую.
        //
        // cameraFOV — ВЕРТИКАЛЬНЫЙ угол в градусах (matrix4.cpp:294-298: top = zNear *
        // tan(fov * pi/360)), у Godot при KeepHeight ровно он же.
        public void Apply(Node3D cameraNode, Camera3D camera)
        {
            camera.Position = Vector3.Zero;                 // :1221
            camera.Quaternion = _cameraOrientation;         // :1222
            cameraNode.Position = _cameraNodePosition;      // :1223
            cameraNode.Quaternion = _cameraNodeOrientation; // :1238
            camera.KeepAspect = Camera3D.KeepAspectEnum.Height;
            camera.Fov = _cameraFOV;                        // :1239
            camera.Near = _cameraNearCap;                   // :1240 SetCapping
            camera.Far = _cameraFarCap;
        }
    }
}
