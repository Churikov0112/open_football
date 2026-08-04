using System.Collections.Generic;
using System.Globalization;
using Godot;

namespace Gpf.Lab
{
    // Разбор сценария оракула — зеркало src/oracle/oraclescenario.cpp в форке эталона.
    // Один и тот же файл читают обе стороны, поэтому синтаксис и набор ошибок обязаны совпадать:
    // строка, которую одна сторона проглотила, а другая отвергла, дала бы ложное совпадение трасс.
    //
    // Дельта-кодирование: строка на ИЗМЕНЕНИЕ ввода, состояние держится до следующего изменения.
    //
    //   # walk_line: разгон по прямой, поворот на 90°, торможение
    //   seed 20260731
    //   ticks 1200
    //   0    dir 0,-1,0   buttons Sprint
    //   400  dir 1,0,0
    //   900  buttons -
    public partial class OracleScenario : RefCounted
    {
        // Порядок обязан совпадать с e_ButtonFunction (hid/ihidevice.hpp:17-37).
        public const int BtnUp = 0, BtnRight = 1, BtnDown = 2, BtnLeft = 3;
        public const int BtnLongPass = 4, BtnHighPass = 5, BtnShortPass = 6, BtnShot = 7;
        public const int BtnKeeperRush = 8, BtnSliding = 9, BtnPressure = 10, BtnTeamPressure = 11;
        public const int BtnSwitch = 12, BtnSpecial = 13, BtnSprint = 14, BtnDribble = 15;
        public const int BtnSelect = 16, BtnStart = 17;
        public const int BtnSize = 18;

        private static readonly string[] ButtonNames =
        {
            "Up", "Right", "Down", "Left",
            "LongPass", "HighPass", "ShortPass", "Shot",
            "KeeperRush", "Sliding", "Pressure", "TeamPressure",
            "Switch", "Special", "Sprint", "Dribble",
            "Select", "Start",
        };

        private struct State
        {
            public Vector3 Direction;
            public bool[] Buttons;
        }

        private ulong _seed;
        private int _ticks;
        private readonly List<State> _statePerTick = new();

        public string Error { get; private set; } = "";
        public ulong GetSeed() => _seed;
        public int GetTicks() => _ticks;

        // Тик вне [0, ticks) — «ввода нет»: нулевое направление (дедзона) и все кнопки отжаты.
        public Vector3 GetDirection(int tick) =>
            tick < 0 || tick >= _statePerTick.Count ? Vector3.Zero : _statePerTick[tick].Direction;

        public bool GetButton(int tick, int button) =>
            tick >= 0 && tick < _statePerTick.Count && _statePerTick[tick].Buttons[button];

        private sealed class Event
        {
            public int Tick;
            public bool HasDirection;
            public Vector3 Direction;
            public bool HasButtons;
            public bool[] Buttons = new bool[BtnSize];
        }

