//! Pairing, as pure decisions (spec-protocol.md section 5): the verification key two people compare, and a
//! state machine that is told what happened (the peer's `kdeconnect.pair`, the person's answer, the clock) and
//! says what to do (send a packet, store or drop the pin, ask the person). It touches no socket, no file and no
//! clock of its own, so every flow and every negative case of the spec is a unit test.

use sha2::{Digest, Sha256};

use crate::limits;

/// The eight characters both screens show: SHA-256 over the two public keys (DER SubjectPublicKeyInfo, the
/// larger first as unsigned byte strings) and, for a protocol 8 peer, the pairing timestamp's decimal digits.
/// Upper-case hexadecimal.
pub fn verification_key(ours: &[u8], theirs: &[u8], timestamp: Option<i64>) -> String {
    let (first, second) = if ours >= theirs { (ours, theirs) } else { (theirs, ours) };
    let mut hash = Sha256::new();
    hash.update(first);
    hash.update(second);
    if let Some(t) = timestamp {
        hash.update(t.to_string().as_bytes());
    }
    hash.finalize()[..4].iter().map(|b| format!("{b:02X}")).collect()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Idle,
    /// The phone asked; the person has until `deadline` (seconds since the epoch)
    Incoming { timestamp: Option<i64>, deadline: i64 },
    /// We asked; the phone has until `deadline`
    Outgoing { timestamp: i64, deadline: i64 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Input {
    /// A `kdeconnect.pair` packet
    Peer { pair: bool, timestamp: Option<i64> },
    /// The person asks the phone to pair
    Ask,
    /// The person answers the phone's request
    Accept,
    Reject,
    /// The person cancels our request, rejects the phone's, or unpairs
    Cancel,
    /// Time passes
    Tick,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Out {
    Send { pair: bool, timestamp: Option<i64> },
    /// Show the person the verification key, computed with `key_timestamp`, until `deadline`
    Prompt { outgoing: bool, key_timestamp: Option<i64>, deadline: i64 },
    /// The prompt is gone without an outcome of its own
    Withdraw,
    /// Keep the certificate of this connection as the device's pin. Done before the answer is sent; if it
    /// fails the answer is `pair: false` instead.
    StorePin,
    DropPin,
    Paired,
    /// The phone ended a pairing
    Unpaired,
    /// The phone refused our request
    Rejected,
    TimedOut,
    ClockSkew { peer: i64, ours: i64 },
    /// A device we hold as paired asked again and was answered, without asking the person
    Confirmed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    /// A pairing is in progress already
    Busy,
    /// There is nothing to answer or cancel
    NothingPending,
    AlreadyPaired,
}

#[derive(Debug)]
pub struct Machine {
    peer_protocol: u32,
    phase: Phase,
    /// When requests arrived in the last minute: more than a few are flooding
    recent: Vec<i64>,
}

impl Machine {
    pub fn new(peer_protocol: u32) -> Machine {
        Machine { peer_protocol, phase: Phase::Idle, recent: Vec::new() }
    }

    pub fn phase(&self) -> Phase {
        self.phase
    }

    pub fn is_idle(&self) -> bool {
        self.phase == Phase::Idle
    }

    /// The timestamp the verification key is made with: protocol 8 peers only
    fn key_timestamp(&self, timestamp: Option<i64>) -> Option<i64> {
        if self.peer_protocol >= 8 { timestamp } else { None }
    }

    /// What to do now that `input` happened, for a device that is `paired` or not, at `now`
    pub fn step(&mut self, paired: bool, input: Input, now: i64) -> Result<Vec<Out>, Refusal> {
        match input {
            Input::Tick => Ok(self.tick(now)),
            Input::Ask => {
                if paired {
                    return Err(Refusal::AlreadyPaired);
                }
                if self.phase != Phase::Idle {
                    return Err(Refusal::Busy);
                }
                let deadline = now + limits::PAIR_WAIT_SECS;
                self.phase = Phase::Outgoing { timestamp: now, deadline };
                Ok(vec![
                    Out::Send { pair: true, timestamp: Some(now) },
                    Out::Prompt { outgoing: true, key_timestamp: self.key_timestamp(Some(now)), deadline },
                ])
            }
            Input::Accept => match self.phase {
                // Whatever the clock has not been told yet, the time is up: no tick is waited for
                Phase::Incoming { deadline, .. } | Phase::Outgoing { deadline, .. } if deadline <= now => {
                    self.phase = Phase::Idle;
                    Ok(vec![Out::Withdraw, Out::TimedOut])
                }
                Phase::Incoming { .. } if !paired => {
                    self.phase = Phase::Idle;
                    Ok(vec![Out::StorePin, Out::Send { pair: true, timestamp: None }, Out::Paired])
                }
                _ => Err(Refusal::NothingPending),
            },
            Input::Reject => match self.phase {
                Phase::Incoming { .. } => {
                    self.phase = Phase::Idle;
                    Ok(vec![Out::Send { pair: false, timestamp: None }, Out::Withdraw])
                }
                _ => Err(Refusal::NothingPending),
            },
            Input::Cancel => {
                if paired {
                    self.phase = Phase::Idle;
                    return Ok(vec![Out::Send { pair: false, timestamp: None }, Out::DropPin, Out::Unpaired]);
                }
                match self.phase {
                    Phase::Idle => Err(Refusal::NothingPending),
                    Phase::Incoming { .. } | Phase::Outgoing { .. } => {
                        self.phase = Phase::Idle;
                        Ok(vec![Out::Send { pair: false, timestamp: None }, Out::Withdraw])
                    }
                }
            }
            Input::Peer { pair: true, timestamp } => Ok(self.peer_asks(paired, timestamp, now)),
            Input::Peer { pair: false, .. } => Ok(self.peer_refuses(paired)),
        }
    }

    fn tick(&mut self, now: i64) -> Vec<Out> {
        match self.phase {
            Phase::Incoming { deadline, .. } | Phase::Outgoing { deadline, .. } if deadline <= now => {
                self.phase = Phase::Idle;
                vec![Out::Withdraw, Out::TimedOut]
            }
            _ => Vec::new(),
        }
    }

    fn peer_asks(&mut self, paired: bool, timestamp: Option<i64>, now: i64) -> Vec<Out> {
        // A flood of requests, or two devices that answer each other for ever, is cut short
        self.recent.retain(|t| now - t < 60);
        if self.recent.len() >= limits::PAIR_REQUESTS_PER_MINUTE {
            return Vec::new();
        }
        self.recent.push(now);

        if paired {
            // It lost its side of the pairing; the connection was authenticated by the pin, so say yes
            return vec![Out::Send { pair: true, timestamp: Some(now) }, Out::Confirmed];
        }
        if let Phase::Outgoing { deadline, .. } = self.phase {
            self.phase = Phase::Idle;
            // An acceptance after the time the person had is nothing
            if deadline <= now {
                return vec![Out::Withdraw, Out::TimedOut];
            }
            // Nothing on the wire tells an acceptance from a request but our own state
            return vec![Out::StorePin, Out::Withdraw, Out::Paired];
        }
        // A request. A protocol 8 request without a timestamp is not one; any timestamp must be fresh
        if self.peer_protocol >= 8 && timestamp.is_none() {
            return Vec::new();
        }
        if let Some(t) = timestamp {
            if (t - now).abs() > limits::PAIR_FRESH_SECS {
                return vec![Out::ClockSkew { peer: t, ours: now }];
            }
        }
        if let Phase::Incoming { timestamp: pending, .. } = self.phase {
            if pending == timestamp {
                return Vec::new();
            }
        }
        let deadline = now + limits::PAIR_WAIT_SECS;
        self.phase = Phase::Incoming { timestamp, deadline };
        vec![Out::Prompt { outgoing: false, key_timestamp: self.key_timestamp(timestamp), deadline }]
    }

    fn peer_refuses(&mut self, paired: bool) -> Vec<Out> {
        if paired {
            self.phase = Phase::Idle;
            return vec![Out::DropPin, Out::Unpaired];
        }
        match std::mem::replace(&mut self.phase, Phase::Idle) {
            Phase::Outgoing { .. } => vec![Out::Withdraw, Out::Rejected],
            Phase::Incoming { .. } => vec![Out::Withdraw],
            Phase::Idle => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;
    use base64::engine::general_purpose::STANDARD;

    fn der(b64: &str) -> Vec<u8> {
        STANDARD.decode(b64).unwrap()
    }

    // The spec's vectors (section 8.9), computed twice with OpenSSL and Node
    const P: &str = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEL5cZ38gjXA4Fiis09eREm7fonQWKXhjTGnGnXAF3ILVeGIJ0ZQUPYHOkBpPqGEWsdsrCOl+5KjHkZydZIliTXw==";
    const Q: &str = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFc2wSCJBdJIIY4X1DNNW3YwjOFBKkY5Ozn77H9NSstZ+U7/tqGERxhhfMG1L5tzHJ5PJrlhrBvqQtCQgfGhWyw==";
    const R: &str = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2mP9FMSpRKDGr6uX6AZMzt7k93kJykosOA0/wAGYF8iK2rlU5AQ1o+i/mRRWv91s9+PhPLKpTCIivky0oOdi2g==";
    const S: &str = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAENfy6EZc2NkkIxQVoUcchl+l4Pn+FbPqW9K4277kviwWb0iFApvftZYIoo/T7JBJc7gUBElE/r1/GfxlJhX5E1w==";
    const T: i64 = 1_792_741_240;

    #[test]
    fn vector_one_the_direction() {
        let (p, q) = (der(P), der(Q));
        assert_eq!(verification_key(&p, &q, Some(T)), "08CE4938");
        assert_eq!(verification_key(&q, &p, Some(T)), "08CE4938", "both sides compute the same key");
        assert_eq!(verification_key(&p, &q, None), "B61B9B96");
        assert_ne!(verification_key(&p, &q, Some(T)), "2B50E569", "smaller first is wrong");
    }

    #[test]
    fn vector_two_unsigned_bytes() {
        let (r, s) = (der(R), der(S));
        assert_eq!(verification_key(&r, &s, Some(T)), "C391B2CB");
        assert_eq!(verification_key(&s, &r, Some(T)), "C391B2CB");
        assert_eq!(verification_key(&r, &s, None), "1DE38AA4");
        assert_ne!(verification_key(&r, &s, Some(T)), "406D1637", "signed comparison is wrong");
    }

    const NOW: i64 = 1_792_741_234;

    fn run(m: &mut Machine, paired: bool, input: Input, now: i64) -> Vec<Out> {
        m.step(paired, input, now).unwrap()
    }

    #[test]
    fn flow_a_the_phone_asks_and_the_person_accepts() {
        let mut m = Machine::new(8);
        let out = run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(out, vec![Out::Prompt { outgoing: false, key_timestamp: Some(T), deadline: NOW + 30 }]);
        let out = run(&mut m, false, Input::Accept, NOW + 17);
        // The pin is stored before the answer goes out
        assert_eq!(out, vec![Out::StorePin, Out::Send { pair: true, timestamp: None }, Out::Paired]);
        assert!(m.is_idle());
    }

    #[test]
    fn flow_a_the_person_rejects_or_does_not_answer() {
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(run(&mut m, false, Input::Reject, NOW + 5), vec![Out::Send { pair: false, timestamp: None }, Out::Withdraw]);

        let mut m = Machine::new(8);
        run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(run(&mut m, false, Input::Tick, NOW + 29), vec![]);
        // Nothing is sent when the time runs out
        assert_eq!(run(&mut m, false, Input::Tick, NOW + 30), vec![Out::Withdraw, Out::TimedOut]);
        assert_eq!(m.step(false, Input::Accept, NOW + 31), Err(Refusal::NothingPending), "too late");
    }

    #[test]
    fn a_stale_request_is_the_clocks() {
        let mut m = Machine::new(8);
        // 2,234 seconds off, and a timestamp in milliseconds
        assert_eq!(run(&mut m, false, Input::Peer { pair: true, timestamp: Some(1_792_739_000) }, NOW), vec![Out::ClockSkew { peer: 1_792_739_000, ours: NOW }]);
        assert_eq!(run(&mut m, false, Input::Peer { pair: true, timestamp: Some(1_792_741_240_000) }, NOW).len(), 1);
        assert!(m.is_idle());
        // 1,800 seconds is still fresh, 1,801 is not
        let mut m = Machine::new(8);
        assert!(matches!(run(&mut m, false, Input::Peer { pair: true, timestamp: Some(NOW - 1800) }, NOW)[0], Out::Prompt { .. }));
        let mut m = Machine::new(8);
        assert!(matches!(run(&mut m, false, Input::Peer { pair: true, timestamp: Some(NOW + 1801) }, NOW)[0], Out::ClockSkew { .. }));
    }

    #[test]
    fn a_protocol_8_request_needs_its_timestamp_and_a_protocol_7_one_does_not() {
        let mut m = Machine::new(8);
        assert_eq!(run(&mut m, false, Input::Peer { pair: true, timestamp: None }, NOW), vec![]);
        let mut m = Machine::new(7);
        let out = run(&mut m, false, Input::Peer { pair: true, timestamp: None }, NOW);
        assert_eq!(out, vec![Out::Prompt { outgoing: false, key_timestamp: None, deadline: NOW + 30 }]);
        // A protocol 7 key never has a timestamp in it, even when the request carries one
        let mut m = Machine::new(7);
        let out = run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(out, vec![Out::Prompt { outgoing: false, key_timestamp: None, deadline: NOW + 30 }]);
    }

    #[test]
    fn flow_b_we_ask() {
        let mut m = Machine::new(8);
        let out = run(&mut m, false, Input::Ask, NOW);
        assert_eq!(
            out,
            vec![Out::Send { pair: true, timestamp: Some(NOW) }, Out::Prompt { outgoing: true, key_timestamp: Some(NOW), deadline: NOW + 30 }]
        );
        assert_eq!(m.step(false, Input::Ask, NOW + 1), Err(Refusal::Busy));
        // The acceptance has no timestamp that matters
        let out = run(&mut m, false, Input::Peer { pair: true, timestamp: Some(1) }, NOW + 9);
        assert_eq!(out, vec![Out::StorePin, Out::Withdraw, Out::Paired]);
        assert!(m.is_idle());
    }

    #[test]
    fn flow_b_rejected_cancelled_timed_out() {
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Ask, NOW);
        assert_eq!(run(&mut m, false, Input::Peer { pair: false, timestamp: None }, NOW + 3), vec![Out::Withdraw, Out::Rejected]);

        let mut m = Machine::new(8);
        run(&mut m, false, Input::Ask, NOW);
        assert_eq!(run(&mut m, false, Input::Cancel, NOW + 3), vec![Out::Send { pair: false, timestamp: None }, Out::Withdraw]);

        let mut m = Machine::new(8);
        run(&mut m, false, Input::Ask, NOW);
        assert_eq!(run(&mut m, false, Input::Tick, NOW + 30), vec![Out::Withdraw, Out::TimedOut]);
    }

    #[test]
    fn flow_c_both_ask_at_once() {
        // Each takes the other's request for the acceptance of its own: state decides
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Ask, NOW);
        assert!(run(&mut m, false, Input::Peer { pair: true, timestamp: Some(NOW + 1) }, NOW + 1).contains(&Out::Paired));
    }

    #[test]
    fn flow_d_unpair() {
        let mut m = Machine::new(8);
        assert_eq!(run(&mut m, true, Input::Peer { pair: false, timestamp: None }, NOW), vec![Out::DropPin, Out::Unpaired]);
        assert_eq!(run(&mut m, true, Input::Cancel, NOW), vec![Out::Send { pair: false, timestamp: None }, Out::DropPin, Out::Unpaired]);
        assert_eq!(m.step(true, Input::Ask, NOW), Err(Refusal::AlreadyPaired));
    }

    #[test]
    fn flow_f_a_paired_device_asks_again() {
        let mut m = Machine::new(8);
        let out = run(&mut m, true, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(out, vec![Out::Send { pair: true, timestamp: Some(NOW) }, Out::Confirmed]);
    }

    #[test]
    fn two_paired_devices_do_not_answer_each_other_for_ever() {
        let mut m = Machine::new(8);
        let mut answers = 0;
        for i in 0..20 {
            answers += run(&mut m, true, Input::Peer { pair: true, timestamp: Some(NOW) }, NOW + i).iter().filter(|o| matches!(o, Out::Send { .. })).count();
        }
        assert_eq!(answers, limits::PAIR_REQUESTS_PER_MINUTE);
        // A minute later it answers again
        assert_eq!(run(&mut m, true, Input::Peer { pair: true, timestamp: Some(NOW) }, NOW + 61).len(), 2);
    }

    #[test]
    fn a_flood_of_unpaired_requests_gives_one_prompt() {
        let mut m = Machine::new(8);
        let mut prompts = 0;
        for i in 0..30 {
            let stamp = NOW + i;
            prompts += run(&mut m, false, Input::Peer { pair: true, timestamp: Some(stamp) }, NOW + i).iter().filter(|o| matches!(o, Out::Prompt { .. })).count();
        }
        assert_eq!(prompts, limits::PAIR_REQUESTS_PER_MINUTE);
    }

    #[test]
    fn a_repeat_is_ignored_and_a_new_timestamp_replaces_the_request() {
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW + 2), vec![]);
        let out = run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T + 1) }, NOW + 4);
        assert_eq!(out, vec![Out::Prompt { outgoing: false, key_timestamp: Some(T + 1), deadline: NOW + 34 }]);
    }

    #[test]
    fn the_phone_withdrawing_its_request_withdraws_the_prompt() {
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(run(&mut m, false, Input::Peer { pair: false, timestamp: None }, NOW + 3), vec![Out::Withdraw]);
        assert!(m.is_idle());
        // pair: false while idle and unpaired: ignored
        assert_eq!(run(&mut m, false, Input::Peer { pair: false, timestamp: None }, NOW + 4), vec![]);
    }

    #[test]
    fn nothing_is_accepted_after_the_deadline_even_if_no_tick_ran() {
        // The person answers an hour late, and the phone's acceptance comes a minute late
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(run(&mut m, false, Input::Accept, NOW + 30), vec![Out::Withdraw, Out::TimedOut]);
        assert!(m.is_idle());
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Peer { pair: true, timestamp: Some(T) }, NOW);
        assert_eq!(run(&mut m, false, Input::Accept, NOW + 3600), vec![Out::Withdraw, Out::TimedOut]);
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Ask, NOW);
        let out = run(&mut m, false, Input::Peer { pair: true, timestamp: None }, NOW + 31);
        assert_eq!(out, vec![Out::Withdraw, Out::TimedOut], "no pin for an acceptance that came late");
        assert!(m.is_idle());
        // The last second is still good
        let mut m = Machine::new(8);
        run(&mut m, false, Input::Ask, NOW);
        assert!(run(&mut m, false, Input::Peer { pair: true, timestamp: None }, NOW + 29).contains(&Out::Paired));
    }

    #[test]
    fn answers_with_nothing_to_answer_are_refused() {
        let mut m = Machine::new(8);
        assert_eq!(m.step(false, Input::Accept, NOW), Err(Refusal::NothingPending));
        assert_eq!(m.step(false, Input::Reject, NOW), Err(Refusal::NothingPending));
        assert_eq!(m.step(false, Input::Cancel, NOW), Err(Refusal::NothingPending));
        run(&mut m, false, Input::Ask, NOW);
        assert_eq!(m.step(false, Input::Accept, NOW), Err(Refusal::NothingPending), "our own request is not the phone's to accept");
    }
}
