(async function () {
  try {
    const node_fetch = await import("node-fetch");
    global.fetch = node_fetch.default;
  } catch (_) {
  }
})().catch((_) => {
  return;
});

export function request(
  method,
  url,
  body = null,
  auth = null,
  branch = null,
) {
  const opts = {
    method,
    mode: "cors",
    headers: {},
  };

  if (body !== null) {
    opts.body = body;
  }

  if (auth !== null) {
    opts.headers["Wasmstore-Auth"] = auth;
  }

  if (branch !== null) {
    opts.headers["Wasmstore-Branch"] = branch;
  }

  return fetch(url, opts);
}

function normalizePath(path) {
  if (typeof path === "string") {
    return path;
  }

  return path.join("/");
}

function pathString(path) {
  if (path === null) {
    return "";
  }
  return normalizePath(path);
}

export class Client {
  constructor(
    url = "http://127.0.0.1:6384",
    branch = null,
    auth = null,
    version = "v1",
  ) {
    this.url = url + "/api/" + version;
    this.auth = auth;
    this.branch = branch;
  }

  request(method, url, body = null) {
    return request(method, this.url + url, body, this.auth, this.branch);
  }

  async find(path) {
    const res = await this.request("GET", "/module/" + pathString(path));
    if (res.status === 404) {
      return null;
    }

    return res;
  }

  async hash(path) {
    const res = await this.request("GET", "/hash/" + pathString(path));
    if (res.status === 404) {
      return null;
    }

    return await res.text();
  }

  async add(path, data) {
    const res = await this.request("POST", "/module/" + pathString(path), data);
    return await res.text();
  }

  async snapshot() {
    const res = await this.request("GET", "/snapshot");
    return await res.text();
  }

  async restore(hash, path = null) {
    const res = await this.request(
      "POST",
      "/restore/" + hash + (path === null ? "" : "/" + pathString(path)),
    );
    return res.ok;
  }

  async rollback(path = null) {
    const res = await this.request("POST", "/rollback/" + pathString(path));
    return res.ok;
  }

  async gc() {
    const res = await this.request("POST", "/gc");
    return res.ok;
  }

  async versions(path) {
    const res = await this.request("GET", "/versions/" + pathString(path));
    return await res.json();
  }

  async list(path = null) {
    const res = await this.request("GET", "/modules/" + pathString(path));
    return await res.json();
  }

  async branches() {
    const res = await this.request("GET", "/branches");
    return await res.json();
  }

  async createBranch(name) {
    const res = await this.request("POST", "/branch/" + name);
    return res.ok;
  }

  async deleteBranch(name) {
    const res = await this.request("DELETE", "/branch/" + name);
    return res.ok;
  }

  async set(path, hash) {
    const res = await this.request(
      "POST",
      "/hash/" + hash + "/" + pathString(path),
    );
    return res.ok;
  }

  async delete(path) {
    const res = await this.request("DELETE", "/module/" + pathString(path));
    return res.ok;
  }

  async contains(path) {
    const res = await this.request("HEAD", "/module/" + pathString(path));
    return res.ok;
  }

  async commitInfo(hash) {
    const res = await this.request("GET", "/commit/" + hash);
    return await res.json();
  }

  watch(callback) {
    const ws = new WebSocket(this.url.replace("http", "ws") + "/watch");

    ws.onmessage = function (msg) {
      callback(JSON.parse(msg.data));
    };

    return ws;
  }
}
