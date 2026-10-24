//! Payloads: the bytes a packet announces with `payloadSize` and `payloadTransferInfo` (spec-protocol.md
//! section 6). They travel on a connection of their own, opened for one transfer: the sender of the packet
//! listens (`offer`), the receiver connects (`fetch`), both with certificates, both checked against the pin of
//! the device the packet went between. Closing the connection is the end of the bytes.

use std::cell::RefCell;
use std::collections::VecDeque;
use std::io;
use std::net::{IpAddr, SocketAddr};
use std::ops::RangeInclusive;
use std::rc::Rc;

use gio::prelude::*;

use crate::limits;
use crate::net::{self, Error, Result, Trust};

/// How long a download that has all its bytes waits for the sender to close the connection
const LINGER: std::time::Duration = std::time::Duration::from_secs(2);

/// How many connections to an offered port may be in their handshake at once, and for how long. When another comes
/// the one that has waited longest is let go, so that a flood of connections that say nothing cannot keep out the one
/// that does
const MOST_HANDSHAKES: usize = 8;
const HANDSHAKE_WAIT: std::time::Duration = std::time::Duration::from_secs(5);

/// A listener for one payload: the first free port of the range, announced in the packet
pub struct Offer {
    listener: gio::SocketListener,
    pub port: u16,
}

/// Binds the first free port of `ports` (a range starting at 0 takes any port: the tests)
pub fn offer(ports: &RangeInclusive<u16>) -> Result<Offer> {
    let listener = gio::SocketListener::new();
    listener.set_backlog(1);
    if *ports.start() == 0 {
        let port = listener.add_any_inet_port(None::<&glib::Object>)?;
        return Ok(Offer { listener, port });
    }
    for port in ports.clone() {
        if listener.add_inet_port(port, None::<&glib::Object>).is_ok() {
            return Ok(Offer { listener, port });
        }
    }
    Err(Error::Io("no port is free for a transfer".into()))
}

impl Offer {
    /// Waits for the device to connect with its certificate, then writes `size` bytes from `source` and closes.
    /// A connection from anyone else is dropped and the wait goes on, up to a minute in all. The handshakes run
    /// side by side (eight at a time, five seconds each), so that a host that connects to the port and says nothing
    /// cannot keep the phone's turn from coming.
    pub async fn serve(self, ours: &gio::TlsCertificate, pin: Rc<Vec<u8>>, size: u64, source: &mut dyn FnMut(&mut [u8]) -> io::Result<usize>, progress: &dyn Fn(u64)) -> Result<()> {
        let (found, arrives) = futures_channel::oneshot::channel::<net::Secured>();
        let found = Rc::new(RefCell::new(Some(found)));
        let handshakes: Rc<RefCell<VecDeque<(u64, glib::JoinHandle<()>)>>> = Rc::default();
        let acceptor = {
            let (listener, ours, pin, found, handshakes) = (self.listener.clone(), ours.clone(), pin.clone(), found.clone(), handshakes.clone());
            glib::spawn_future_local(async move {
                let mut count = 0u64;
                while let Ok((connection, _)) = listener.accept_future().await {
                    // The newest connection has its turn: the one that has waited longest gives its place up
                    while handshakes.borrow().len() >= MOST_HANDSHAKES {
                        let oldest = handshakes.borrow_mut().pop_front();
                        if let Some((_, old)) = oldest {
                            old.abort();
                        }
                    }
                    net::tune(&connection.socket());
                    count += 1;
                    let number = count;
                    let (ours, pin, found, list) = (ours.clone(), pin.clone(), found.clone(), handshakes.clone());
                    let handshake = glib::spawn_future_local(async move {
                        let base: gio::IOStream = connection.upcast();
                        let outcome = net::timed(HANDSHAKE_WAIT, net::secure_as_server(&base, &ours, Trust::Pin(pin))).await;
                        list.borrow_mut().retain(|(n, _)| *n != number);
                        if let (Ok(secured), Some(found)) = (outcome, found.borrow_mut().take()) {
                            let _ = found.send(secured);
                        }
                    });
                    handshakes.borrow_mut().push_back((number, handshake));
                }
            })
        };
        let secured = net::timed(limits::PAYLOAD_ACCEPT_WAIT, async { arrives.await.map_err(|_| Error::Protocol("the offer was dropped")) }).await;
        acceptor.abort();
        for (_, handshake) in handshakes.borrow_mut().drain(..) {
            handshake.abort();
        }
        self.listener.close();
        let secured = secured?;

        let out = secured.tls.output_stream();
        let mut buffer = vec![0u8; 64 * 1024];
        let mut sent: u64 = 0;
        while sent < size {
            let want = buffer.len().min((size - sent) as usize);
            let n = source(&mut buffer[..want]).map_err(|e| Error::Io(e.to_string()))?;
            if n == 0 {
                return Err(Error::Protocol("the file ended early"));
            }
            net::timed(limits::PAYLOAD_IDLE, net::write_all(&out, buffer[..n].to_vec())).await?;
            sent += n as u64;
            progress(sent);
        }
        net::close(&secured.tls).await;
        Ok(())
    }
}

