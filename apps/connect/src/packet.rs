//! The packet: one JSON object and a line feed (spec-protocol.md section 3). Parsing is strict about what the
//! protocol fixes and lenient about what a phone may add: unknown fields are ignored, a missing `body` is an
//! empty one, and a field of the wrong type is as good as absent.

use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Map, Number, Value, json};

/// `kdeconnect.pair` and the other types the core itself handles
pub const IDENTITY: &str = "kdeconnect.identity";
pub const PAIR: &str = "kdeconnect.pair";

#[derive(Debug, Clone, PartialEq)]
pub struct Packet {
    pub kind: String,
    pub body: Map<String, Value>,
    /// `payloadSize` and the port of `payloadTransferInfo`, as the peer wrote them. Whether they make a payload
    /// is `payload()`'s to say.
    payload_size: Option<Value>,
    payload_info: Option<Value>,
}

/// Bytes that follow on a connection of their own, and where to fetch them
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Payload {
    pub size: u64,
    pub port: u16,
}

#[derive(Debug, PartialEq, Eq)]
pub enum PacketError {
    /// Not UTF-8, not JSON, not an object, or no string `type`
    Malformed,
}

/// Milliseconds since the epoch: what `id` carries (deprecated: nobody reads it)
pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

pub fn now_secs() -> i64 {
    now_ms() / 1000
}

impl Packet {
    pub fn new(kind: &str, body: Value) -> Packet {
        let body = match body {
            Value::Object(map) => map,
            _ => Map::new(),
        };
        Packet { kind: kind.to_string(), body, payload_size: None, payload_info: None }
    }

    /// The packet with its payload announced: `payloadSize` and `payloadTransferInfo`, beside `body`
    pub fn with_payload(mut self, size: u64, port: u16) -> Packet {
        self.payload_size = Some(json!(size));
        self.payload_info = Some(json!({ "port": port }));
        self
    }

    /// One line: compact JSON and a line feed
    pub fn to_line(&self) -> Vec<u8> {
        self.to_line_with_id(now_ms())
    }

    pub fn to_line_with_id(&self, id: i64) -> Vec<u8> {
        let mut object = Map::new();
        object.insert("id".into(), json!(id));
        object.insert("type".into(), json!(self.kind));
        object.insert("body".into(), Value::Object(self.body.clone()));
        if let (Some(size), Some(info)) = (&self.payload_size, &self.payload_info) {
            object.insert("payloadSize".into(), size.clone());
            object.insert("payloadTransferInfo".into(), info.clone());
        }
        let mut line = serde_json::to_vec(&Value::Object(object)).unwrap_or_default();
        line.push(b'\n');
        line
    }

    /// One line (without its line feed, a trailing carriage return allowed) as a packet
    pub fn parse(line: &[u8]) -> Result<Packet, PacketError> {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        let Ok(Value::Object(mut object)) = serde_json::from_slice::<Value>(line) else {
            return Err(PacketError::Malformed);
        };
        let Some(Value::String(kind)) = object.remove("type") else {
            return Err(PacketError::Malformed);
        };
        let body = match object.remove("body") {
            Some(Value::Object(map)) => map,
            _ => Map::new(),
        };
        Ok(Packet { kind, body, payload_size: object.remove("payloadSize"), payload_info: object.remove("payloadTransferInfo") })
    }

    /// Whether the packet announces bytes: both fields, and a port in the info. `Err` when it announces them
    /// in a way that cannot be followed (a negative or fractional size, no usable port).
    pub fn payload(&self) -> Result<Option<Payload>, PacketError> {
        let (Some(size), Some(info)) = (&self.payload_size, &self.payload_info) else {
            return Ok(None);
        };
        match info {
            Value::Object(map) if map.is_empty() => return Ok(None),
            Value::Object(_) => {}
            _ => return Ok(None),
        }
        let size = as_unsigned(size).ok_or(PacketError::Malformed)?;
        let port = info.get("port").and_then(as_unsigned).filter(|p| *p <= u64::from(u16::MAX)).ok_or(PacketError::Malformed)?;
        Ok(Some(Payload { size, port: port as u16 }))
    }

