//! Battery: the phone's charge, and one alert when it says it is low (spec-plugins.md 3). Only what is on:
//! the alert at a chosen level, the "fully charged" one and sending our own battery are not carried over.

use serde_json::{Map, Value};

use crate::packet;

/// The threshold a phone's own "low" event starts from, until it has said one
const START_THRESHOLD: i32 = 25;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Battery {
    /// Percent, or -1 when the phone has not said (or has no battery)
    pub level: i32,
    pub charging: bool,
    threshold: i32,
    low_raised: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Alert {
    None,
    /// The phone fell below its own threshold: tell the person once
    Raise,
    /// The level rose above the threshold again
    Withdraw,
}

impl Default for Battery {
    fn default() -> Self {
        Battery { level: -1, charging: false, threshold: START_THRESHOLD, low_raised: false }
    }
}

impl Battery {
    /// A `kdeconnect.battery` body. A charge out of -1..=100 is ignored; a missing `isCharging` keeps the last one.
    pub fn apply(&mut self, body: &Map<String, Value>) -> Alert {
        let before = self.level;
        let charge = match body.get("currentCharge") {
            Some(Value::String(s)) => s.trim().parse::<i64>().ok(),
            _ => packet::int_of(body, "currentCharge"),
        };
        if let Some(charge) = charge.filter(|c| (-1..=100).contains(c)) {
            self.level = charge as i32;
        }
        if let Some(charging) = packet::bool_of(body, "isCharging") {
            self.charging = charging;
        }
        let event = packet::int_of(body, "thresholdEvent").unwrap_or(0);
        if event > 0 {
            // A phone may say it in every packet while low: once for each low period is enough
            if self.low_raised {
                return Alert::None;
            }
            self.low_raised = true;
            if self.level >= 0 {
                self.threshold = self.level;
            }
            return Alert::Raise;
        }
        if self.level != before && self.level > self.threshold && self.low_raised {
            self.low_raised = false;
            return Alert::Withdraw;
        }
        Alert::None
    }

    /// The phone went away: the next low event is news again
    pub fn disconnected(&mut self) {
        self.low_raised = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn body(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn the_spec_packets() {
        let mut b = Battery::default();
        assert_eq!(b.apply(&body(json!({ "currentCharge": 62, "isCharging": false, "thresholdEvent": 0 }))), Alert::None);
        assert_eq!((b.level, b.charging), (62, false));
        assert_eq!(b.apply(&body(json!({ "currentCharge": 14, "isCharging": false, "thresholdEvent": 1 }))), Alert::Raise);
        assert_eq!(b.level, 14);
        // The same event again while low is not news
        assert_eq!(b.apply(&body(json!({ "currentCharge": 13, "isCharging": false, "thresholdEvent": 1 }))), Alert::None);
        assert_eq!(b.apply(&body(json!({ "currentCharge": 40, "isCharging": true }))), Alert::Withdraw);
        assert!(b.charging);
        // A new low period raises again
        assert_eq!(b.apply(&body(json!({ "currentCharge": 9, "isCharging": false, "thresholdEvent": 1 }))), Alert::Raise);
    }

    #[test]
    fn unknown_charge_and_odd_values() {
        let mut b = Battery::default();
        b.apply(&body(json!({ "currentCharge": -1, "isCharging": false })));
        assert_eq!(b.level, -1);
        b.apply(&body(json!({ "currentCharge": "55" })));
        assert_eq!(b.level, 55);
        b.apply(&body(json!({ "currentCharge": 500 })));
        assert_eq!(b.level, 55, "out of range is ignored");
        b.apply(&body(json!({ "currentCharge": "lots" })));
        assert_eq!(b.level, 55);
        b.apply(&body(json!({})));
        assert_eq!(b.level, 55);
        b.apply(&body(json!({ "isCharging": true })));
        assert!(b.charging);
        b.apply(&body(json!({ "isCharging": "false" })));
        assert!(b.charging, "the string false is not a boolean");
    }

    #[test]
    fn a_disconnect_ends_the_low_period() {
        let mut b = Battery::default();
        assert_eq!(b.apply(&body(json!({ "currentCharge": 10, "thresholdEvent": 1 }))), Alert::Raise);
        b.disconnected();
        assert_eq!(b.apply(&body(json!({ "currentCharge": 10, "thresholdEvent": 1 }))), Alert::Raise);
    }
}
