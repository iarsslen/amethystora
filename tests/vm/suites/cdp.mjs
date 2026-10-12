// cdp.mjs PORT BODY: runs BODY, the body of an async function, in the page of an Electron app started with
// --remote-debugging-port=PORT, and prints what it returns as JSON. Exits 1, saying why, when BODY throws.
// For the suites that use an app's window as a person would: run with the app's own Electron as Node
// (ELECTRON_RUN_AS_NODE=1), whose WebSocket and fetch this needs and nothing else.
//
// BODY can use, besides the page's own globals:
//   find(SELECTOR, TEXT)   the first element matching SELECTOR whose text contains TEXT, or null
//   click(SELECTOR, TEXT)  click it, failing when it is not there or is disabled
//   has(TEXT)              whether the page shows TEXT
const HELPERS = `
const find = (selector, text) => [...document.querySelectorAll(selector)]
    .find((node) => text === undefined || node.textContent.includes(text)) || null;
const click = (selector, text) => {
    const node = find(selector, text);
    if (!node) throw new Error('nothing to click: ' + selector + ' ' + (text ?? ''));
    if (node.disabled) throw new Error('disabled: ' + selector + ' ' + (text ?? ''));
    node.click();
    return true;
};
const has = (text) => document.body.innerText.includes(text);
`;

const [port, body] = process.argv.slice(2);
const fail = (why) => {
  console.error(why);
  process.exit(1);
};

let targets;
try {
  targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
} catch (error) {
  fail(`no app answers on port ${port}: ${error.message}`);
}
const page = targets.find((target) => target.type === 'page' && target.url.startsWith('file:'));
if (!page) fail(`no page on port ${port}: ${JSON.stringify(targets.map((target) => target.url))}`);

const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = () => reject(new Error('the page refused the connection'));
}).catch((error) => fail(error.message));
const answer = await new Promise((resolve) => {
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id === 1) resolve(message);
  };
  socket.send(JSON.stringify({
    id: 1,
    method: 'Runtime.evaluate',
    params: { expression: `(async () => {${HELPERS}\n${body}\n})()`, awaitPromise: true, returnByValue: true },
  }));
});
socket.close();
if (answer.error) fail(JSON.stringify(answer.error));
if (answer.result.exceptionDetails) {
  const details = answer.result.exceptionDetails;
  fail(details.exception?.description || details.text);
}
console.log(JSON.stringify(answer.result.result.value ?? null));
process.exit(0);