    /// The `payloadSize` the packet declares, if it is a whole number: for a packet with no payload to follow
    pub fn declared_size(&self) -> Option<u64> {
        self.payload_size.as_ref().and_then(as_unsigned)
    }

    pub fn str(&self, key: &str) -> Option<&str> {
        str_of(&self.body, key)
    }

    pub fn bool(&self, key: &str) -> Option<bool> {
        bool_of(&self.body, key)
    }

    pub fn int(&self, key: &str) -> Option<i64> {
        int_of(&self.body, key)
    }
}

fn as_unsigned(value: &Value) -> Option<u64> {
    match value {
        Value::Number(n) => n.as_u64().or_else(|| n.as_f64().filter(|f| *f >= 0.0 && f.fract() == 0.0 && *f < 9.0e15).map(|f| f as u64)),
        _ => None,
    }
}

/// A string field, if it is one
pub fn str_of<'a>(map: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    map.get(key).and_then(Value::as_str)
}

/// A boolean field, if it is one: the string "false" is not false, and 0 is not either
pub fn bool_of(map: &Map<String, Value>, key: &str) -> Option<bool> {
    map.get(key).and_then(Value::as_bool)
}

/// A whole-number field: an integer, or a float that is one (a few senders write `12.0`)
pub fn int_of(map: &Map<String, Value>, key: &str) -> Option<i64> {
    match map.get(key)? {
        Value::Number(n) => number_as_int(n),
        _ => None,
    }
}

/// The same, or a decimal string of one (the pairing timestamp)
pub fn int_or_text_of(map: &Map<String, Value>, key: &str) -> Option<i64> {
    match map.get(key)? {
        Value::Number(n) => number_as_int(n),
        Value::String(s) => {
            let digits = s.strip_prefix('-').unwrap_or(s);
            (!digits.is_empty() && digits.len() < 19 && digits.bytes().all(|b| b.is_ascii_digit())).then(|| s.parse().ok()).flatten()
        }
        _ => None,
    }
}

fn number_as_int(n: &Number) -> Option<i64> {
    n.as_i64().or_else(|| n.as_f64().filter(|f| f.fract() == 0.0 && f.abs() < 9.0e15).map(|f| f as i64))
}

