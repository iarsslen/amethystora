//! What the main process had for free in JavaScript and Rust on one thread needs written out: one thing at a
//! time (main.js chained every save onto the last one's promise), and a value handed from a callback to
//! whoever awaits it (a dialog's answer). Everything here lives on the window's thread.

use std::cell::{Cell, RefCell};
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::task::{Context, Poll, Waker};

/// One holder at a time; the others wait, and are woken in the order they came when it is free
#[derive(Clone, Default)]
pub struct Gate {
    inner: Rc<GateInner>,
}

#[derive(Default)]
struct GateInner {
    busy: Cell<bool>,
    waiting: RefCell<Vec<Waker>>,
}

pub struct Held {
    inner: Rc<GateInner>,
}

impl Drop for Held {
    fn drop(&mut self) {
        self.inner.busy.set(false);
        let waiting = std::mem::take(&mut *self.inner.waiting.borrow_mut());
        for waker in waiting {
            waker.wake();
        }
    }
}

impl Gate {
    pub fn new() -> Gate {
        Gate::default()
    }

    /// Whether something holds it now
    pub fn busy(&self) -> bool {
        self.inner.busy.get()
    }

    /// Waits for its turn, then holds the gate until what it returns is dropped
    pub fn enter(&self) -> impl Future<Output = Held> {
        Enter { inner: self.inner.clone() }
    }
}

struct Enter {
    inner: Rc<GateInner>,
}

impl Future for Enter {
    type Output = Held;

    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Held> {
        if !self.inner.busy.get() {
            self.inner.busy.set(true);
            return Poll::Ready(Held { inner: self.inner.clone() });
        }
        self.inner.waiting.borrow_mut().push(cx.waker().clone());
        Poll::Pending
    }
}

/// A value sent once from a callback to the one awaiting it
pub struct Sender<T> {
    slot: Rc<RefCell<Slot<T>>>,
}

struct Slot<T> {
    value: Option<T>,
    waker: Option<Waker>,
    closed: bool,
}

pub struct Receiver<T> {
    slot: Rc<RefCell<Slot<T>>>,
}

pub fn oneshot<T>() -> (Sender<T>, Receiver<T>) {
    let slot = Rc::new(RefCell::new(Slot { value: None, waker: None, closed: false }));
    (Sender { slot: slot.clone() }, Receiver { slot })
}

impl<T> Clone for Sender<T> {
    fn clone(&self) -> Self {
        Sender { slot: self.slot.clone() }
    }
}

impl<T> Sender<T> {
    /// The first value sent is the one received; later ones are dropped
    pub fn send(&self, value: T) {
        let waker = {
            let mut slot = self.slot.borrow_mut();
            if slot.closed {
                return;
            }
            slot.closed = true;
            slot.value = Some(value);
            slot.waker.take()
        };
        if let Some(waker) = waker {
            waker.wake();
        }
    }

    pub fn is_sent(&self) -> bool {
        self.slot.borrow().closed
    }
}

impl<T> Future for Receiver<T> {
    type Output = T;

    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<T> {
        let mut slot = self.slot.borrow_mut();
        match slot.value.take() {
            Some(value) => Poll::Ready(value),
            None => {
                slot.waker = Some(cx.waker().clone());
                Poll::Pending
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use amethystora_ui::glib;

    #[test]
    fn one_at_a_time() {
        let context = glib::MainContext::new();
        context
            .with_thread_default(|| {
                let gate = Gate::new();
                let inside = Rc::new(Cell::new(0));
                let most = Rc::new(Cell::new(0));
                let done = Rc::new(Cell::new(0));
                for _ in 0..3 {
                    let (gate, inside, most, done) = (gate.clone(), inside.clone(), most.clone(), done.clone());
                    context.spawn_local(async move {
                        let _held = gate.enter().await;
                        inside.set(inside.get() + 1);
                        most.set(most.get().max(inside.get()));
                        glib::timeout_future(std::time::Duration::from_millis(5)).await;
                        inside.set(inside.get() - 1);
                        done.set(done.get() + 1);
                    });
                }
                let (gate2, done2) = (gate.clone(), done.clone());
                context.block_on(async move {
                    while done2.get() < 3 {
                        glib::timeout_future(std::time::Duration::from_millis(5)).await;
                    }
                    let _held = gate2.enter().await;
                });
                assert_eq!(most.get(), 1);
                let (sender, receiver) = oneshot();
                sender.send(5);
                sender.send(6);
                assert_eq!(context.block_on(receiver), 5);
            })
            .unwrap();
    }
}
