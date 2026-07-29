using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Gpf
{
    // Порт слоя выбора клипа HumanoidBase (humanoidbase.cpp): ForceInto*-таблицы (:63-97, 2547-2606),
    // предикаты сравнения (:1779-2012), _KeepBest* (:1103-1229), SelectAnim movement-путь (:1374-1496).
    // ВСЕ сортировки — только StableSort (std::stable_sort); List.Sort запрещён (нестабилен).
    public partial class AnimSelector : RefCounted
    {
        private AnimCollection _anims = null!;

        private readonly List<Vector3> _allowedBodyDirVecs = new();
        private readonly List<float> _allowedBodyDirAngles = new();
        private readonly List<Vector3> _preferredDirectionVecs = new();
        private readonly List<float> _preferredDirectionAngles = new();

        // предикаты (humanoidbase.hpp: mutable predicate_*)
        private Vector3 _predRelDesiredDirection;
        private int _predDesiredVelocityId;
        private float _predCorneringBias;
        private Vector3 _predLookAt;
        private string _predNumericVariableName = "";
        private float _predNumericVariableValue;
        private int _predDesiredFootId;
        private Vector3 _predRelIncomingBodyDirection;
        private int _predIncomingVelocityId;
        private Vector3 _spatialPosition;
        private float _spatialAngle;

        public AnimSelector()
        {
            // humanoidbase.cpp:63-97
            var fwd = new Vector3(0, -1, 0);
            foreach (float a in new[] { 0f, -0.25f, 0.25f, -0.75f, 0.75f })
                _allowedBodyDirVecs.Add(BluntMath.GetRotated2D(fwd, a * Mathf.Pi));
            foreach (float a in new[] { 0f, 0.25f, -0.25f, 0.75f, -0.75f })
                _allowedBodyDirAngles.Add(a * Mathf.Pi);
            foreach (float a in new[] { 0f, 0.111f, -0.111f, 0.25f, -0.25f, 0.5f, -0.5f, 0.75f, -0.75f, 0.999f, -0.999f })
            {
                _preferredDirectionVecs.Add(BluntMath.GetRotated2D(fwd, a * Mathf.Pi));
                _preferredDirectionAngles.Add(a * Mathf.Pi);
            }
        }

        public void Setup(AnimCollection anims) => _anims = anims;

        // std::stable_sort → LINQ OrderBy (документированно стабилен). List.Sort НЕ использовать:
        // List<T>.Sort в C# нестабилен и даёт недетерминированный выбор клипа (запрет плана фазы 2).
        internal static void StableSort(List<int> data, Func<int, int, bool> less)
        {
            var sorted = data.OrderBy(x => x, Comparer<int>.Create(
                (a, b) => less(a, b) ? -1 : less(b, a) ? 1 : 0)).ToList();
            data.Clear();
            data.AddRange(sorted);
        }

        // humanoidbase.cpp:2547-2561
        public Vector3 ForceIntoAllowedBodyDirectionVec(Vector3 src)
        {
            float bestDot = -1.0f;
            int bestIndex = 0;
            for (int i = 0; i < _allowedBodyDirVecs.Count; i++)
            {
                float nDotL = _allowedBodyDirVecs[i].Dot(src);
                if (nDotL > bestDot) { bestDot = nDotL; bestIndex = i; }
            }
            return _allowedBodyDirVecs[bestIndex];
        }

        // humanoidbase.cpp:2563-2576
        public float ForceIntoAllowedBodyDirectionAngle(float angle)
        {
            float bestDiff = 10000.0f;
            int bestIndex = 0;
            for (int i = 0; i < _allowedBodyDirAngles.Count; i++)
            {
                float diff = Mathf.Abs(_allowedBodyDirAngles[i] - angle);
                if (diff < bestDiff) { bestDiff = diff; bestIndex = i; }
            }
            return _allowedBodyDirAngles[bestIndex];
        }

        // humanoidbase.cpp:2578-2591 — та же схема по preferred-таблице векторов
        public Vector3 ForceIntoPreferredDirectionVec(Vector3 src)
        {
            float bestDot = -1.0f;
            int bestIndex = 0;
            for (int i = 0; i < _preferredDirectionVecs.Count; i++)
            {
                float d = _preferredDirectionVecs[i].Dot(src);
                if (d > bestDot) { bestDot = d; bestIndex = i; }
            }
            return _preferredDirectionVecs[bestIndex];
        }

        // humanoidbase.cpp:2593-2606
        public float ForceIntoPreferredDirectionAngle(float angle)
        {
            float bestDiff = 10000.0f;
            int bestIndex = 0;
            for (int i = 0; i < _preferredDirectionAngles.Count; i++)
            {
                float d = Mathf.Abs(_preferredDirectionAngles[i] - angle);
                if (d < bestDiff) { bestDiff = d; bestIndex = i; }
            }
            return _preferredDirectionAngles[bestIndex];
        }

        // humanoid_utils.cpp:53-66
        public static float CalculateBiasForFastCornering(Vector3 currentMovement, Vector3 desiredMovement,
                                                          float veloPow, float bias)
        {
            float angle = BluntMath.GetAngle2D(BluntMath.GetNormalized(desiredMovement, currentMovement), currentMovement);
            // wolfram: sin(x - 0.5*pi) * 0.5 + 0.5 | x = 0..pi (humanoid_utils.cpp:57)
            float currentMovementBias = Mathf.Sin(Mathf.Abs(angle) - 0.5f * Mathf.Pi) * 0.5f + 0.5f;
            // эффект слабее на малых скоростях (:61)
            float velocityBias = Mathf.Pow(Mathf.Clamp(currentMovement.Length() / (Velo.Sprint - 0.5f), 0f, 1f), veloPow);
            return velocityBias * currentMovementBias * bias;
        }

        // ---- предикаты (humanoidbase.cpp:1779-2012) ----

        // :1826-1869
        private float GetMovementSimilarity(int animIndex, Vector3 relDesiredDirection, int desiredVelocityId,
                                            float corneringBias)
        {
            Vector3 desiredMovement = relDesiredDirection * Velo.EnumToFloatVelocity(desiredVelocityId);
            Vector3 outgoingDirection = ForceIntoPreferredDirectionVec(_anims.GetAnim(animIndex).GetOutgoingDirection());
            float outgoingVelocity = Velo.RangeVelocity(_anims.GetAnim(animIndex).GetOutgoingVelocity());
            Vector3 outgoingMovement = outgoingDirection * outgoingVelocity;
            desiredMovement *= 1.0f - corneringBias; // :1844
            float value = (desiredMovement - outgoingMovement).Length();
            value -= Mathf.Abs(relDesiredDirection.Dot(outgoingDirection)) * 4.0f; // :1848 «любовь к прямым»
            return value;
        }

        private bool CompareMovementSimilarity(int a1, int a2) // :1871-1875
            => GetMovementSimilarity(a1, _predRelDesiredDirection, _predDesiredVelocityId, _predCorneringBias)
             < GetMovementSimilarity(a2, _predRelDesiredDirection, _predDesiredVelocityId, _predCorneringBias);

        private bool CompareNumericVariable(int a1, int a2) // :2009-2012
            => Mathf.Abs(BluntMath.AtoF(_anims.GetAnim(a1).GetVariable(_predNumericVariableName)) - _predNumericVariableValue)
             < Mathf.Abs(BluntMath.AtoF(_anims.GetAnim(a2).GetVariable(_predNumericVariableName)) - _predNumericVariableValue);

        private bool CompareFootSimilarity(int a1, int a2) // :1779-1787
        {
            int one = 1, two = 1;
            if (_anims.GetAnim(a1).GetCurrentFootId() == _predDesiredFootId) one = 0;
            if (_anims.GetAnim(a2).GetCurrentFootId() == _predDesiredFootId) two = 0;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetIncomingVelocity()) == Velo.IdVelIdle) one = 0;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetIncomingVelocity()) == Velo.IdVelIdle) two = 0;
            return one < two;
        }

        private bool CompareIncomingBodyDirectionSimilarity(int a1, int a2) // :1893-1900
        {
            float r1 = Mathf.Abs(BluntMath.GetAngle2D(
                ForceIntoAllowedBodyDirectionVec(_anims.GetAnim(a1).GetIncomingBodyDirection()),
                ForceIntoAllowedBodyDirectionVec(_predRelIncomingBodyDirection))) / Mathf.Pi;
            float r2 = Mathf.Abs(BluntMath.GetAngle2D(
                ForceIntoAllowedBodyDirectionVec(_anims.GetAnim(a2).GetIncomingBodyDirection()),
                ForceIntoAllowedBodyDirectionVec(_predRelIncomingBodyDirection))) / Mathf.Pi;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetIncomingVelocity()) == Velo.IdVelIdle) r1 = 0;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetIncomingVelocity()) == Velo.IdVelIdle) r2 = 0;
            return r1 < r2;
        }

        private bool CompareIncomingVelocitySimilarity(int a1, int a2) // :1793-1816
        {
            int currentId = Velo.GetVelocityID(_predIncomingVelocityId);
            int in1 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetIncomingVelocity()));
            int in2 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetIncomingVelocity()));
            float r1 = Mathf.Abs(Mathf.Clamp(in1 - currentId, -3, 3));
            float r2 = Mathf.Abs(Mathf.Clamp(in2 - currentId, -3, 3));
            int out1 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetOutgoingVelocity()));
            int out2 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetOutgoingVelocity()));
            if (in1 > Mathf.Max(currentId, out1)) r1 += 0.5f;
            if (in1 < Mathf.Min(currentId, out1)) r1 += 0.5f;
            if (in2 > Mathf.Max(currentId, out2)) r2 += 0.5f;
            if (in2 < Mathf.Min(currentId, out2)) r2 += 0.5f;
            return r1 < r2;
        }

        private bool CompareBodyDirectionSimilarity(int i1, int i2) // :1906-1965
        {
            Animation a1 = _anims.GetAnim(i1);
            Animation a2 = _anims.GetAnim(i2);
            const float translationFactor = 1.0f;
            Vector3 relDesired1 = BluntMath.GetNormalized(
                BluntMath.GetRotated2D(_predLookAt - _spatialPosition, -_spatialAngle)
                - a1.GetTranslation() * translationFactor, new Vector3(0, -1, 0));
            Vector3 relDesired2 = BluntMath.GetNormalized(
                BluntMath.GetRotated2D(_predLookAt - _spatialPosition, -_spatialAngle)
                - a2.GetTranslation() * translationFactor, new Vector3(0, -1, 0));

            const float maxAngleSmuggle = 0.1f * Mathf.Pi; // :1945
            float outAngle1 = BluntMath.GetAngle2D(BluntMath.GetRotated2D(a1.GetOutgoingDirection(),
                Mathf.Clamp(BluntMath.GetAngle2D(_predRelDesiredDirection, a1.GetOutgoingDirection()),
                    -maxAngleSmuggle, maxAngleSmuggle)), new Vector3(0, -1, 0));
            float outAngle2 = BluntMath.GetAngle2D(BluntMath.GetRotated2D(a2.GetOutgoingDirection(),
                Mathf.Clamp(BluntMath.GetAngle2D(_predRelDesiredDirection, a2.GetOutgoingDirection()),
                    -maxAngleSmuggle, maxAngleSmuggle)), new Vector3(0, -1, 0));
            Vector3 predictedOut1 = BluntMath.GetRotated2D(a1.GetOutgoingBodyDirection(), outAngle1);
            Vector3 predictedOut2 = BluntMath.GetRotated2D(a2.GetOutgoingBodyDirection(), outAngle2);
            float rating1 = Mathf.Abs(BluntMath.GetAngle2D(predictedOut1, relDesired1));
            float rating2 = Mathf.Abs(BluntMath.GetAngle2D(predictedOut2, relDesired2));
            rating1 += Mathf.Abs(a1.GetOutgoingBodyAngle()) * 0.05f; // :1956 штраф за угол корпуса
            rating2 += Mathf.Abs(a2.GetOutgoingBodyAngle()) * 0.05f;
            return rating1 < rating2;
        }

        // ---- _KeepBest* (humanoidbase.cpp:1103-1229) ----

        // :1103-1171 (movement-путь: baseanim-сортировки нет)
        private void KeepBestDirectionAnims(List<int> dataSet, bool strict = true, float allowedAngle = 0f,
                                            int allowedVelocitySteps = 0, int forcedQuadrantId = -1)
        {
            if (dataSet.Count == 0) return;
            int bestQuadrantId = forcedQuadrantId;
            if (bestQuadrantId == -1)
            {
                StableSort(dataSet, CompareMovementSimilarity);
                bestQuadrantId = BluntMath.AtoI(_anims.GetAnim(dataSet[0]).GetVariable("quadrant_id"));
            }
            var bestQuadrant = _anims.GetQuadrant(bestQuadrantId);
            for (int k = dataSet.Count - 1; k >= 1; k--) // erase со 2-го элемента (:1134-1135)
            {
                Animation anim = _anims.GetAnim(dataSet[k]);
                int quadrantId = BluntMath.AtoI(anim.GetVariable("quadrant_id"));
                bool keep;
                if (strict) keep = quadrantId == bestQuadrantId;
                else
                {
                    var quadrant = _anims.GetQuadrant(quadrantId);
                    keep = true;
                    if (anim.GetVariable("lastditch") != "true" &&
                        Mathf.Abs(Velo.GetVelocityID(quadrant.VelocityId, true) -
                                  Velo.GetVelocityID(bestQuadrant.VelocityId, true)) > allowedVelocitySteps) keep = false;
                    if (Mathf.Abs(quadrant.Angle - bestQuadrant.Angle) > allowedAngle) keep = false;
                }
                if (!keep) dataSet.RemoveAt(k);
            }
        }

        // :1174-1229 (movement-путь)
        private void KeepBestBodyDirectionAnims(List<int> dataSet, bool strict = true, float allowedAngle = 0f)
        {
            if (dataSet.Count == 0) return;
            StableSort(dataSet, CompareBodyDirectionSimilarity);
            Animation bestAnim = _anims.GetAnim(dataSet[0]);
            float bestLookAngle = ForceIntoAllowedBodyDirectionAngle(bestAnim.GetOutgoingBodyAngle())
                                + ForceIntoPreferredDirectionAngle(bestAnim.GetOutgoingAngle());
            float adaptedAllowedAngle = strict ? 0.06f * Mathf.Pi : allowedAngle; // :1214-1217
            for (int k = dataSet.Count - 1; k >= 1; k--)
            {
                Animation anim = _anims.GetAnim(dataSet[k]);
                float animLookAngle = ForceIntoAllowedBodyDirectionAngle(anim.GetOutgoingBodyAngle())
                                    + ForceIntoPreferredDirectionAngle(anim.GetOutgoingAngle());
                if (Mathf.Abs(animLookAngle - bestLookAngle) > adaptedAllowedAngle) dataSet.RemoveAt(k);
            }
        }

        // ---- SelectAnim movement-путь (humanoidbase.cpp:1374-1496) ----

        internal List<int> SelectMovementInternal(Vector3 position, float angle, int enumVelocityId,
            float floatVelocity, Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld,
            float desiredVelocityFloat, bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            _spatialPosition = position;
            _spatialAngle = angle;

            // запрос (:1383-1397); special/retain/vars в лабе пусты
            var query = new CrudeSelectionQuery
            {
                ByFunctionType = true,
                FunctionTypeId = AnimCollection.FnMovement,
                ByIncomingVelocity = true,
                IncomingVelocityId = enumVelocityId,
                IncomingVelocityStrict = true,
                ByIncomingBodyDirection = true,
                IncomingBodyDirectionStrict = true,
                IncomingBodyDirection = relBodyDirectionVec,
                IncomingVelocityForceLinearity = true,
                IncomingBodyDirectionForceLinearity = true,
            };

            var dataSet = new List<int>();
            _anims.CrudeSelectionInternal(dataSet, query);
            if (dataSet.Count == 0) // :1412-1417
            {
                if (_anims.GetIdleMovementAnimID() >= 0) dataSet.Add(_anims.GetIdleMovementAnimID());
                else return dataSet;
            }

            // сортировочная цепочка (:1425-1476)
            Vector3 relDesiredDirection = BluntMath.GetRotated2D(desiredDirectionWorld, -angle); // :1429
            _predRelDesiredDirection = relDesiredDirection;
            _predDesiredVelocityId = Velo.FloatToEnumVelocity(desiredVelocityFloat);
            _predCorneringBias = CalculateBiasForFastCornering(
                new Vector3(0, -1.0f * floatVelocity, 0),
                relDesiredDirection * Velo.EnumToFloatVelocity(_predDesiredVelocityId), 1.0f, 0.9f); // :1823
            _predLookAt = desiredLookAt;

            KeepBestDirectionAnims(dataSet); // :1435
            if (useDesiredLookAt) KeepBestBodyDirectionAnims(dataSet); // :1436

            _predNumericVariableName = "idlelevel"; // :1449-1450
            _predNumericVariableValue = 1;
            StableSort(dataSet, CompareNumericVariable);

            _predDesiredFootId = footId; // :1457
            StableSort(dataSet, CompareFootSimilarity);

            _predRelIncomingBodyDirection = relBodyDirectionVec; // :1464
            StableSort(dataSet, CompareIncomingBodyDirectionSimilarity);

            _predIncomingVelocityId = enumVelocityId; // :1471
            StableSort(dataSet, CompareIncomingVelocitySimilarity);

            return dataSet;
        }

        public int SelectMovementAnim(Vector3 position, float angle, int enumVelocityId, float floatVelocity,
            Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld, float desiredVelocityFloat,
            bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            var ds = SelectMovementInternal(position, angle, enumVelocityId, floatVelocity, relBodyDirectionVec,
                footId, desiredDirectionWorld, desiredVelocityFloat, useDesiredLookAt, desiredLookAt);
            return ds.Count > 0 ? ds[0] : -1;
        }

        public Godot.Collections.Array SelectMovementDataSet(Vector3 position, float angle, int enumVelocityId,
            float floatVelocity, Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld,
            float desiredVelocityFloat, bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            var result = new Godot.Collections.Array();
            foreach (int i in SelectMovementInternal(position, angle, enumVelocityId, floatVelocity,
                relBodyDirectionVec, footId, desiredDirectionWorld, desiredVelocityFloat, useDesiredLookAt, desiredLookAt))
                result.Add(i);
            return result;
        }
    }
}
