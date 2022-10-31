from requests import request


class Error(Exception):
    pass


def normalize_path(path):
    if isinstance(path, list):
        return "/".join(path)
    elif isinstance(path, str):
        return path.lstrip("/")
    else:
        raise Error("invalid path")


class Client:
    def __init__(
        self, 
        url="http://127.0.0.1:6384", 
        version="v1", 
        auth=None,
        branch=None
    ):
        self.url = url + "/api/" + version
        self.auth = auth
        self.branch = branch

    def request(self, method, route, body=None):
        headers = {}
        if self.auth is not None:
            headers["Wasmstore-Auth"] = self.auth
        if self.branch is not None:
            headers["Wasmstore-Branch"] = self.branch
        return request(method, self.url + route, headers=headers, data=body)

    def find(self, path):
        path = normalize_path(path)
        res = self.request("GET", "/module/" + path)
        if res.status_code == 404:
            return None
        return res.content

    def add(self, path, data):
        path = normalize_path(path)
        res = self.request("POST", "/module/" + path, body=data)
        return res.text

    def hash(self, path):
        path = normalize_path(path)
        res = self.request("GET", "/hash/" + path)
        return res.text

    def remove(self, path):
        path = normalize_path(path)
        res = self.request("DELETE", "/module/" + path)
        return res.ok

    def snapshot(self):
        res = self.request("GET", "/snapshot")
        return res.text

    def restore(self, hash, path=None):
        url = "/restore/" + hash
        if path is not None:
            url += "/"
            url += normalize_path(path)
        res = self.request("POST", url)
        return res.ok
        
    def rollback(self, path):
        res = self.request("POST", "/rollback/" + normalize_path(path))
        return res.ok

    def list(self, path=None):
        url = "/modules"
        if path is not None:
            url += "/" + path
        res = self.request("GET", url)
        return res.json()

    def branches(self):
        res = self.request("GET", "/branches")
        return res.json()

    def gc(self):
        res = self.request("POST", "/gc")
        return res.ok

    def create_branch(self, name):
        res = self.request("POST", "/branch/" + name)
        return res.ok

    def delete_branch(self, name):
        res = self.request("DELETE", "/branch/" + name)
        return res.ok

    def merge(self, branch):
        res = self.request("POST", "/merge/" + branch)
        return res.ok
