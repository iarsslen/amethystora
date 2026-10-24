//! Where an address belongs: the machine's interfaces, which of them are in the firewall's `amethystora-home`
//! zone, and whether an address is one this program may talk to at all.
//!
//! The zone is the person's choice (`ame security home-networks`) and firewalld's to enforce. This program asks
//! it, read-only, which zone each interface is in, only so as not to announce itself on the others; it treats
//! "cannot ask" as "not home". Nothing here is a firewall.

use std::collections::HashSet;
use std::ffi::CStr;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use gio::prelude::*;

pub const HOME_ZONE: &str = "amethystora-home";

#[derive(Debug, Clone)]
pub struct V4 {
    pub addr: Ipv4Addr,
    pub mask: Ipv4Addr,
}

impl V4 {
    pub fn broadcast(&self) -> Ipv4Addr {
        Ipv4Addr::from(u32::from(self.addr) | !u32::from(self.mask))
    }

    fn contains(&self, ip: Ipv4Addr) -> bool {
        u32::from(ip) & u32::from(self.mask) == u32::from(self.addr) & u32::from(self.mask)
    }
}

#[derive(Debug, Clone)]
pub struct V6 {
    pub addr: Ipv6Addr,
    pub prefix: u8,
}

impl V6 {
    fn contains(&self, ip: Ipv6Addr) -> bool {
        let (a, b) = (u128::from(self.addr), u128::from(ip));
        let mask = if self.prefix == 0 { 0 } else { u128::MAX << (128 - u32::from(self.prefix.min(128))) };
        a & mask == b & mask
    }
}

#[derive(Debug, Clone)]
pub struct Iface {
    pub name: String,
    pub index: u32,
    pub up: bool,
    pub loopback: bool,
    pub broadcast: bool,
    pub v4: Vec<V4>,
    pub v6: Vec<V6>,
}

impl Iface {
    /// Whether `ip` is on one of this interface's networks (a link-local IPv6 address is on the interface
    /// its scope names, which the caller checks)
    pub fn has_on_link(&self, ip: IpAddr) -> bool {
        match ip {
            IpAddr::V4(ip) => self.v4.iter().any(|n| n.contains(ip)),
            IpAddr::V6(ip) => self.v6.iter().any(|n| n.contains(ip)),
        }
    }
}

/// The machine's interfaces with their addresses
pub fn interfaces() -> Vec<Iface> {
    let mut out: Vec<Iface> = Vec::new();
    let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
    // SAFETY: getifaddrs fills a list that stays valid until freeifaddrs; every pointer read below is one of
    // its entries, checked for null, and read as the structure the address family says it is
    unsafe {
        if libc::getifaddrs(&mut head) != 0 {
            return out;
        }
        let mut entry = head;
        while !entry.is_null() {
            let ifa = &*entry;
            entry = ifa.ifa_next;
            let name = CStr::from_ptr(ifa.ifa_name).to_string_lossy().into_owned();
            let at = match out.iter().position(|i| i.name == name) {
                Some(at) => at,
                None => {
                    let index = libc::if_nametoindex(ifa.ifa_name);
                    out.push(Iface {
                        name,
                        index,
                        up: ifa.ifa_flags & libc::IFF_UP as u32 != 0 && ifa.ifa_flags & libc::IFF_RUNNING as u32 != 0,
                        loopback: ifa.ifa_flags & libc::IFF_LOOPBACK as u32 != 0,
                        broadcast: ifa.ifa_flags & libc::IFF_BROADCAST as u32 != 0,
                        v4: Vec::new(),
                        v6: Vec::new(),
                    });
                    out.len() - 1
                }
            };
            if ifa.ifa_addr.is_null() || ifa.ifa_netmask.is_null() {
                continue;
            }
            match i32::from((*ifa.ifa_addr).sa_family) {
                libc::AF_INET => {
                    let addr = &*(ifa.ifa_addr as *const libc::sockaddr_in);
                    let mask = &*(ifa.ifa_netmask as *const libc::sockaddr_in);
                    out[at].v4.push(V4 { addr: Ipv4Addr::from(u32::from_be(addr.sin_addr.s_addr)), mask: Ipv4Addr::from(u32::from_be(mask.sin_addr.s_addr)) });
                }
                libc::AF_INET6 => {
                    let addr = &*(ifa.ifa_addr as *const libc::sockaddr_in6);
                    let mask = &*(ifa.ifa_netmask as *const libc::sockaddr_in6);
                    let prefix = mask.sin6_addr.s6_addr.iter().map(|b| b.count_ones() as u8).sum();
                    out[at].v6.push(V6 { addr: Ipv6Addr::from(addr.sin6_addr.s6_addr), prefix });
                }
                _ => {}
            }
        }
        libc::freeifaddrs(head);
    }
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Locality {
    Loopback,
    LinkLocal,
    Private,
    Global,
}

/// Where an address is: the home network's kinds of address are private and link-local, and nothing else
/// is ever connected to because a datagram said so
pub fn locality(ip: IpAddr) -> Locality {
    match ip {
        IpAddr::V4(ip) => {
            let o = ip.octets();
            if ip.is_loopback() {
                Locality::Loopback
            } else if o[0] == 169 && o[1] == 254 {
                Locality::LinkLocal
            } else if o[0] == 10 || (o[0] == 172 && (16..=31).contains(&o[1])) || (o[0] == 192 && o[1] == 168) {
                Locality::Private
            } else {
                Locality::Global
            }
        }
        IpAddr::V6(ip) => {
            if let Some(v4) = ip.to_ipv4_mapped() {
                return locality(IpAddr::V4(v4));
            }
            let first = ip.segments()[0];
            if ip.is_loopback() {
                Locality::Loopback
            } else if first & 0xffc0 == 0xfe80 {
                Locality::LinkLocal
            } else if first & 0xfe00 == 0xfc00 {
                Locality::Private
            } else {
                Locality::Global
            }
        }
    }
}

/// Plain IPv4 for an IPv4-mapped IPv6 address
pub fn unmap(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => v6.to_ipv4_mapped().map(IpAddr::V4).unwrap_or(ip),
        ip => ip,
    }
}

