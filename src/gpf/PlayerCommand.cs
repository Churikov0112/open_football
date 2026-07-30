using Godot;

namespace Gpf
{
    // Порт struct TouchInfo (gamedefines.hpp:145-167). Обычный C#-класс (как SpatialState):
    // через мост GDScript↔C# не ходит, живёт только внутри ядра.
    // targetPlayer/forcedTargetPlayer (:164-165) — Player* оригинала; объекта игрока в ядре порта
    // ещё нет (появится в задачах 8-9), поэтому поля-швы отсутствуют; когда появятся — добавить
    // сюда, а не в вызывающий код.
    public class TouchInfo
    {
        public Vector3 InputDirection = Vector3.Zero;   // :156
        public float InputPower = 0.0f;                 // ctor :148
        public float AutoDirectionBias = 0.0f;          // ctor :149
        public float AutoPowerBias = 0.0f;              // ctor :150
        public Vector3 DesiredDirection = Vector3.Zero; // :162 — inputDirection после пас-функции
        public float DesiredPower = 0.0f;               // ctor :153

        // В C++ TouchInfo — POD-структура внутри PlayerCommand, копируемая по значению вместе
        // с ней (humanoid.cpp:1784 `currentAnim->originatingCommand = command;`). См. PlayerCommand.Clone.
        public TouchInfo Clone() => (TouchInfo)MemberwiseClone();
    }

    // Порт struct PlayerCommand (gamedefines.hpp:175-229). Все дефолты — из конструктора
    // оригинала (:185-198), дословно. Обычный C#-класс (не RefCounted): внутренняя структура
    // ядра, мостовые обёртки собирают её сами.
    public class PlayerCommand
    {
        // e_StrictMovement (gamedefines.hpp:169-173) → int-константы (мост GDScript↔C#).
        public const int StrictFalse = 0;
        public const int StrictTrue = 1;
        public const int StrictDynamic = 2;

        // e_PlayerCommandModifier (gamedefines.hpp:138-141) — битовая маска поля Modifier;
        // потребитель — touch-ветки тика (knock-on-множитель 1.35, humanoid.cpp:373-375 и др.).
        public const int ModifierNone = 0;    // :139
        public const int ModifierKnockOn = 1; // :140

        public int DesiredFunctionType = AnimCollection.FnMovement;  // ctor :185
        public bool UseDesiredMovement = false;                      // ctor :186
        public Vector3 DesiredDirection = Vector3.Zero;              // :204
        public int StrictMovement = StrictDynamic;                   // ctor :188
        public float DesiredVelocityFloat = Velo.Idle;               // ctor :187 (idleVelocity)

        public bool UseDesiredLookAt = false;                        // ctor :189
        public Vector3 DesiredLookAt = Vector3.Zero;                 // :210 — абсолютная точка на поле

        // :212 useTouchInfo — конструктор оригинала (:185-198) его НЕ инициализирует
        // (неопределённое значение в C++); в C# дефолт false — фиксируем расхождение bug-for-bug:
        // «неинициализированный bool» воспроизвести нельзя, false — единственный детерминированный
        // выбор и совпадает с де-факто использованием (команды выставляют его явно).
        public bool UseTouchInfo = false;
        public TouchInfo TouchInfo = new TouchInfo();                // :213

        public bool OnlyDeflectAnimsThatPickupBall = false;          // ctor :192

        public bool UseTripType = false;                             // ctor :190
        public int TripType = 1;                                     // ctor :193 — только для trip-клипов

        public bool UseDesiredTripDirection = false;                 // ctor :191
        public Vector3 DesiredTripDirection = Vector3.Zero;          // :221

        public bool UseSpecialVar1 = false;                          // ctor :194
        public int SpecialVar1 = 0;                                  // ctor :195
        public bool UseSpecialVar2 = false;                          // ctor :196
        public int SpecialVar2 = 0;                                  // ctor :197

        public int Modifier = 0;                                     // ctor :198

        // КОПИЯ ПО ЗНАЧЕНИЮ. В C++ PlayerCommand — struct, и `currentAnim->originatingCommand =
        // command` (humanoid.cpp:1784) копирует её целиком; ReQueue-фильтры :1206-1207 читают
        // этот СНИМОК команды, породившей текущий клип. В C# присваивание было бы ссылкой:
        // переиспользование объекта команды вызывающим кодом задним числом «переписало» бы
        // снимок и сломало фильтр «слишком похоже на то, что уже делаем». Копируем явно.
        public PlayerCommand Clone()
        {
            var copy = (PlayerCommand)MemberwiseClone();
            copy.TouchInfo = TouchInfo.Clone(); // вложенная структура — тоже по значению
            return copy;
        }
    }
}
