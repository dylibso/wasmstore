(async function() {
  try {
    var node_fetch = await import('node-fetch');
    fetch = node_fetch.default;
  } catch (_) {

  }
})().catch(_ => { return });

async function request(method, url, body = null, auth = null, branch = null) {
  let opts = {
    method,
    mode: 'cors',
    headers: {}
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
  if (typeof path === 'string') {
    return path;
  }

  return path.join('/');
}

function pathString(path) {
  if (path === null) {
    return "";
  }
  return normalizePath(path);
}

class Client {
  constructor(url = "http://127.0.0.1:6384", branch = null, auth = null, version = "v1") {
    this.url = url + "/api/" + version;
    this.auth = auth;
    this.branch = branch;
  }

  async request(method, url, body = null) {
    return request(method, this.url + url, body, this.auth, this.branch);
  }

  async find(path) {
    let res = await this.request("GET", "/module/" + pathString(path));
    if (res.status === 404) {
      return null;
    }

    return res;
  }

  async hash(path) {
    let res = await this.request("GET", "/hash/" + pathString(path));
    if (res.status === 404) {
      return null;
    }

    return await res.text();
  }

  async add(path, data) {
    let res = await this.request("POST", "/module/" + pathString(path), data);
    return await res.text();
  }

  async snapshot() {
    let res = await this.request("GET", "/snapshot");
    return await res.text();
  }

  async restore(hash, path = null) {
    let res = await this.request("POST", "/restore/" + hash + (path === null ? "" : "/" + pathString(path)));
    return res.ok;
  }

  async rollback(path = null) {
    let res = await this.request("POST", "/rollback/" + pathString(path));
    return res.ok;
  }

  async gc() {
    let res = await this.request("POST", "/gc");
    return res.ok;
  }

  async list(path = null) {
    let res = await this.request("GET", "/modules/" + pathString(path));
    return await res.json();
  }

  async branches() {
    let res = await this.request("GET", "/branches");
    return await res.json();
  }

  async createBranch(name) {
    let res = await this.request("POST", "/branch/" + name);
    return res.ok;
  }

  async deleteBranch(name) {
    let res = await this.request("DELETE", "/branch/" + name);
    return res.ok;
  }

  async watch(callback) {
    let ws = new WebSocket(this.url.replace("http", "ws") + "/watch");

    ws.onmessage = function(msg) {
      callback(JSON.parse(msg.data))
    };

    return ws;
  }
}