/// An array of strings; anything else in it is dropped
pub fn strings_of(map: &Map<String, Value>, key: &str) -> Option<Vec<String>> {
    map.get(key).and_then(Value::as_array).map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_packet_is_one_compact_line() {
        let packet = Packet::new("kdeconnect.ping", json!({ "message": "hello\nthere" }));
        let line = packet.to_line_with_id(1792741400001);
        assert_eq!(line.last(), Some(&b'\n'));
        assert_eq!(line.iter().filter(|b| **b == b'\n').count(), 1, "no raw line feed inside");
        let text = String::from_utf8(line).unwrap();
        assert!(text.contains("\"id\":1792741400001"));
        assert!(text.contains("\"type\":\"kdeconnect.ping\""));
        assert!(!text.contains(": "));
    }

    #[test]
    fn the_spec_packets_parse() {
        let ping = Packet::parse(br#"{"id":1792741400000,"type":"kdeconnect.ping","body":{}}"#).unwrap();
        assert_eq!(ping.kind, "kdeconnect.ping");
        assert!(ping.body.is_empty());

        let file = Packet::parse(
            br#"{"id":1792741500000,"type":"kdeconnect.share.request","body":{"filename":"holiday.jpg","lastModified":1790000000000,"numberOfFiles":1,"totalPayloadSize":48213},"payloadSize":48213,"payloadTransferInfo":{"port":1739}}"#,
        )
        .unwrap();
        assert_eq!(file.str("filename"), Some("holiday.jpg"));
        assert_eq!(file.int("lastModified"), Some(1790000000000));
        assert_eq!(file.payload(), Ok(Some(Payload { size: 48213, port: 1739 })));
    }

    #[test]
    fn a_payload_goes_beside_the_body() {
        let packet = Packet::new("kdeconnect.share.request", json!({ "filename": "notes.txt", "open": false })).with_payload(1204, 1739);
        let value: Value = serde_json::from_slice(&packet.to_line()).unwrap();
        assert_eq!(value["payloadSize"], 1204);
        assert_eq!(value["payloadTransferInfo"]["port"], 1739);
        assert!(value["body"].get("payloadSize").is_none());
        let back = Packet::parse(&packet.to_line()).unwrap();
        assert_eq!(back.payload(), Ok(Some(Payload { size: 1204, port: 1739 })));
    }

    #[test]
    fn a_missing_or_odd_body_is_empty() {
        assert!(Packet::parse(br#"{"type":"kdeconnect.ping"}"#).unwrap().body.is_empty());
        assert!(Packet::parse(br#"{"type":"kdeconnect.ping","body":[1]}"#).unwrap().body.is_empty());
        assert!(Packet::parse(br#"{"type":"kdeconnect.ping","body":null}"#).unwrap().body.is_empty());
        // The id may be a number, a string or absent: it is never read
        assert!(Packet::parse(br#"{"id":"12","type":"kdeconnect.ping","body":{}}"#).is_ok());
    }

    #[test]
    fn malformed_lines_are_refused() {
        for bad in [
            &b"not json"[..],
            b"[1,2]",
            b"\"text\"",
            b"{}",
            br#"{"type":7,"body":{}}"#,
            br#"{"type":null}"#,
            &[0xff, 0xfe, b'{', b'}'][..],
            br#"{"type":"a\ud800"}"#,
            b"",
        ] {
            assert_eq!(Packet::parse(bad), Err(PacketError::Malformed), "{:?}", String::from_utf8_lossy(bad));
        }
    }

    #[test]
    fn a_carriage_return_is_ignored() {
        assert!(Packet::parse(b"{\"type\":\"kdeconnect.ping\",\"body\":{}}\r").is_ok());
    }

    #[test]
    fn payloads_that_cannot_be_followed_are_errors() {
        let bad_size = Packet::parse(br#"{"type":"t","body":{},"payloadSize":-1,"payloadTransferInfo":{"port":1739}}"#).unwrap();
        assert_eq!(bad_size.payload(), Err(PacketError::Malformed));
        let fraction = Packet::parse(br#"{"type":"t","body":{},"payloadSize":1.5,"payloadTransferInfo":{"port":1739}}"#).unwrap();
        assert_eq!(fraction.payload(), Err(PacketError::Malformed));
        let no_port = Packet::parse(br#"{"type":"t","body":{},"payloadSize":5,"payloadTransferInfo":{"p":1}}"#).unwrap();
        assert_eq!(no_port.payload(), Err(PacketError::Malformed));
        let huge_port = Packet::parse(br#"{"type":"t","body":{},"payloadSize":5,"payloadTransferInfo":{"port":70000}}"#).unwrap();
        assert_eq!(huge_port.payload(), Err(PacketError::Malformed));
        // Only one of the two, or an empty info: no payload at all
        let size_only = Packet::parse(br#"{"type":"t","body":{},"payloadSize":5}"#).unwrap();
        assert_eq!(size_only.payload(), Ok(None));
        let empty_info = Packet::parse(br#"{"type":"t","body":{},"payloadSize":5,"payloadTransferInfo":{}}"#).unwrap();
        assert_eq!(empty_info.payload(), Ok(None));
    }

    #[test]
    fn fields_are_read_strictly() {
        let packet = Packet::parse(br#"{"type":"t","body":{"a":"false","b":true,"c":0,"d":12.0,"e":"12","f":7,"g":["x",1,"y"]}}"#).unwrap();
        assert_eq!(packet.bool("a"), None, "the string false is not a boolean");
        assert_eq!(packet.bool("b"), Some(true));
        assert_eq!(packet.bool("c"), None, "0 is not false");
        assert_eq!(packet.int("d"), Some(12));
        assert_eq!(packet.int("e"), None);
        assert_eq!(int_or_text_of(&packet.body, "e"), Some(12));
        assert_eq!(packet.str("f"), None);
        assert_eq!(strings_of(&packet.body, "g"), Some(vec!["x".to_string(), "y".to_string()]));
    }
}
