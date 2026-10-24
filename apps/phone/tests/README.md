# Tests of amethystora-phone

What is pure is tested by cargo (`cargo test -p amethystora-phone`: the command line, the text of a phone made safe and
its links, the conversation and the chat as data, the pairing's situations). The window itself is tested against a
stand-in for the program, so that nothing here needs a phone or `amethystora-connect`.

- `mock-service.py` owns `org.amethystora.Connect` on the session bus and serves
  `apps/connect/dbus/org.amethystora.Connect.xml` with canned data: four phones (a paired and connected one with a long
  texting history, a tablet that shares no texts, one out of reach, one nearby), and scenarios `pairing` (a request
  with its key), `empty`, `many`. Every call is logged as a JSON line; a test makes the "phone" do something through
  `org.amethystora.ConnectMock.Do` (see its header).
- `run-behaviour.sh` uses the window as a person would (the accessibility tree and the keyboard, `session.sh` makes the
  session) and checks, from the log, what it asked the program to do. `test.sh` runs it in the `amethystora-rust`
  container: `CARGO=.../cargo.sh bash apps/phone/tests/test.sh [-n] [CASE...]`. Exit status: the checks that failed.
- `shoot-all.sh` and `shoot.sh` take a screenshot of every page and dialog in a theme (`amethystora` dark,
  `amethystora-light`), `steps/NAME.sh` being what is done in the window first:
  `CARGO=... SCRATCH=<folder> bash apps/phone/tests/shoot-all.sh amethystora-light [NAME...]`.

None of this runs in the image build, and the scripts are not part of the image.
