using Godot;

namespace Gpf.Lab
{
    // Звуковой слой лабы (тикет 08): плееры касания мяча и удара о штангу. Зеркало звуковой
    // части Ball оригинала — загрузка (ball.cpp:46-68), гейн штанги (:324-327) и
    // TriggerBallTouchSound (:553-560).
    //
    // Почему тут, а не в `Gpf.Ball`: ядро отдаёт наружу только СИГНАЛЫ (факт касания с гейном,
    // факт woodwork с силой) и не знает ни про аудио-узлы Godot, ни про конфиг — тот же приём,
    // что у TraceWriter. Значит формулы, которым нужен `audio_volume` и презентационный ГСЧ,
    // живут здесь.
    //
    // Крауд (crowd01/02.wav) и свисток (whistle2/3.wav) — фаза 8: файлы в репозитории есть,
    // проводки здесь нет.
    public partial class MatchAudio : RefCounted
    {
        // GetConfiguration()->GetReal("audio_volume", 0.5f) — конфига в порте нет, живёт дефолт.
        public const float AudioVolume = 0.5f;

        private const string BallSoundWav = "res://assets/gpf/media/sounds/ballsound.wav";
        private const string GoalpostWav = "res://assets/gpf/media/sounds/goalpost.wav";

        private AudioStreamPlayer _ballSound = null!;
        private AudioStreamPlayer _goalpostSound = null!;

        // ball.cpp:554 — финальный гейн касания. Аргумент приходит из шва ядра:
        // pow(NormalizedClamp(|touchVec|, 4, 40), 0.7).
        public static float TouchGain(float gain) => gain * 0.6f * AudioVolume;

        // ball.cpp:555 — порог слышимости: тихие касания не звучат вовсе.
        public static bool TouchAudible(float gain) => TouchGain(gain) > 0.01f;

        // ball.cpp:556 — питч гуляет от касания к касанию; числа — из ПРЕЗЕНТАЦИОННОГО ГСЧ
        // (геймплейный поток трогать нельзя, тикет .scratch/oracle/issues/17-...).
        public static float TouchPitch(Gpf.GpfRng rng) => 0.9f + rng.Uniform(0.0f, 0.2f);

        // ball.cpp:325 — гейн штанги от силы удара, с клампом снизу 0.01 и сверху 1.0.
        public static float WoodworkGain(float momentumLength)
            => Mathf.Clamp(momentumLength * 0.05f, 0.01f, 1.0f) * 0.5f * AudioVolume;

        // ball.cpp:46-68: два ненаправленных плеера. У оригинала это объекты 3D-сцены, но
        // позиция им не задаётся ни разу — то есть звук и там ненаправленный.
        public void Setup(Node parent)
        {
            _ballSound = MakePlayer(parent, "BallSound", BallSoundWav);
            _goalpostSound = MakePlayer(parent, "GoalpostSound", GoalpostWav);
            // :54, :64 — базовый гейн 0.7 * audio_volume; и там, и тут он перезаписывается
            // перед каждым проигрыванием, поэтому переносится комментарием, а не полем.
        }

        private static AudioStreamPlayer MakePlayer(Node parent, string name, string wavPath)
        {
            var player = new AudioStreamPlayer { Name = name };
            if (ResourceLoader.Exists(wavPath)) player.Stream = GD.Load<AudioStream>(wavPath);
            else GD.PushWarning($"MatchAudio: нет {wavPath} — тикет 01 клал звуки в репозиторий");
            parent.AddChild(player);
            return player;
        }

        // ball.cpp:553-560. Повторный вызов перезапускает тот же плеер — как Poke оригинала,
        // который дёргает один и тот же объект Sound.
        public void PlayBallTouch(float gain, Gpf.GpfRng rng)
        {
            if (!TouchAudible(gain)) return;          // :555
            _ballSound.PitchScale = TouchPitch(rng);  // :556
            _ballSound.VolumeDb = Mathf.LinearToDb(TouchGain(gain)); // :557 — SetGain линейный
            _ballSound.Play();                        // :558 Poke
        }

        // ball.cpp:324-327
        public void PlayWoodwork(float momentumLength)
        {
            _goalpostSound.VolumeDb = Mathf.LinearToDb(WoodworkGain(momentumLength)); // :325
            _goalpostSound.Play();                                                    // :326
        }
    }
}