/// Whether the program may talk to this address on a stranger's word: private or link-local, and loopback
/// only where the caller says so (the tests do)
pub fn local_enough(ip: IpAddr, allow_loopback: bool) -> bool {
    match locality(ip) {
        Locality::Private | Locality::LinkLocal => true,
        Locality::Loopback => allow_loopback,
        Locality::Global => false,
    }
}

/// The interface a peer's address is on: a link-local IPv6 address by its scope, any other by the networks
/// the interfaces are in
pub fn interface_of<'a>(interfaces: &'a [Iface], ip: IpAddr, scope: u32) -> Option<&'a Iface> {
    let ip = unmap(ip);
    interfaces.iter().filter(|i| i.up).find(|i| {
        if let IpAddr::V6(v6) = ip {
            if locality(ip) == Locality::LinkLocal {
                return scope != 0 && i.index == scope;
            }
            return i.has_on_link(IpAddr::V6(v6));
        }
        i.has_on_link(ip)
    })
}

/// Which interfaces are in the home zone. Refreshed by asking firewalld; the tests set it.
pub struct HomeZone {
    names: std::cell::RefCell<HashSet<String>>,
    firewalld: Option<gio::DBusConnection>,
}

impl HomeZone {
    /// A fixed set of interface names (tests, and a machine where the answer is known)
    pub fn fixed(names: &[&str]) -> HomeZone {
        HomeZone { names: std::cell::RefCell::new(names.iter().map(|n| n.to_string()).collect()), firewalld: None }
    }

    /// Asks firewalld on the system bus. Until it has answered, nothing is home.
    pub fn firewalld(system_bus: gio::DBusConnection) -> HomeZone {
        HomeZone { names: std::cell::RefCell::new(HashSet::new()), firewalld: Some(system_bus) }
    }

    /// The bus firewalld is asked on, if it is asked at all
    pub fn bus(&self) -> Option<&gio::DBusConnection> {
        self.firewalld.as_ref()
    }

    pub fn contains(&self, interface: &str) -> bool {
        self.names.borrow().contains(interface)
    }

    pub fn names(&self) -> Vec<String> {
        let mut names: Vec<String> = self.names.borrow().iter().cloned().collect();
        names.sort();
        names
    }

