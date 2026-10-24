//! The transport under the links: sockets with the keepalive the protocol wants, TLS with certificates in both
//! directions checked against a pin, and lines read with a limit. All of it is GIO's, on the main loop; a
//! future that is dropped cancels the operation it waits on.
//!
//! The roles are the protocol's: whoever opened the TCP connection is the TLS *server* and asks for a
//! certificate; whoever accepted it is the TLS *client*. Neither has a certificate authority behind it: a
//! certificate is trusted because it is the pin of a paired device, or, for a device not yet paired, for
//! the length of the connection (spec-protocol.md 4.3.1 and 4.5).

use std::cell::Cell;
use std::fmt;
use std::net::{IpAddr, SocketAddr};
use std::rc::Rc;
use std::time::Duration;

use gio::prelude::*;

use crate::limits;

#[derive(Debug)]
pub enum Error {
    Io(String),
    Timeout,
    /// The peer's certificate is not the pin of the device it says it is
    PinMismatch,
    /// The same, known by the id of the paired device that was claimed
    Mismatch(String),
    /// A line longer than the limit for this stage of the connection
    TooLong,
    /// The peer sent something the protocol does not allow
    Protocol(&'static str),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "{e}"),
            Error::Timeout => write!(f, "timed out"),
            Error::PinMismatch | Error::Mismatch(_) => write!(f, "the certificate is not the one paired"),
            Error::TooLong => write!(f, "a line too long"),
            Error::Protocol(what) => write!(f, "{what}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<glib::Error> for Error {
    fn from(e: glib::Error) -> Error {
        Error::Io(e.message().to_string())
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// `fut`, or `Error::Timeout` after `limit`; the operation it waits on is cancelled
pub async fn timed<T>(limit: Duration, fut: impl std::future::Future<Output = Result<T>>) -> Result<T> {
    match glib::future_with_timeout(limit, fut).await {
        Ok(result) => result,
        Err(_) => Err(Error::Timeout),
    }
}

// --- Addresses --------------------------------------------------------------------------------------------

pub fn socket_address(ip: IpAddr, port: u16, scope: u32) -> gio::InetSocketAddress {
    let address = gio::InetAddress::from_string(&ip.to_string()).unwrap_or_else(|| gio::InetAddress::new_loopback(gio::SocketFamily::Ipv4));
    if scope != 0 {
        // A link-local address needs its interface to be reached; the scope can only be given at construction
        return glib::Object::builder().property("address", &address).property("port", u32::from(port)).property("scope-id", scope).build();
    }
    gio::InetSocketAddress::new(&address, port)
}

/// A GIO address as the standard library's, an IPv4-mapped one as plain IPv4. The scope is the interface
/// index of a link-local IPv6 address.
pub fn from_gio(address: &gio::SocketAddress) -> Option<(IpAddr, u16, u32)> {
    let inet = address.downcast_ref::<gio::InetSocketAddress>()?;
    let ip: IpAddr = inet.address().to_str().parse().ok()?;
    // Only an IPv6 address has a scope; asking an IPv4 one is an error in GLib
    let scope = if ip.is_ipv6() { inet.scope_id() } else { 0 };
    Some((crate::netinfo::unmap(ip), inet.port(), scope))
}

pub fn peer_of(connection: &gio::SocketConnection) -> Result<(IpAddr, u16, u32)> {
    let remote = connection.remote_address()?;
    from_gio(&remote).ok_or(Error::Protocol("not an internet address"))
}

// --- Sockets ----------------------------------------------------------------------------------------------

/// Keepalive on a connection: the first probe after 10 seconds idle, then every 5, three in all, and a write
/// that nobody acknowledges fails after 30 seconds: a vanished phone is noticed in about 25 seconds
pub fn tune(socket: &gio::Socket) {
    socket.set_keepalive(true);
    for (option, value) in [(libc::TCP_KEEPIDLE, limits::KEEPALIVE_IDLE), (libc::TCP_KEEPINTVL, limits::KEEPALIVE_INTERVAL), (libc::TCP_KEEPCNT, limits::KEEPALIVE_COUNT), (libc::TCP_USER_TIMEOUT, limits::USER_TIMEOUT_MS)] {
        // A socket that cannot be tuned still works: the peer is noticed late
        let _ = socket.set_option(libc::IPPROTO_TCP, option, value);
    }
}

/// Opens a TCP connection to `addr`, directly (no proxy), within the time a step may take
pub async fn connect(addr: SocketAddr, scope: u32) -> Result<gio::SocketConnection> {
    let client = gio::SocketClient::new();
    client.set_enable_proxy(false);
    let target = socket_address(addr.ip(), addr.port(), scope);
    let connection = timed(limits::STEP_TIMEOUT, async { client.connect_future(&target).await.map_err(Error::from) }).await?;
    tune(&connection.socket());
    Ok(connection)
}

/// Writes all of `bytes`
pub async fn write_all(out: &gio::OutputStream, bytes: Vec<u8>) -> Result<()> {
    match out.write_all_future(bytes, glib::Priority::DEFAULT).await {
        Ok((_, _, None)) => Ok(()),
        Ok((_, _, Some(e))) | Err((_, e)) => Err(e.into()),
    }
}

// --- Lines ------------------------------------------------------------------------------------------------

/// How many empty lines may come one after the other before the connection is dropped: a peer has no use for
/// even one, and a stream of them is a way to keep a reader busy
const MOST_EMPTY_LINES: usize = 64;

/// Reads lines (up to a line feed) from a stream, each under a limit of the caller's choosing; an empty
/// line is skipped. Whatever follows a line in the same read stays for the next call.
pub struct LineReader {
    input: gio::InputStream,
    buf: Vec<u8>,
    /// Where the line being looked for starts, and how far in it has been looked at: a line taken is not moved
    /// out of the front of the buffer, so that a read full of short lines costs one pass
    start: usize,
    scanned: usize,
    empty_run: usize,
    eof: bool,
    spare: Option<Vec<u8>>,
}

impl LineReader {
    pub fn new(input: gio::InputStream) -> LineReader {
        LineReader { input, buf: Vec::new(), start: 0, scanned: 0, empty_run: 0, eof: false, spare: None }
    }

    /// Bytes read and not yet returned as a line
    pub fn buffered(&self) -> usize {
        self.buf.len() - self.start
    }

    /// The next line without its line feed; `None` at the end of the stream (a last line with no line feed is
    /// dropped). `Err(TooLong)` when a line goes past `max` bytes, or too many empty ones come in a row.
    pub async fn next(&mut self, max: usize) -> Result<Option<Vec<u8>>> {
        loop {
            if let Some(at) = self.buf[self.scanned..].iter().position(|b| *b == b'\n') {
                let end = self.scanned + at;
                let line = &self.buf[self.start..end];
                let empty = line.is_empty() || line == b"\r";
                if line.len() > max {
                    return Err(Error::TooLong);
                }
                let line = (!empty).then(|| line.to_vec());
                self.start = end + 1;
                self.scanned = self.start;
                match line {
                    Some(line) => {
                        self.empty_run = 0;
                        return Ok(Some(line));
                    }
                    None => {
                        self.empty_run += 1;
                        if self.empty_run > MOST_EMPTY_LINES {
                            return Err(Error::TooLong);
                        }
                        continue;
                    }
                }
            }
            // No whole line is left: what was taken goes, once for each read
            if self.start > 0 {
                self.buf.drain(..self.start);
                self.start = 0;
            }
            self.scanned = self.buf.len();
            if self.buf.len() > max {
                return Err(Error::TooLong);
            }
            if self.eof {
                return Ok(None);
            }
            let chunk = self.spare.take().unwrap_or_else(|| vec![0u8; 64 * 1024]);
            let (chunk, n) = self.input.read_future(chunk, glib::Priority::DEFAULT).await.map_err(|(_, e)| Error::from(e))?;
            if n == 0 {
                self.eof = true;
            } else {
                self.buf.extend_from_slice(&chunk[..n]);
            }
            self.spare = Some(chunk);
        }
    }
}

// --- TLS --------------------------------------------------------------------------------------------------

/// How the peer's certificate is judged
#[derive(Clone)]
pub enum Trust {
    /// A paired device: the certificate is this one, byte for byte
    Pin(Rc<Vec<u8>>),
    /// A device we hold nothing for: any certificate, for this connection only
    FirstUse,
}

pub struct Secured {
    pub tls: gio::TlsConnection,
    /// The peer's certificate as it stands on the wire
    pub peer_der: Vec<u8>,
}

fn judge(trust: &Trust, certificate: &gio::TlsCertificate) -> bool {
    match trust {
        Trust::FirstUse => true,
        Trust::Pin(pin) => certificate.certificate().is_some_and(|der| der.as_ref() == pin.as_slice()),
    }
}

async fn finish(tls: gio::TlsConnection, trust: Trust) -> Result<Secured> {
    // The database is left out on purpose: with none, every certificate fails the chain and so reaches the
    // handler above, and a server sends no list of authorities for a client to choose its certificate by
    tls.set_database(None::<&gio::TlsDatabase>);
    // A peer that closes without a close_notify has ended all the same; byte counts say whether it was early
    tls.set_require_close_notify(false);
    let for_handler = trust.clone();
    let rejected = Rc::new(Cell::new(false));
    let flag = rejected.clone();
    tls.connect_accept_certificate(move |_, certificate, _| {
        let accepted = judge(&for_handler, certificate);
        flag.set(!accepted);
        accepted
    });
    // A handshake that fails because we refused the certificate is the pin's doing, not the network's
    let handshake = timed(limits::STEP_TIMEOUT, async { tls.handshake_future(glib::Priority::DEFAULT).await.map_err(Error::from) }).await;
    if let Err(e) = handshake {
        return Err(if rejected.get() { Error::PinMismatch } else { e });
    }
    let peer = tls.peer_certificate().ok_or(Error::Protocol("no certificate"))?;
    // Checked again after the handshake: whether the handler ran at all is the TLS library's to say
    if !judge(&trust, &peer) {
        return Err(Error::PinMismatch);
    }
    let der = peer.certificate().ok_or(Error::Protocol("no certificate"))?.to_vec();
    Ok(Secured { tls, peer_der: der })
}

/// TLS as the server of a connection we opened or a payload we offer: a client certificate is required
pub async fn secure_as_server(base: &gio::IOStream, ours: &gio::TlsCertificate, trust: Trust) -> Result<Secured> {
    let tls = gio::TlsServerConnection::new(base, Some(ours))?;
    tls.set_authentication_mode(gio::TlsAuthenticationMode::Required);
    finish(tls.upcast(), trust).await
}

/// TLS as the client of a connection we accepted or a payload we download
pub async fn secure_as_client(base: &gio::IOStream, ours: &gio::TlsCertificate, trust: Trust) -> Result<Secured> {
    let tls = gio::TlsClientConnection::new(base, None::<&gio::SocketConnectable>)?;
    tls.set_certificate(ours);
    finish(tls.upcast(), trust).await
}

/// Closes a TLS connection politely, without waiting long for a peer that has gone
pub async fn close(tls: &gio::TlsConnection) {
    let _ = timed(Duration::from_secs(3), async { tls.close_future(glib::Priority::DEFAULT).await.map_err(Error::from) }).await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    /// Runs a future on a main context of its own, so that tests on several threads do not share one
    fn run<T>(fut: impl std::future::Future<Output = T>) -> T {
        let context = glib::MainContext::new();
        context.with_thread_default(|| context.block_on(fut)).expect("the context is free")
    }

    fn reader(bytes: Vec<u8>) -> LineReader {
        LineReader::new(gio::MemoryInputStream::from_bytes(&glib::Bytes::from_owned(bytes)).upcast())
    }

    #[test]
    fn lines_come_one_at_a_time() {
        run(async {
            let mut r = reader(b"one\r\ntwo\n\n\r\nthree\npartial".to_vec());
            assert_eq!(r.next(100).await.unwrap(), Some(b"one\r".to_vec()), "the line feed goes; a carriage return is the packet parser's");
            assert_eq!(r.next(100).await.unwrap(), Some(b"two".to_vec()));
            assert_eq!(r.next(100).await.unwrap(), Some(b"three".to_vec()));
            assert_eq!(r.next(100).await.unwrap(), None, "a last line with no line feed is dropped");
        });
    }

    #[test]
    fn a_line_over_the_limit_is_an_error() {
        run(async {
            let mut r = reader(vec![b'x'; 20_000]);
            assert!(matches!(r.next(8192).await, Err(Error::TooLong)));
            let mut r = reader([vec![b'x'; 9000], b"\n".to_vec()].concat());
            assert!(matches!(r.next(8192).await, Err(Error::TooLong)));
            let mut r = reader([vec![b'x'; 8192], b"\nnext\n".to_vec()].concat());
            assert_eq!(r.next(8192).await.unwrap().map(|l| l.len()), Some(8192));
            assert_eq!(r.next(8192).await.unwrap(), Some(b"next".to_vec()));
        });
    }

    #[test]
    fn empty_lines_count_and_cost_one_pass() {
        run(async {
            // Eight megabytes of nothing but line feeds: refused after a handful, in no time
            let started = Instant::now();
            let mut r = reader(vec![b'\n'; 8 * 1024 * 1024]);
            assert!(matches!(r.next(8192).await, Err(Error::TooLong)));
            assert!(started.elapsed().as_millis() < 500, "{:?}", started.elapsed());
            // A few empty lines are no harm
            let mut r = reader([vec![b'\n'; 10], b"hello\n".to_vec()].concat());
            assert_eq!(r.next(8192).await.unwrap(), Some(b"hello".to_vec()));
        });
    }

    #[test]
    fn many_short_lines_in_one_read_are_linear() {
        run(async {
            let started = Instant::now();
            let lines: Vec<u8> = (0..200_000).flat_map(|i| format!("{i}\n").into_bytes()).collect();
            let mut r = reader(lines);
            let mut count = 0;
            while r.next(8192).await.unwrap().is_some() {
                count += 1;
            }
            assert_eq!(count, 200_000);
            assert!(started.elapsed().as_millis() < 2000, "{:?}", started.elapsed());
        });
    }

    #[test]
    fn a_big_line_is_whole() {
        run(async {
            let big = vec![b'a'; 3 * 1024 * 1024];
            let mut r = reader([big.clone(), b"\n".to_vec()].concat());
            assert_eq!(r.next(16 * 1024 * 1024).await.unwrap(), Some(big));
        });
    }
}
