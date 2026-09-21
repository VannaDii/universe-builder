//! The effective frame and perspective (spec §27.1, §8.3).
//!
//! A fully resolved frame: universe, continuity, immutable revision,
//! represented context, temporal query/reference system, and perspective.
//! An omitted time means an explicitly timeless/all-validities query where
//! the operation allows that — not silently "now" (spec §27.1).

use serde::{Deserialize, Serialize};

use crate::canonical::{Canonical, CanonicalValue};
use crate::ids::{ContinuityId, RecordId, RevisionId, UniverseId};
use crate::temporal::TemporalExpression;
use crate::value::RecordRef;

/// How a query views the universe (spec §8.3).
///
/// Author-known truth, character perspective, and reader disclosure are
/// separate views. Author permissions are a security dimension; a
/// point-of-view filter is not an access-control mechanism unless the
/// author explicitly configures a restricted principal.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Perspective {
    /// The author's omniscient view of the universe.
    Author,
    /// A character's fictional knowledge (bounded by records).
    Character(RecordId),
    /// A source/narrator's depicted view.
    Narrator(RecordId),
    /// Reader disclosure position.
    Reader,
}

impl Canonical for Perspective {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            Perspective::Author => CanonicalValue::Str("author".into()),
            Perspective::Reader => CanonicalValue::Str("reader".into()),
            Perspective::Character(id) => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("character".into())),
                ("record".into(), CanonicalValue::Str(id.to_owned())),
            ]),
            Perspective::Narrator(id) => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("narrator".into())),
                ("record".into(), CanonicalValue::Str(id.to_owned())),
            ]),
        }
    }
}

/// The temporal part of a frame.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum FrameTime {
    /// All validities: the query makes no temporal claim (spec §27.1:
    /// "an explicitly timeless/all-validities query").
    #[default]
    Timeless,
    /// Evaluate at or within this temporal expression.
    At { time: TemporalExpression },
    /// State at the moment of a specific event (entry/exit framing
    /// is handled by the event's own time; this names the anchor).
    AtEvent {
        event: RecordRef,
        side: EventTimeSide,
    },
}

/// Which side of an event a frame observes (spec §30.2 event entry/exit
/// selector). Preconditions see `Before`; effects see `After`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum EventTimeSide {
    /// The pre-event state.
    Before,
    /// The post-event state.
    After,
}

impl std::hash::Hash for FrameTime {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        crate::canonical::hash_canonical(state, self);
    }
}

impl Canonical for FrameTime {
    fn to_canonical(&self) -> CanonicalValue {
        match self {
            FrameTime::Timeless => CanonicalValue::Str("timeless".into()),
            FrameTime::At { time } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("at".into())),
                ("time".into(), time.to_canonical()),
            ]),
            FrameTime::AtEvent { event, side } => CanonicalValue::obj(vec![
                ("kind".into(), CanonicalValue::Str("at_event".into())),
                ("event".into(), event.to_canonical()),
                (
                    "side".into(),
                    CanonicalValue::Str(match side {
                        EventTimeSide::Before => "before".into(),
                        EventTimeSide::After => "after".into(),
                    }),
                ),
            ]),
        }
    }
}

/// The effective frame: fully resolved before evaluation (spec §27.1).
///
/// A context handle pins this frame (plus expiry/owner in the service
/// layer). The frame never stores a hidden current-world selection: world
/// focus is per supporting request (spec §11.3, §27.1, I24).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Frame {
    pub universe: UniverseId,
    pub continuity: ContinuityId,
    pub revision: RevisionId,
    /// The represented context record (objective reality, a character's
    /// beliefs, a source narrative, ...).
    pub context: RecordRef,
    pub time: FrameTime,
    pub perspective: Perspective,
    /// Optional personal experienced sequence (spec §7.1): a separately
    /// declared ordering, never inferred.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub personal_sequence: Option<String>,
}

impl Canonical for Frame {
    fn to_canonical(&self) -> CanonicalValue {
        let mut f = vec![
            (
                "continuity".into(),
                CanonicalValue::Str(self.continuity.to_owned()),
            ),
            ("context".into(), self.context.to_canonical()),
            ("perspective".into(), self.perspective.to_canonical()),
            (
                "revision".into(),
                CanonicalValue::Str(self.revision.to_owned()),
            ),
            ("time".into(), self.time.to_canonical()),
            (
                "universe".into(),
                CanonicalValue::Str(self.universe.to_owned()),
            ),
        ];
        if let Some(p) = &self.personal_sequence {
            f.push(("personalSequence".into(), CanonicalValue::Str(p.clone())));
        }
        CanonicalValue::obj(f)
    }
}
