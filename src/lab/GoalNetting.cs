using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Порт Match::PrepareGoalNetting / UpdateGoalNetting / UploadGoalNetting
    // (match.cpp:2140-2215). ПРЕЗЕНТАЦИЯ: своей коллизии тут нет — вход только флаг
    // касания сетки из физики (`Gpf.Ball.BallTouchesNet()`, тикет 05) и позиция мяча.
    // Мяч снаружи ворот сетку не деформирует ровно потому, что физика этот флаг не
    // выставляет (внешние ветки в оригинале закомментированы).
    //
    // Состояние (nettingMeshes/nettingMeshesSrc/resetNetting/nettingHasChanged,
    // match.hpp:353-365) — поля Match, поэтому экземплярный класс, а не статики.
    public partial class GoalNetting : RefCounted
    {
        // :2148-2149 — «don't catch woodwork, only netting.. DIRTY HAXX»: порог отсекает
        // штанги, оставляя 1138 вершин на сторону (пинится check_gpf_stadium.gd).
        private const float NettingThresholdMargin = 0.06f;

        // Одна поверхность одного меша: копия вершин-источника, рабочая копия и индексы
        // вершин, прошедших фильтр, — раздельно по сторонам (nettingMeshes[0..1]).
        private sealed class Surface
        {
            public Godot.Collections.Array Arrays = new();
            public Material? SlotMaterial;
            public Vector3[] Src = System.Array.Empty<Vector3>(); // nettingMeshesSrc
            public Vector3[] Work = System.Array.Empty<Vector3>();
            public readonly int[][] SideIndices = new int[2][];   // nettingMeshes[side]
        }

        private sealed class Target
        {
            public MeshInstance3D Instance = null!;
            public ArrayMesh Mesh = null!;
            public Surface[] Surfaces = System.Array.Empty<Surface>();
            public Material?[] Overrides = System.Array.Empty<Material?>();
        }

        private readonly List<Target> _targets = new();
        private bool _resetNetting;      // match.cpp:49
        private bool _nettingHasChanged; // match.cpp:50

        // :2140-2157. Отличие от оригинала вынужденное: тот пишет прямо в вершинный буфер
        // ресурса геометрии, а у нас импортированный меш ОБЩИЙ для всех экземпляров
        // сцены (тот же довод, что у перекрытий материалов в AseMaterials) — поэтому
        // мешам с сеткой выдаётся собственная копия ArrayMesh, её и деформируем.
        //
        // Вершины `.glb` лежат в координатах оригинала, трансформы узлов единичные
        // (инвариант конвейера, пинится check_gpf_stadium.gd) — как и у оригинала, где
        // goalsNode в режиме e_LocalMode_Absolute.
        public void Prepare(Node goalsRoot)
        {
            var instances = new List<MeshInstance3D>();
            Collect(goalsRoot, instances);

            foreach (MeshInstance3D instance in instances)
            {
                if (instance.Mesh == null) continue;

                int surfaceCount = instance.Mesh.GetSurfaceCount();
                var surfaces = new Surface[surfaceCount];
                bool anyNetting = false;

                for (int s = 0; s < surfaceCount; s++)
                {
                    Godot.Collections.Array arrays = instance.Mesh.SurfaceGetArrays(s);
                    var verts = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();

                    var side0 = new List<int>();
                    var side1 = new List<int>();
                    for (int i = 0; i < verts.Length; i++)
                    {
                        // :2147-2149 — goalID: −1 (не сетка), 0 (левые ворота), 1 (правые)
                        if (verts[i].X < -GpfPitch.PitchHalfW - NettingThresholdMargin) side0.Add(i);
                        else if (verts[i].X > GpfPitch.PitchHalfW + NettingThresholdMargin) side1.Add(i);
                    }

                    var surface = new Surface
                    {
                        Arrays = arrays,
                        SlotMaterial = instance.Mesh.SurfaceGetMaterial(s),
                        Src = (Vector3[])verts.Clone(),
                        Work = (Vector3[])verts.Clone(),
                    };
                    surface.SideIndices[0] = side0.ToArray();
                    surface.SideIndices[1] = side1.ToArray();
                    surfaces[s] = surface;
                    if (side0.Count + side1.Count > 0) anyNetting = true;
                }

                if (!anyNetting) continue; // штанги/каркас — деформировать нечего

                var target = new Target
                {
                    Instance = instance,
                    Mesh = new ArrayMesh(),
                    Surfaces = surfaces,
                    Overrides = new Material?[surfaceCount],
                };
                for (int s = 0; s < surfaceCount; s++)
                    target.Overrides[s] = instance.GetSurfaceOverrideMaterial(s);

                Rebuild(target);
                instance.Mesh = target.Mesh;
                ApplyOverrides(target);
                _targets.Add(target);
            }
        }

        // :2159-2209 UpdateGoalNetting. ballPosition — позиция УЗЛА мяча
        // (ball->GetBallGeom()->GetPosition(), то есть positionBuffer), не Predict(0).
        public void Update(bool ballTouchesNet, Vector3 ballPosition)
        {
            _nettingHasChanged = false;                       // :2161
            int sideId = (ballPosition.X < 0) ? 0 : 1;        // :2162

            if (ballTouchesNet) // :2163
            {
                // ближайшая к мячу вершина этой стороны (:2164-2174)
                float shortestDistance = 100000.0f;
                foreach (Target target in _targets)
                {
                    foreach (Surface surface in target.Surfaces)
                    {
                        foreach (int i in surface.SideIndices[sideId])
                        {
                            float distance = GetDistance(surface.Src[i], ballPosition); // :2169
                            if (distance < shortestDistance) shortestDistance = distance;
                        }
                    }
                }

                // подтягивание вершин к мячу: чем ближе, тем сильнее (:2176-2193)
                foreach (Target target in _targets)
                {
                    foreach (Surface surface in target.Surfaces)
                    {
                        foreach (int i in surface.SideIndices[sideId])
                        {
                            Vector3 vertex = surface.Src[i]; // :2178
                            // :2179-2180 — falloffDistance 4.0 и линейный falloff в
                            // оригинале закомментированы, живёт степенной:
                            // float influenceBias = clamp(1.0f - (vertex.GetDistance(ballPos) - shortestDistance) / falloffDistance, 0.0f, 1.0f);
                            float influenceBias = Mathf.Pow(Mathf.Clamp(
                                (shortestDistance + 0.0001f)
                                / (GetDistance(vertex, ballPosition) + 0.0001f), 0.0f, 1.0f), 1.5f); // :2181

                            // сетка прибита к штангам — возле них ослабление (:2182-2183);
                            // тот же квирк, что в физике, но здесь от ПОЗИЦИИ мяча
                            float woodworkTensionBiasInv = Mathf.Clamp(
                                (Mathf.Abs(ballPosition.X) - GpfPitch.PitchHalfW) * 2.0f, 0.0f, 1.0f);
                            influenceBias *= woodworkTensionBiasInv; // :2184

                            // :2185-2186 — сглаживание синусом (ссылка на wolframalpha в оригинале)
                            influenceBias = Mathf.Sin(influenceBias * Mathf.Pi - 0.5f * Mathf.Pi)
                                * 0.5f + 0.5f;
                            if (influenceBias > 0.0f) // :2187
                            {
                                // :2188-2191 — нормали НЕ пересчитываются, как в оригинале
                                surface.Work[i] = vertex * (1.0f - influenceBias)
                                    + ballPosition * influenceBias;
                            }
                        }
                    }
                }

                _resetNetting = true;     // :2194 — в следующий раз обязательно вернуть форму
                _nettingHasChanged = true; // :2195
            }
            else if (_resetNetting) // :2197 — мяч сетки (больше) не касается, возврат формы
            {
                foreach (Target target in _targets)
                {
                    foreach (Surface surface in target.Surfaces)
                    {
                        for (int side = 0; side < 2; side++) // :2198
                        {
                            foreach (int i in surface.SideIndices[side])
                                surface.Work[i] = surface.Src[i]; // :2200-2202
                        }
                    }
                }
                _resetNetting = false;     // :2205
                _nettingHasChanged = true; // :2206
            }
        }

        // :2211-2215 UploadGoalNetting — заливка в геометрию только когда что-то менялось.
        public void Upload()
        {
            if (!_nettingHasChanged) return; // :2212
            foreach (Target target in _targets)
            {
                Rebuild(target);      // :2213 — OnUpdateGeometryData
                ApplyOverrides(target);
            }
        }

        // Пересборка собственного ArrayMesh из рабочих массивов. У оригинала на этом месте
        // заливка изменённого вершинного буфера в GPU; поверхностей у ворот две, вершин
        // 2448 — пересборка идёт только в кадры, когда сетка менялась.
        private static void Rebuild(Target target)
        {
            target.Mesh.ClearSurfaces();
            for (int s = 0; s < target.Surfaces.Length; s++)
            {
                Surface surface = target.Surfaces[s];
                surface.Arrays[(int)Mesh.ArrayType.Vertex] = surface.Work;
                target.Mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, surface.Arrays);
                if (surface.SlotMaterial != null)
                    target.Mesh.SurfaceSetMaterial(s, surface.SlotMaterial);
            }
        }

        // Перекрытия материалов живут на УЗЛЕ и считаются по числу поверхностей меша —
        // после подмены меша их надо поставить заново (материалы назначил AseMaterials).
        private static void ApplyOverrides(Target target)
        {
            for (int s = 0; s < target.Overrides.Length; s++)
                if (target.Overrides[s] != null)
                    target.Instance.SetSurfaceOverrideMaterial(s, target.Overrides[s]);
        }

        // vector3.cpp:230-244 GetDistance — те же два квирка, что у GetLength:
        // ранний выход на нулевой разнице и обнуление длины меньше 1e-6.
        private static float GetDistance(Vector3 a, Vector3 b)
        {
            float x = a.X - b.X, y = a.Y - b.Y, z = a.Z - b.Z;
            if (x == 0.0f && y == 0.0f && z == 0.0f) return 0.0f;
            float length = Mathf.Sqrt(x * x + y * y + z * z);
            if (length < 0.000001f) length = 0f;
            return length;
        }

        private static void Collect(Node node, List<MeshInstance3D> into)
        {
            if (node is MeshInstance3D hit) into.Add(hit);
            foreach (Node child in node.GetChildren()) Collect(child, into);
        }
    }
}
