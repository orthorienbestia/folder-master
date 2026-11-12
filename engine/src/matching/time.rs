use super::UnknownReason;
use crate::rules::{AgeUnit, CalendarDate, DateTest};
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DayWindow {
    pub start_ms: i64,
    pub end_ms: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CalendarDateWindow {
    pub date: CalendarDate,
    pub window: Option<DayWindow>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EvaluationContext {
    pub now_ms: i64,
    pub timezone_identifier: String,
    pub today: Option<DayWindow>,
    pub yesterday: Option<DayWindow>,
    pub dates: Vec<CalendarDateWindow>,
}

impl DayWindow {
    fn valid(&self) -> bool {
        self.start_ms < self.end_ms
    }
    fn contains(&self, timestamp: i64) -> bool {
        timestamp >= self.start_ms && timestamp < self.end_ms
    }
}
#[derive(Debug)]
pub(super) struct CompiledDate {
    test: DateTest,
    elapsed: Option<AgeBoundary>,
}
impl CompiledDate {
    pub(super) fn new(test: &DateTest) -> Self {
        let elapsed = match test {
            DateTest::OlderThan { amount, unit } | DateTest::NewerThan { amount, unit } => {
                Some(AgeBoundary::new(*amount, unit))
            }
            _ => None,
        };
        Self {
            test: test.clone(),
            elapsed,
        }
    }
    pub(super) fn calendar_date(&self) -> Option<&CalendarDate> {
        match &self.test {
            DateTest::OnDate { date } => Some(date),
            _ => None,
        }
    }
    pub(super) fn evaluate(
        &self,
        timestamp: i64,
        context: Option<&EvaluationContext>,
    ) -> Result<bool, UnknownReason> {
        evaluate(&self.test, self.elapsed.as_ref(), timestamp, context)
    }
}

#[derive(Debug)]
enum AgeBoundary {
    Finite { floor_ms: i128, fractional: bool },
    AboveRange,
}
impl AgeBoundary {
    fn new(amount: f64, unit: &AgeUnit) -> Self {
        // Configuration stores f64, so use its canonical shortest decimal
        // spelling. Scale that decimal once, without floating point unit math.
        let spelling = amount.to_string();
        let (mantissa, explicit) = spelling
            .split_once('e')
            .map_or((spelling.as_str(), 0), |(m, e)| {
                (m, e.parse::<i32>().expect("finite f64 exponent"))
            });
        let places = mantissa
            .split_once('.')
            .map_or(0, |(_, fraction)| fraction.len() as i32);
        let digits: String = mantissa.chars().filter(char::is_ascii_digit).collect();
        let significant = digits.trim_start_matches('0').trim_end_matches('0');
        if significant.is_empty() {
            return Self::Finite {
                floor_ms: 0,
                fractional: false,
            };
        }
        let trailing = digits.len() - digits.trim_end_matches('0').len();
        let power = explicit - places + trailing as i32;
        // A shortest round-trip f64 spelling has at most 17 significant digits.
        let coefficient = significant
            .parse::<u128>()
            .expect("shortest finite f64 significand");
        let multiplier = match unit {
            AgeUnit::Minutes => 60_000u128,
            AgeUnit::Hours => 3_600_000,
            AgeUnit::Days => 86_400_000,
            AgeUnit::Weeks => 604_800_000,
        };
        let scaled = coefficient * multiplier;
        if power >= 0 {
            let value = 10u128
                .checked_pow(power as u32)
                .and_then(|scale| scaled.checked_mul(scale))
                .and_then(|value| i128::try_from(value).ok());
            value.map_or(Self::AboveRange, |floor_ms| Self::Finite {
                floor_ms,
                fractional: false,
            })
        } else {
            match 10u128.checked_pow((-power) as u32) {
                Some(divisor) => Self::Finite {
                    floor_ms: (scaled / divisor) as i128,
                    fractional: scaled % divisor != 0,
                },
                None => Self::Finite {
                    floor_ms: 0,
                    fractional: true,
                },
            }
        }
    }
    fn compare(&self, age: i128, older: bool) -> bool {
        match self {
            Self::AboveRange => !older,
            Self::Finite {
                floor_ms,
                fractional,
            } => {
                if older {
                    age > *floor_ms
                } else if *fractional {
                    age <= *floor_ms
                } else {
                    age < *floor_ms
                }
            }
        }
    }
}
fn evaluate(
    test: &DateTest,
    elapsed: Option<&AgeBoundary>,
    timestamp: i64,
    context: Option<&EvaluationContext>,
) -> Result<bool, UnknownReason> {
    match test {
        DateTest::Before { timestamp_ms } => Ok(timestamp < *timestamp_ms),
        DateTest::After { timestamp_ms } => Ok(timestamp > *timestamp_ms),
        DateTest::DateRange { start_ms, end_ms } => {
            Ok(timestamp >= *start_ms && timestamp <= *end_ms)
        }
        DateTest::OlderThan { .. } | DateTest::NewerThan { .. } => {
            let context = context.ok_or(UnknownReason::MissingEvaluationContext)?;
            let age = i128::from(context.now_ms) - i128::from(timestamp);
            let boundary =
                elapsed.expect("elapsed boundary constructed with its private compiled date");
            Ok(boundary.compare(age, matches!(test, DateTest::OlderThan { .. })))
        }
        _ => {
            let context = context.ok_or(UnknownReason::MissingEvaluationContext)?;
            if context.timezone_identifier.trim().is_empty()
                || context.timezone_identifier.contains('\0')
            {
                return Err(UnknownReason::InvalidCalendarContext);
            }
            let window = match test {
                DateTest::Today {} | DateTest::Yesterday {} => {
                    let today = context
                        .today
                        .as_ref()
                        .ok_or(UnknownReason::CalendarUnavailable)?;
                    if !today.valid() || !today.contains(context.now_ms) {
                        return Err(UnknownReason::InvalidCalendarContext);
                    }
                    if matches!(test, DateTest::Today {}) {
                        today
                    } else {
                        let previous = context
                            .yesterday
                            .as_ref()
                            .ok_or(UnknownReason::CalendarUnavailable)?;
                        if previous.end_ms != today.start_ms {
                            return Err(UnknownReason::InvalidCalendarContext);
                        }
                        previous
                    }
                }
                DateTest::OnDate { date } => {
                    let mut matching = context.dates.iter().filter(|entry| entry.date == *date);
                    let entry = matching.next().ok_or(UnknownReason::CalendarUnavailable)?;
                    if matching.next().is_some() {
                        return Err(UnknownReason::InvalidCalendarContext);
                    }
                    entry
                        .window
                        .as_ref()
                        .ok_or(UnknownReason::CalendarUnavailable)?
                }
                _ => unreachable!("absolute and elapsed date predicates handled above"),
            };
            if !window.valid() {
                return Err(UnknownReason::InvalidCalendarContext);
            }
            Ok(window.contains(timestamp))
        }
    }
}