async fn open(host: IpAddr, scope: u32, port: u16, ours: &gio::TlsCertificate, pin: Rc<Vec<u8>>) -> Result<net::Secured> {
    if !limits::PAYLOAD_PORTS_ACCEPTED.contains(&port) {
        return Err(Error::Protocol("a payload port out of range"));
    }
    let connection = net::connect(SocketAddr::new(host, port), scope).await?;
    let base: gio::IOStream = connection.upcast();
    net::secure_as_client(&base, ours, Trust::Pin(pin)).await
}

/// Downloads a payload into `sink`, up to what was announced and a little over, and returns how many bytes
/// there were. Fewer or more than announced is for the caller to judge; more than the announcement plus
/// `PAYLOAD_EXCESS` is an error.
pub async fn fetch(host: IpAddr, scope: u32, port: u16, ours: &gio::TlsCertificate, pin: Rc<Vec<u8>>, announced: u64, sink: &mut dyn FnMut(&[u8]) -> io::Result<()>, progress: &dyn Fn(u64)) -> Result<u64> {
    let secured = open(host, scope, port, ours, pin).await?;
    let input = secured.tls.input_stream();
    let mut chunk = vec![0u8; 64 * 1024];
    let mut total: u64 = 0;
    loop {
        // A sender is to close the connection after the last byte; one that keeps it open (or that sent a little more than
        // it said) is given a moment to, and then the bytes announced are taken as the whole
        let whole = announced > 0 && total >= announced;
        let wait = if whole { LINGER } else { limits::PAYLOAD_IDLE };
        let read = net::timed(wait, async { input.read_future(chunk, glib::Priority::DEFAULT).await.map_err(|(_, e)| Error::from(e)) }).await;
        let (back, n) = match read {
            Err(Error::Timeout) if whole => break,
            other => other?,
        };
        chunk = back;
        if n == 0 {
            break;
        }
        total += n as u64;
        if total > announced.saturating_add(limits::PAYLOAD_EXCESS) {
            return Err(Error::TooLong);
        }
        sink(&chunk[..n]).map_err(|e| Error::Io(e.to_string()))?;
        progress(total);
    }
    net::close(&secured.tls).await;
    Ok(total)
}

/// Says no to a payload: connects as a download would and closes at once. The sender's write then fails, which
/// is the only way to refuse; there is no packet for it.
pub async fn refuse(host: IpAddr, scope: u32, port: u16, ours: &gio::TlsCertificate, pin: Rc<Vec<u8>>) {
    if let Ok(secured) = open(host, scope, port, ours, pin).await {
        net::close(&secured.tls).await;
    }
}