        public bool Load(string path)
        {
            Error = "";
            _seed = 0;
            _ticks = 0;
            _statePerTick.Clear();

            using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
            if (file == null)
            {
                Error = $"{path}: файл сценария не открывается ({Godot.FileAccess.GetOpenError()})";
                return false;
            }

            bool haveSeed = false, haveTicks = false;
            var events = new List<Event>();
            int lineNumber = 0;

            while (!file.EofReached())
            {
                string rawLine = file.GetLine();
                lineNumber++;

                int comment = rawLine.IndexOf('#');
                if (comment >= 0) rawLine = rawLine.Substring(0, comment);

                string[] tokens = rawLine.Split(new[] { ' ', '\t', '\r' },
                    System.StringSplitOptions.RemoveEmptyEntries);
                if (tokens.Length == 0) continue;

                if (tokens[0] == "seed")
                {
                    if (events.Count > 0) return Fail(path, lineNumber, "seed обязан стоять до первой строки тика");
                    if (haveSeed) return Fail(path, lineNumber, "seed уже задан");
                    if (tokens.Length != 2) return Fail(path, lineNumber, "seed требует ровно одно значение");
                    if (!ulong.TryParse(tokens[1], NumberStyles.None, CultureInfo.InvariantCulture, out _seed))
                        return Fail(path, lineNumber, $"seed не число: '{tokens[1]}'");
                    haveSeed = true;
                    continue;
                }

                if (tokens[0] == "ticks")
                {
                    if (events.Count > 0) return Fail(path, lineNumber, "ticks обязан стоять до первой строки тика");
                    if (haveTicks) return Fail(path, lineNumber, "ticks уже задан");
                    if (tokens.Length != 2) return Fail(path, lineNumber, "ticks требует ровно одно значение");
                    if (!int.TryParse(tokens[1], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out _ticks)
                        || _ticks <= 0)
                        return Fail(path, lineNumber, $"ticks не положительное число: '{tokens[1]}'");
                    haveTicks = true;
                    continue;
                }

                var ev = new Event();
                if (!int.TryParse(tokens[0], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out ev.Tick))
                    return Fail(path, lineNumber, $"неизвестная директива '{tokens[0]}'");
                if (!haveSeed || !haveTicks)
                    return Fail(path, lineNumber, "seed и ticks обязаны стоять до первой строки тика");
                if (ev.Tick < 0) return Fail(path, lineNumber, "отрицательный номер тика");
                if (ev.Tick >= _ticks) return Fail(path, lineNumber, $"номер тика '{tokens[0]}' вне длины прогона");
                if (events.Count > 0 && ev.Tick < events[events.Count - 1].Tick)
                    return Fail(path, lineNumber, "номера тиков идут не по возрастанию");

                for (int t = 1; t < tokens.Length; t++)
                {
                    if (tokens[t] == "dir")
                    {
                        if (t + 1 >= tokens.Length) return Fail(path, lineNumber, "dir без вектора");
                        if (!ParseVector(tokens[t + 1], out ev.Direction))
                            return Fail(path, lineNumber, $"dir не вектор x,y,z: '{tokens[t + 1]}'");
                        ev.HasDirection = true;
                        t++;
                        continue;
                    }

                    if (tokens[t] == "buttons")
                    {
                        if (t + 1 >= tokens.Length) return Fail(path, lineNumber, "buttons без списка");
                        string list = tokens[t + 1];
                        ev.HasButtons = true;
                        if (list != "-")
                        {
                            foreach (string name in list.Split('|'))
                            {
                                if (name.Length == 0) return Fail(path, lineNumber, $"пустое имя кнопки в '{list}'");
                                int found = System.Array.IndexOf(ButtonNames, name);
                                if (found < 0) return Fail(path, lineNumber, $"неизвестная кнопка '{name}'");
                                // Switch переводит управление на другого игрока (team.cpp:368-393) —
                                // строки трассы с controlled = 1 начали бы принадлежать разным людям.
                                if (found == BtnSwitch) return Fail(path, lineNumber, "кнопка Switch в сценарии запрещена");
                                ev.Buttons[found] = true;
                            }
                        }
                        t++;
                        continue;
                    }

                    return Fail(path, lineNumber, $"неизвестный токен '{tokens[t]}'");
                }

                if (!ev.HasDirection && !ev.HasButtons)
                    return Fail(path, lineNumber, "строка тика без dir и без buttons — no-op запрещён");

                events.Add(ev);
            }

            if (!haveSeed) { Error = $"{path}: обязательная директива seed отсутствует"; return false; }
            if (!haveTicks) { Error = $"{path}: обязательная директива ticks отсутствует"; return false; }

            // Разворачиваем дельта-кодирование: состояние держится до следующего изменения.
            var current = new State { Direction = Vector3.Zero, Buttons = new bool[BtnSize] };
            int nextEvent = 0;
            for (int tick = 0; tick < _ticks; tick++)
            {
                while (nextEvent < events.Count && events[nextEvent].Tick == tick)
                {
                    Event ev = events[nextEvent];
                    if (ev.HasDirection) current.Direction = ev.Direction;
                    if (ev.HasButtons) current.Buttons = (bool[])ev.Buttons.Clone();
                    nextEvent++;
                }
                _statePerTick.Add(new State { Direction = current.Direction, Buttons = current.Buttons });
            }

            return true;
        }

        private bool Fail(string path, int lineNumber, string message)
        {
            Error = $"{path}:{lineNumber}: {message}";
            return false;
        }

        private static bool ParseVector(string token, out Vector3 result)
        {
            result = Vector3.Zero;
            string[] parts = token.Split(',');
            if (parts.Length != 3) return false;
            var coords = new float[3];
            for (int i = 0; i < 3; i++)
            {
                if (parts[i].Length == 0) return false;
                if (!float.TryParse(parts[i], NumberStyles.Float, CultureInfo.InvariantCulture, out coords[i]))
                    return false;
            }
            result = new Vector3(coords[0], coords[1], coords[2]);
            return true;
        }
    }
}
