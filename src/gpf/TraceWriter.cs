using System.Collections.Generic;
using System.Globalization;
using System.Text;
using Godot;

namespace Gpf
{
    // Писатель трассы оракула — зеркало src/oracle/oracletrace.cpp в форке эталона.
    // Формат — источник истины в .scratch/oracle/spec.md, живой образец — .scratch/oracle/trace-example.md;
    // общего кода у сторон нет, набор колонок держится руками синхронно.
    //
    // Зовётся ОРКЕСТРАТОРОМ ТИКА (BallLabMain), а не изнутри ядра: оригинал зовёт свой дамп в конце
    // Match::Process, и на фазе 8 этот вызов переедет в портированный Match без правки писателя.
    // Ядро (HumanoidBase, Ball, отбор клипа) про файлы и формат не знает.
    public partial class TraceWriter : RefCounted
    {
        // Дословно заголовок эталона. Имена относятся к P-строке как самой длинной; у B-строки своя
        // схема (kind, tick, затем шесть значений мяча, дальше пусто до 23 полей).
        public const string Header =
            "kind,tick,player_id,controlled,anim_name,anim_id,anim_type,function_type,frame_num,touch_frame,"
            + "foot,enum_velocity,quadrant_id,pos_x,pos_y,pos_z,angle,rel_body_angle,move_x,move_y,move_z,"
            + "action_smuggle,movement_smuggle";

        public const string ManifestHeader = "index,anim_name,anim_type,foot,frame_count";

        private const int FieldCount = 23;

        // Мост для GDScript-тестов: const-поля через мост не читаются, только методы (тот же приём,
        // что у Velo.GetAnimSprint).
        public string GetHeader() => Header;
        public string GetManifestHeader() => ManifestHeader;

        private Godot.FileAccess _file = null!;

        // Инвариантная культура на каждом float: региональные настройки Windows иначе подставят
        // запятую и трасса перестанет быть CSV. Тот же инвариант уже ловил парсинг .anim.
        private static string F(float value) => value.ToString("F6", CultureInfo.InvariantCulture);
        private static string I(int value) => value.ToString(CultureInfo.InvariantCulture);

        // Имя клипа относительно animations/: прямые слэши, нижний регистр, без расширения .anim.
        // У зеркал расширение стоит в середине (`000.anim_mirror`), потому что Mirror дописывает
        // суффикс к готовому имени (Animation.cs:785 ↔ animation.cpp:1247).
        public static string NormalizeAnimName(string rawName)
        {
            string name = rawName.Replace('\\', '/');

            const string root = "animations/";
            int rootPos = name.IndexOf(root, System.StringComparison.Ordinal);
            if (rootPos >= 0) name = name.Substring(rootPos + root.Length);

            const string extension = ".anim";
            int extensionPos = name.IndexOf(extension, System.StringComparison.Ordinal);
            if (extensionPos >= 0) name = name.Remove(extensionPos, extension.Length);

            name = name.ToLowerInvariant();

            // Запятая сломала бы CSV. По построению её там нет — ни в путях, ни в формуле автогена
            // (AnimCollection.cs:252), — но молча испортить трассу хуже, чем упасть.
            if (name.Contains(',')) GD.PushError($"Gpf.TraceWriter: запятая в имени клипа: {name}");

            return name;
        }

        public bool BeginTrace(string path)
        {
            _file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Write);
            if (_file == null)
            {
                GD.PushError($"Gpf.TraceWriter: трасса не открывается на запись: {path} "
                    + $"({Godot.FileAccess.GetOpenError()})");
                return false;
            }
            _file.StoreLine(Header);
            return true;
        }

        public bool WriteManifest(string path, AnimCollection collection)
        {
            using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Write);
            if (file == null)
            {
                GD.PushError($"Gpf.TraceWriter: манифест не открывается на запись: {path} "
                    + $"({Godot.FileAccess.GetOpenError()})");
                return false;
            }

            file.StoreLine(ManifestHeader);
            for (int i = 0; i < collection.GetAnimationCount(); i++)
            {
                Animation animation = collection.GetAnim(i);
                file.StoreLine(I(i) + "," + NormalizeAnimName(animation.GetName()) + ","
                    + animation.GetAnimType() + "," + I(animation.GetOutgoingFootId()) + ","
                    + I(animation.GetFrameCount()));
            }
            return true;
        }

        // Строка мяча. В вердикт фазы 5 не входит, но из неё порт берёт стартовую позицию мяча, а
        // дифф считает дистанцию для проверки безопасной области.
        public void WriteBall(int tick, Vector3 position, Vector3 momentum)
        {
            var fields = new List<string> { "B", I(tick) };
            fields.Add(F(position.X)); fields.Add(F(position.Y)); fields.Add(F(position.Z));
            fields.Add(F(momentum.X)); fields.Add(F(momentum.Y)); fields.Add(F(momentum.Z));
            WriteRow(fields);
        }

        // Строка игрока. player_id у порта всегда 0, controlled всегда 1: гуманоид в лабе один,
        // а спаривание трасс идёт по (tick, controlled = 1), не по player_id.
        public void WritePlayer(int tick, HumanoidBase humanoid, Animation anim)
        {
            var fields = new List<string>
            {
                "P",
                I(tick),
                "0",
                "1",
                NormalizeAnimName(anim.GetName()),
                I(humanoid.GetCurrentAnimId()),
                anim.GetAnimType(),
                I(humanoid.GetCurrentFunctionType()),
                I(humanoid.GetCurrentFrameNum()),
                I(humanoid.GetCurrentTouchFrame()),
                I(humanoid.GetFoot()),
                I(humanoid.GetSpatialEnumVelocity()),
                I(BluntMath.AtoI(anim.GetVariable("quadrant_id"))),
            };

            Vector3 position = humanoid.GetSpatialPosition();
            fields.Add(F(position.X)); fields.Add(F(position.Y)); fields.Add(F(position.Z));
            fields.Add(F(humanoid.GetSpatialAngle()));
            // Публичного геттера на spatialState.relBodyAngle нет; та же формула, которой поле
            // считается внутри (HumanoidBase.cs:667).
            fields.Add(F(BluntMath.GetAngle2D(humanoid.GetRelBodyDirectionVec(), new Vector3(0, -1, 0))));
            Vector3 movement = humanoid.GetSpatialMovement();
            fields.Add(F(movement.X)); fields.Add(F(movement.Y)); fields.Add(F(movement.Z));
            fields.Add(F(humanoid.GetActionSmuggle().Length()));
            fields.Add(F(humanoid.GetMovementSmuggle().Length()));

            WriteRow(fields);
        }

        private void WriteRow(List<string> fields)
        {
            var line = new StringBuilder();
            for (int i = 0; i < FieldCount; i++)
            {
                if (i > 0) line.Append(',');
                if (i < fields.Count) line.Append(fields[i]);
            }
            _file.StoreLine(line.ToString());
        }

        public void End()
        {
            if (_file == null) return;
            _file.Close();
            _file = null!;
        }
    }
}
