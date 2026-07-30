using Godot;

namespace Gpf
{
    // Порт struct SpatialState (humanoidbase.hpp:172-194). В C++ это POD без конструктора;
    // де-факто начальные значения задаёт HumanoidBase::ResetPosition (humanoidbase.cpp:929-947),
    // вызываемый из конструктора HumanoidBase (:170) — дефолты ниже повторяют его (:937-947).
    // Actual/Physics/Anim/SmuggleMovement-поля в ResetPosition не задаются (их перезапишет первый
    // UpdateSpatialState), RelBody*Nonquantized — тоже; здесь для них нули/(0,-1,0) как
    // определённый старт. Обычный C#-класс: через мост не ходит, наружу его отдаёт
    // HumanoidBase геттерами (задача 4).
    public class SpatialState
    {
        public Vector3 Position = Vector3.Zero;              // :937
        public float Angle = 0f;                             // :938
        public Vector3 DirectionVec = new Vector3(0, -1, 0); // :939 — векторная версия Angle
        public int EnumVelocity = Velo.IdVelIdle;            // :941
        public float FloatVelocity = 0f;                     // :940

        public Vector3 ActualMovement = Vector3.Zero;
        public Vector3 PhysicsMovement = Vector3.Zero;  // игнорирует positionoffset-эффекты (hpp:180)
        public Vector3 AnimMovement = Vector3.Zero;
        public Vector3 Movement = Vector3.Zero;         // одно из трёх выше (default, hpp:182); :942
        public Vector3 ActionSmuggleMovement = Vector3.Zero;    // нули до фазы 4
        public Vector3 MovementSmuggleMovement = Vector3.Zero;  // нули до фазы 4
        public Vector3 PositionOffsetMovement = Vector3.Zero;   // нули до фазы 4

        public float BodyAngle = 0f;                                // :946
        public Vector3 BodyDirectionVec = new Vector3(0, -1, 0);    // :945
        public float RelBodyAngleNonquantized = 0f;
        public float RelBodyAngle = 0f;                             // :944
        public Vector3 RelBodyDirectionVec = new Vector3(0, -1, 0); // :943
        public Vector3 RelBodyDirectionVecNonquantized = new Vector3(0, -1, 0);
        // humanoidbase.cpp:947 — e_Foot_Right. Бриф задачи ссылался на humanoidbase.hpp:117
        // (e_Foot_Left) — но это конструктор ДРУГОЙ структуры (IdealAnimDescription);
        // у SpatialState конструктора нет, оригинал побеждает.
        public int Foot = Animation.FootRight;
    }
}
