#!/usr/bin/env node

import net from 'node:net';

const socketPath = process.env.HERDR_SOCKET_PATH;
if (!socketPath) {
  throw new Error('HERDR_SOCKET_PATH is unavailable');
}

const socketEndpoint =
  process.platform === 'win32' ? `\\\\.\\pipe\\${socketPath}` : socketPath;
const request = {
  id: `herdr-popup-close:${process.pid}`,
  method: 'popup.close',
  params: {},
};

await new Promise((resolve, reject) => {
  const client = net.connect(socketEndpoint);
  const timer = setTimeout(() => {
    client.destroy();
    reject(new Error('Herdr popup close timed out'));
  }, 1000);

  const finish = (callback, value) => {
    clearTimeout(timer);
    callback(value);
  };

  client.once('connect', () => {
    client.end(`${JSON.stringify(request)}\n`, () => finish(resolve));
  });
  client.once('error', (error) => finish(reject, error));
});