    /// Asks again which of the interfaces are in the zone. A question that fails leaves the interface out.
    pub async fn refresh(&self) {
        let Some(bus) = &self.firewalld else { return };
        let mut home = HashSet::new();
        for iface in interfaces().iter().filter(|i| i.up) {
            let reply = bus
                .call_future(
                    Some("org.fedoraproject.FirewallD1"),
                    "/org/fedoraproject/FirewallD1",
                    "org.fedoraproject.FirewallD1.zone",
                    "getZoneOfInterface",
                    Some(&(iface.name.as_str(),).to_variant()),
                    None,
                    gio::DBusCallFlags::NONE,
                    2000,
                )
                .await;
            if let Ok(reply) = reply {
                if reply.child_value(0).str() == Some(HOME_ZONE) {
                    home.insert(iface.name.clone());
                }
            }
        }
        *self.names.borrow_mut() = home;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    #[test]
    fn localities() {
        for private in ["10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.37", "fd00::1"] {
            assert_eq!(locality(ip(private)), Locality::Private, "{private}");
        }
        for global in ["8.8.8.8", "172.32.0.1", "172.15.0.1", "100.64.0.1", "192.169.0.1", "2001:db8::1", "::ffff:8.8.8.8"] {
            assert_eq!(locality(ip(global)), Locality::Global, "{global}");
        }
        assert_eq!(locality(ip("169.254.3.4")), Locality::LinkLocal);
        assert_eq!(locality(ip("fe80::1")), Locality::LinkLocal);
        assert_eq!(locality(ip("127.0.0.1")), Locality::Loopback);
        assert_eq!(locality(ip("::1")), Locality::Loopback);
        assert_eq!(locality(ip("::ffff:192.168.1.5")), Locality::Private);
    }

    #[test]
    fn what_may_be_connected_to() {
        assert!(local_enough(ip("192.168.1.37"), false));
        assert!(local_enough(ip("fe80::1"), false));
        assert!(!local_enough(ip("8.8.8.8"), false));
        assert!(!local_enough(ip("127.0.0.1"), false));
        assert!(local_enough(ip("127.0.0.1"), true));
        assert!(!local_enough(ip("8.8.8.8"), true));
    }

    #[test]
    fn networks_and_broadcasts() {
        let n = V4 { addr: "192.168.1.20".parse().unwrap(), mask: "255.255.255.0".parse().unwrap() };
        assert_eq!(n.broadcast(), "192.168.1.255".parse::<Ipv4Addr>().unwrap());
        assert!(n.contains("192.168.1.37".parse().unwrap()));
        assert!(!n.contains("192.168.2.37".parse().unwrap()));
        let wide = V4 { addr: "10.0.5.1".parse().unwrap(), mask: "255.0.0.0".parse().unwrap() };
        assert_eq!(wide.broadcast(), "10.255.255.255".parse::<Ipv4Addr>().unwrap());
        let n6 = V6 { addr: "fd00:1::5".parse().unwrap(), prefix: 64 };
        assert!(n6.contains("fd00:1::99".parse().unwrap()));
        assert!(!n6.contains("fd00:2::99".parse().unwrap()));
    }

    #[test]
    fn a_peer_is_on_the_interface_its_network_is_on() {
        let wifi = Iface { name: "wlp3s0".into(), index: 3, up: true, loopback: false, broadcast: true, v4: vec![V4 { addr: "192.168.1.20".parse().unwrap(), mask: "255.255.255.0".parse().unwrap() }], v6: vec![] };
        let down = Iface { name: "eth0".into(), index: 2, up: false, loopback: false, broadcast: true, v4: vec![V4 { addr: "10.0.0.2".parse().unwrap(), mask: "255.255.255.0".parse().unwrap() }], v6: vec![] };
        let all = [down, wifi];
        assert_eq!(interface_of(&all, ip("192.168.1.37"), 0).map(|i| i.name.as_str()), Some("wlp3s0"));
        assert_eq!(interface_of(&all, ip("::ffff:192.168.1.37"), 0).map(|i| i.name.as_str()), Some("wlp3s0"));
        assert!(interface_of(&all, ip("10.0.0.9"), 0).is_none(), "an interface that is down has no peers");
        assert!(interface_of(&all, ip("192.168.7.1"), 0).is_none());
        assert_eq!(interface_of(&all, ip("fe80::1"), 3).map(|i| i.name.as_str()), Some("wlp3s0"));
        assert!(interface_of(&all, ip("fe80::1"), 0).is_none(), "a link-local address needs its scope");
    }

    #[test]
    fn the_real_interfaces_can_be_read() {
        let found = interfaces();
        assert!(found.iter().any(|i| i.loopback), "{found:?}");
    }

    #[test]
    fn a_fixed_zone() {
        let zone = HomeZone::fixed(&["wlp3s0"]);
        assert!(zone.contains("wlp3s0"));
        assert!(!zone.contains("eth0"));
        assert_eq!(zone.names(), vec!["wlp3s0".to_string()]);
    }
}
