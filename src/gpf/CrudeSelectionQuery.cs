using Godot;

namespace Gpf
{
    // Порт CrudeSelectionQuery (animcollection.hpp:106-164). Все поля struct как публичные
    // C#-свойства с дефолтами конструктора (:107-120). enum-иды (functionType, incomingVelocity,
    // ...) гоняем как int через мост GDScript↔C#. properties → SetProperty/GetProperty
    // (семантика Properties::Get: неустановленное → "").
    public partial class CrudeSelectionQuery : RefCounted
    {
        // byFunctionType / functionType (:122-123)
        public bool ByFunctionType { get; set; }
        public int FunctionTypeId { get; set; }

        // byFoot / foot (:125-126) — foot = e_Foot_Left(0)
        public bool ByFoot { get; set; }
        public int FootId { get; set; }

        // heedForcedFoot / strongFoot (:128-129) — strongFoot = e_Foot_Right(1)
        public bool HeedForcedFoot { get; set; }
        public int StrongFootId { get; set; } = 1;

        // bySide / lookAtVecRel (:131-132)
        public bool BySide { get; set; }
        public Vector3 LookAtVecRel { get; set; }

        // allowLastDitchAnims (:134)
        public bool AllowLastDitchAnims { get; set; }

        // byIncomingVelocity + флаги + incomingVelocity (:136-141)
        public bool ByIncomingVelocity { get; set; }
        public bool IncomingVelocityStrict { get; set; }
        public bool IncomingVelocityNoDribbleToIdle { get; set; }
        public bool IncomingVelocityNoDribbleToSprint { get; set; }
        public bool IncomingVelocityForceLinearity { get; set; }
        public int IncomingVelocityId { get; set; }

        // byOutgoingVelocity / outgoingVelocity (:143-144)
        public bool ByOutgoingVelocity { get; set; }
        public int OutgoingVelocityId { get; set; }

        // byPickupBall / pickupBall (:146-147) — pickupBall = true
        public bool ByPickupBall { get; set; }
        public bool PickupBall { get; set; } = true;

        // byIncomingBodyDirection + флаги (:149-152)
        public bool ByIncomingBodyDirection { get; set; }
        public Vector3 IncomingBodyDirection { get; set; }
        public bool IncomingBodyDirectionStrict { get; set; }
        public bool IncomingBodyDirectionForceLinearity { get; set; }

        // byIncomingBallDirection / incomingBallDirection (:154-155)
        public bool ByIncomingBallDirection { get; set; }
        public Vector3 IncomingBallDirection { get; set; }

        // byOutgoingBallDirection / outgoingBallDirection (:157-158)
        public bool ByOutgoingBallDirection { get; set; }
        public Vector3 OutgoingBallDirection { get; set; }

        // byTripType / tripType (:160-161)
        public bool ByTripType { get; set; }
        public int TripType { get; set; }

        // Properties properties (:163) — семантика Properties::Get: неустановленное → ""
        private readonly System.Collections.Generic.Dictionary<string, string> _properties = new();
        public void SetProperty(string name, string value) => _properties[name] = value;
        public string GetProperty(string name) => _properties.TryGetValue(name, out var v) ? v : "";
    }
}
