//! Author-controlled fictional time; never reads the system clock.
use crate::{ids::CalendarId, records::CalendarDef};
use chrono::{DateTime, Datelike, FixedOffset, Months, Timelike};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum UniverseStart {
    Gregorian {
        timestamp: String,
    },
    Fictional {
        calendar_name: String,
        initial_tick: String,
        tick_label: String,
        ticks_per_month: Option<u32>,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum ClockSystem {
    Gregorian {
        offset_seconds: i32,
    },
    Fictional {
        tick_label: String,
        ticks_per_month: Option<u32>,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Chronology {
    pub calendar: CalendarId,
    pub system: ClockSystem,
    /// Immutable first interaction coordinate in this authored clock.
    pub first_interaction: String,
    /// Revision-bound current coordinate; only an explicit operation changes it.
    pub current: String,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum TimeChangeKind {
    Elapsed,
    TimeTravel,
}

fn timestamp(value: &str) -> Result<DateTime<FixedOffset>, String> {
    let t=DateTime::parse_from_rfc3339(value).map_err(|_|"Enter an RFC3339 fictional timestamp with an explicit offset, such as 2042-06-01T12:00:00+00:00".to_string())?;
    if t.nanosecond() != 0 {
        return Err(
            "This clock requires whole seconds; fractional and leap seconds are unsupported."
                .into(),
        );
    }
    Ok(t)
}
impl UniverseStart {
    pub fn build(&self, calendar: CalendarId) -> Result<(Chronology, CalendarDef), String> {
        let (name, current, system) = match self {
            Self::Gregorian { timestamp: value } => {
                let t = timestamp(value)?;
                (
                    "Gregorian".into(),
                    t.timestamp().to_string(),
                    ClockSystem::Gregorian {
                        offset_seconds: t.offset().local_minus_utc(),
                    },
                )
            }
            Self::Fictional {
                calendar_name,
                initial_tick,
                tick_label,
                ticks_per_month,
            } => {
                if calendar_name.trim().is_empty()
                    || tick_label.trim().is_empty()
                    || calendar_name.len() > 200
                    || tick_label.len() > 80
                    || *ticks_per_month == Some(0)
                {
                    return Err("Name the fictional calendar and tick unit; a declared month must contain positive ticks.".into());
                }
                let n = initial_tick.parse::<i128>().map_err(|_| {
                    "Enter the first fictional-time coordinate explicitly as a whole number."
                        .to_string()
                })?;
                (
                    calendar_name.trim().into(),
                    n.to_string(),
                    ClockSystem::Fictional {
                        tick_label: tick_label.trim().into(),
                        ticks_per_month: *ticks_per_month,
                    },
                )
            }
        };
        let chronology = Chronology {
            calendar,
            system,
            first_interaction: current.clone(),
            current,
        };
        let definition = CalendarDef {
            namespace: "chronology".into(),
            key: "universe_clock".into(),
            labels: std::collections::BTreeMap::from([("en".into(), name)]),
            epoch: Some(chronology.display(&chronology.first_interaction)?),
            unit_structure: std::collections::BTreeMap::from([(
                "coordinate".into(),
                match chronology.system {
                    ClockSystem::Gregorian { .. } => {
                        "whole Unix seconds in the authored Gregorian calendar"
                    }
                    _ => "authored integer ticks",
                }
                .into(),
            )]),
            conversions: vec![],
        };
        Ok((chronology, definition))
    }
}
impl Chronology {
    pub fn validate(&self) -> Result<(), String> {
        self.first_interaction
            .parse::<i128>()
            .map_err(|_| "Invalid first interaction coordinate")?;
        self.current
            .parse::<i128>()
            .map_err(|_| "Invalid current coordinate")?;
        self.display(&self.first_interaction)?;
        self.display(&self.current)?;
        if let ClockSystem::Fictional {
            tick_label,
            ticks_per_month,
        } = &self.system
        {
            if tick_label.trim().is_empty() || tick_label.len() > 80 || *ticks_per_month == Some(0)
            {
                return Err("Invalid fictional clock units".into());
            }
        }
        Ok(())
    }
    pub fn coordinate(&self, value: &str) -> Result<String, String> {
        match self.system {
            ClockSystem::Gregorian { .. } => Ok(timestamp(value)?.timestamp().to_string()),
            ClockSystem::Fictional { .. } => value
                .parse::<i128>()
                .map(|n| n.to_string())
                .map_err(|_| "Enter an exact fictional clock coordinate.".into()),
        }
    }
    pub fn display(&self, value: &str) -> Result<String, String> {
        match &self.system {
            ClockSystem::Gregorian { offset_seconds } => {
                let n = value
                    .parse::<i64>()
                    .map_err(|_| "Clock value out of range")?;
                let offset =
                    FixedOffset::east_opt(*offset_seconds).ok_or("Invalid clock offset")?;
                Ok(DateTime::from_timestamp(n, 0)
                    .ok_or("Clock value out of range")?
                    .with_timezone(&offset)
                    .to_rfc3339())
            }
            ClockSystem::Fictional { tick_label, .. } => {
                value
                    .parse::<i128>()
                    .map_err(|_| "Invalid fictional coordinate")?;
                Ok(format!("{value} {tick_label}"))
            }
        }
    }
    pub fn change(
        &mut self,
        value: &str,
        mode: TimeChangeKind,
        reason: &str,
    ) -> Result<(), String> {
        if reason.trim().is_empty() {
            return Err("Explain the elapsed-time or time-travel transition.".into());
        }
        let next = self.coordinate(value)?;
        let n = next.parse::<i128>().map_err(|_| "Invalid next time")?;
        let old = self
            .current
            .parse::<i128>()
            .map_err(|_| "Invalid current time")?;
        if mode == TimeChangeKind::Elapsed && n <= old {
            return Err("Elapsed time must move forward; backward travel requires an explicit time-travel transition.".into());
        }
        if n == old {
            return Err("The authored time is unchanged.".into());
        }
        self.current = next;
        Ok(())
    }
    /// Resolve against a supplied pinned coordinate, never wall-clock now.
    /// Reject invalid month-end dates instead of silently clamping them.
    pub fn months_ago(&self, from: &str, months: u32) -> Result<String, String> {
        match self.system {
            ClockSystem::Gregorian { offset_seconds } => {
                let t =
                    DateTime::from_timestamp(from.parse::<i64>().map_err(|_| "Invalid date")?, 0)
                        .ok_or("Date out of range")?
                        .with_timezone(
                            &FixedOffset::east_opt(offset_seconds).ok_or("Invalid offset")?,
                        );
                let earlier = t
                    .checked_sub_months(Months::new(months))
                    .ok_or("Month offset out of range")?;
                if earlier.day() != t.day() {
                    return Err(
                        "That day does not exist in the target month; choose an explicit date."
                            .into(),
                    );
                }
                Ok(earlier.timestamp().to_string())
            }
            ClockSystem::Fictional {
                ticks_per_month: Some(ticks),
                ..
            } => from
                .parse::<i128>()
                .ok()
                .and_then(|n| n.checked_sub(i128::from(months) * i128::from(ticks)))
                .map(|n| n.to_string())
                .ok_or_else(|| "Month offset out of range".into()),
            _ => Err("This fictional calendar has no declared month length.".into()),
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn calendar() -> CalendarId {
        CalendarId::parse("cal_000000000000000000000001").unwrap()
    }
    #[test]
    fn explicit_start_elapsed_and_travel_preserve_first_interaction() {
        let (mut c, _) = UniverseStart::Gregorian {
            timestamp: "2040-03-15T12:30:00+02:00".into(),
        }
        .build(calendar())
        .unwrap();
        let initial = c.first_interaction.clone();
        assert_eq!(
            c.display(&c.months_ago(&c.current, 1).unwrap()).unwrap(),
            "2040-02-15T12:30:00+02:00"
        );
        assert!(c
            .change("2040-03-14T12:30:00+02:00", TimeChangeKind::Elapsed, "Back")
            .is_err());
        c.change(
            "2040-03-14T12:30:00+02:00",
            TimeChangeKind::TimeTravel,
            "Time machine",
        )
        .unwrap();
        assert_eq!(c.first_interaction, initial);
        c.change(
            "2040-03-16T12:30:00+02:00",
            TimeChangeKind::Elapsed,
            "Two days pass",
        )
        .unwrap();
        assert_eq!(c.first_interaction, initial);
        let end = c.coordinate("2040-03-31T12:30:00+02:00").unwrap();
        assert!(c.months_ago(&end, 1).is_err());
    }
    #[test]
    fn fictional_months_require_an_authored_conversion() {
        let (mut c, _) = UniverseStart::Fictional {
            calendar_name: "Orbital".into(),
            initial_tick: "90".into(),
            tick_label: "days".into(),
            ticks_per_month: None,
        }
        .build(calendar())
        .unwrap();
        assert!(c.months_ago(&c.current, 1).is_err());
        c.system = ClockSystem::Fictional {
            tick_label: "days".into(),
            ticks_per_month: Some(30),
        };
        assert_eq!(c.months_ago(&c.current, 2).unwrap(), "30");
        assert_eq!(c.current, "90");
    }
}
