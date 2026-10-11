#!/usr/bin/env node
// The VM lab's MCP server: lab.mjs's tools over stdio, one JSON-RPC message a line. Registered with Claude Code
// as `docker exec -i amevm node /opt/amethystora-vm/server.mjs` (README.md).
import readline from 'node:readline';

import { tools } from './lab.mjs';

const text = (value) => ({ content: [{ type: 'text', text: String(value) }] });

// --- MCP over stdio -----------------------------------------------------------------------------------------

const send = (message) => process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`);

async function answer(request) {
  const { id, method, params = {} } = request;
  switch (method) {
    case 'initialize':
      return { protocolVersion: params.protocolVersion || '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'amethystora-vm', version: '1.0.0' } };
    case 'ping':
      return {};
    case 'tools/list':
      return { tools: tools.map((t) => ({ name: t.name, description: t.description, inputSchema: { type: 'object', properties: t.schema, required: t.required || [] } })) };
    case 'tools/call': {
      const tool = tools.find((t) => t.name === params.name);
      if (!tool) throw Object.assign(new Error(`no tool ${params.name}`), { code: -32602 });
      try {
        return await tool.call(params.arguments || {});
      } catch (error) {
        return { ...text(error.message), isError: true };
      }
    }
    default:
      if (id === undefined) return undefined;
      throw Object.assign(new Error(`no method ${method}`), { code: -32601 });
  }
}

readline.createInterface({ input: process.stdin }).on('line', async (line) => {
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    return send({ id: null, error: { code: -32700, message: 'not JSON' } });
  }
  try {
    const result = await answer(request);
    if (request.id !== undefined && result !== undefined) send({ id: request.id, result });
  } catch (error) {
    if (request.id !== undefined) send({ id: request.id, error: { code: error.code || -32603, message: error.message } });
  }
});
