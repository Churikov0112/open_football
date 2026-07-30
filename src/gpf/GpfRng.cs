using Godot;

namespace Gpf
{
    // Детерминированный PRNG ядра порта — замена unseeded boost-random() оригинала
    // (мультиплеер-дисциплина №3 роадмапа). Распределение равномерное [min,max],
    // последовательность с эталон-exe НЕ совпадает (у оригинала сид от времени) — допустимое
    // и задокументированное расхождение.
    // Алгоритм: xorshift64* (Marsaglia, 2003) — состояние 64 бита, три сдвига + умножение на
    // 0x2545F4914F6CDD1D. Зафиксирован: менять нельзя без пересчёта тестов, опирающихся на
    // конкретную последовательность.
    // RefCounted — чтобы GDScript мог инстанцировать через load(...).new().
    public partial class GpfRng : RefCounted
    {
        // Дефолт-состояние — золотое сечение в 64 битах (ненулевое: у xorshift 0 — неподвижная точка).
        private const ulong DefaultState = 0x9E3779B97F4A7C15UL;

        private ulong _state = DefaultState;

        public GpfRng() { }

        public GpfRng(ulong seed) => Reseed(seed);

        // Сид 0 запрещён самим алгоритмом (из нуля xorshift никогда не выходит) — подменяем дефолтом.
        public void Reseed(ulong seed) => _state = seed == 0 ? DefaultState : seed;

        private ulong NextRaw()
        {
            _state ^= _state >> 12;
            _state ^= _state << 25;
            _state ^= _state >> 27;
            return _state * 0x2545F4914F6CDD1DUL;
        }

        // Аналог random(min, max) оригинала. Старшие биты сырого слова → [0,1], затем линейное
        // растяжение на [min,max]. ВНИМАНИЕ: max достижим с вероятностью ~2^-25 из-за округления
        // ulong→float (максимум 2^53−1 округляется вверх до 2^53, т.е. t == 1.0f); оригинал
        // (bluntmath.cpp:20-25, boost::uniform_real<float>) — честный [0,1). Расхождение принято.
        public float Uniform(float min, float max)
        {
            float t = (NextRaw() >> 11) * (1.0f / 9007199254740992.0f); // 2^53
            return min + (max - min) * t;
        }
    }
}
