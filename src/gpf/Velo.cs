using Godot;

namespace Gpf
{
    // Скорости GameplayFootball: константы gamedefines.hpp:18-27, конверсии animcollection.hpp:57-104,
    // GetVelocityID utils.cpp:81-102. Enum-иды скоростей гоняем как int (мост GDScript↔C#):
    // 0 idle / 1 dribble / 2 walk / 3 sprint.
    public partial class Velo : RefCounted
    {
        public const float Idle = 0.0f;               // gamedefines.hpp:18
        public const float Dribble = 3.5f;            // gamedefines.hpp:19
        public const float Walk = 5.0f;               // gamedefines.hpp:20
        public const float Sprint = 8.0f;             // gamedefines.hpp:21
        public const float IdleDribbleSwitch = 1.8f;  // gamedefines.hpp:25
        public const float DribbleWalkSwitch = 4.2f;  // gamedefines.hpp:26
        public const float WalkSprintSwitch = 6.0f;   // gamedefines.hpp:27

        public const int IdVelIdle = 0;
        public const int IdVelDribble = 1;
        public const int IdVelWalk = 2;
        public const int IdVelSprint = 3;

        // animcollection.hpp:57-63
        public static float RangeVelocity(float velocity)
        {
            float ret = Idle;
            if (velocity >= IdleDribbleSwitch && velocity < DribbleWalkSwitch) ret = Dribble;
            else if (velocity >= DribbleWalkSwitch && velocity < WalkSprintSwitch) ret = Walk;
            else if (velocity >= WalkSprintSwitch) ret = Sprint;
            return ret;
        }

        // animcollection.hpp:65-69
        public static float ClampVelocity(float velocity)
        {
            if (velocity < 0) return 0;
            if (velocity > Sprint) return Sprint;
            return velocity;
        }

        // animcollection.hpp:71-77 (да, ветвление оригинала именно такое)
        public static float FloorVelocity(float velocity)
        {
            float ret = Idle;
            if (velocity > 0 && velocity < Dribble) ret = Dribble;
            else if (velocity <= Walk) ret = Walk;
            else ret = Sprint;
            return ret;
        }

        // animcollection.hpp:79-95
        public static float EnumToFloatVelocity(int id) => id switch
        {
            IdVelIdle => Idle,
            IdVelDribble => Dribble,
            IdVelWalk => Walk,
            IdVelSprint => Sprint,
            _ => 0,
        };

        // animcollection.hpp:97-104
        public static int FloatToEnumVelocity(float velocity)
        {
            float ranged = RangeVelocity(velocity);
            if (ranged == Idle) return IdVelIdle;
            if (ranged == Dribble) return IdVelDribble;
            if (ranged == Walk) return IdVelWalk;
            if (ranged == Sprint) return IdVelSprint;
            return IdVelIdle;
        }

        // utils.cpp:81-102
        public static int GetVelocityID(int id, bool treatDribbleAsWalk = false)
        {
            int result = id is >= 0 and <= 3 ? id : 0;
            if (treatDribbleAsWalk && result > 1) result--;
            return result;
        }
    }
}
