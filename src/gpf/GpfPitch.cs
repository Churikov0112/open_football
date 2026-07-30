using Godot;

namespace Gpf
{
    // Константы поля/игры оригинала (gamedefines.hpp) — ДАННЫЕ, не тюнинг: трогать их можно только
    // вслед за C++. Ядро порта живёт в «их» размерах поля; сведение с нашим FIFA-полем
    // (FootballConstants) — не задача фазы 4, лаба гоняется прямо в этих числах.
    // RefCounted (не static class) — чтобы GDScript видел скрипт через load(); через мост доступны
    // только статические МЕТОДЫ, поэтому у каждой константы есть Get-обёртка
    // (тот же паттерн, что Velo.GetAnimSprint()).
    public partial class GpfPitch : RefCounted
    {
        public const float PitchHalfW = 55f;   // gamedefines.hpp:271 (только внутри боковых/лицевых линий)
        public const float PitchHalfH = 36f;   // gamedefines.hpp:272
        public const float LineHalfW = 0.06f;  // gamedefines.hpp:275

        public const float GoalDepth = 2.55f;     // gamedefines.hpp:277
        public const float GoalHeight = 2.5f;     // gamedefines.hpp:278
        public const float GoalHalfWidth = 3.7f;  // gamedefines.hpp:279

        public const int BallPredictionSizeMs = 3000; // gamedefines.hpp:56
        public const int BallHistorySizeMs = 4000;    // gamedefines.hpp:57
        public const float BallDistanceOptimizeThreshold = 10f; // gamedefines.hpp:59

        // «Насколько глубоко в анимацию обычно приходится касание мяча» (комментарий оригинала).
        public const int DefaultTouchOffsetMs = 80;     // gamedefines.hpp:64
        public const float DefaultPlayerHeight = 1.92f; // gamedefines.hpp:66

        // Мост-обёртки для GDScript-тестов (const-поля через CSharpScript не читаются).
        public static float GetPitchHalfW() => PitchHalfW;
        public static float GetPitchHalfH() => PitchHalfH;
        public static float GetLineHalfW() => LineHalfW;
        public static float GetGoalDepth() => GoalDepth;
        public static float GetGoalHeight() => GoalHeight;
        public static float GetGoalHalfWidth() => GoalHalfWidth;
        public static int GetBallPredictionSizeMs() => BallPredictionSizeMs;
        public static int GetBallHistorySizeMs() => BallHistorySizeMs;
        public static float GetBallDistanceOptimizeThreshold() => BallDistanceOptimizeThreshold;
        public static int GetDefaultTouchOffsetMs() => DefaultTouchOffsetMs;
        public static float GetDefaultPlayerHeight() => DefaultPlayerHeight;
    }
}
