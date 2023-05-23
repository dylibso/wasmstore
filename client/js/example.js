import { Client } from "./wasmstore.js";

async function main() {
  const client = new Client();

  // List existing modules on the server
  const list = await client.list();
  for (const item in list) {
    console.log(item);
  }
}

await main();
