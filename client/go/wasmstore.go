package wasmstore

import (
	"encoding/json"
	"io"
	"io/ioutil"
	"net/http"
	"net/url"
	"strings"
)

type Hash = string
type CommitHash = string

type Client struct {
	URL    *url.URL
	Config *Config
}

type Config struct {
	Auth    string
	Branch  string
	Version string
}

type CommitInfo struct {
	Hash    CommitHash   `json:"hash"`
	Parents []CommitHash `json:"parents,omitempty"`
	Date    int64        `json:"date"`
	Author  string       `json:"author"`
	Message string       `json:"message"`
}

func JoinPath(path []string) string {
	return strings.Join(path[:], "/")
}

func SplitPath(path string) []string {
	if path == "/" || path == "" {
		return []string{}
	}
	return strings.Split(path, "/")
}

func NewClient(u string, config *Config) (Client, error) {
	version := "v1"
	if config != nil && config.Version != "" {
		version = config.Version
	}

	url, err := url.Parse(u + "/api/" + version)
	if err != nil {
		return Client{}, err
	}

	return Client{
		URL:    url,
		Config: config,
	}, nil
}

func (c *Client) Request(method string, route string, body io.Reader) ([]byte, int, error) {
	req, err := http.NewRequest(method, c.URL.String()+route, body)
	if err != nil {
		return nil, 0, err
	}

	if c.Config != nil {
		if c.Config.Auth != "" {
			req.Header.Add("Wasmstore-Auth", c.Config.Auth)
		}

		if c.Config.Branch != "" {
			req.Header.Add("Wasmstore-Branch", c.Config.Branch)
		}
	}

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, err
	}

	resBody, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return nil, 0, err
	}

	res.Body.Close()
	return resBody, res.StatusCode, nil
}

func (c *Client) Find(path ...string) ([]byte, bool, error) {
	res, code, err := c.Request("GET", "/module/"+JoinPath(path), nil)
	if err != nil {
		return nil, false, err
	}

	return res, code == 200, nil
}

func (c *Client) Add(wasm io.Reader, path ...string) (Hash, error) {
	res, _, err := c.Request("POST", "/module/"+JoinPath(path), wasm)
	if err != nil {
		return "", err
	}

	return string(res), nil
}

func (c *Client) Set(wasm io.Reader, commit CommitHash, path ...string) (bool, error) {
	_, code, err := c.Request("POST", "/module/"+JoinPath(path), wasm)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) Hash(path ...string) (Hash, error) {
	res, _, err := c.Request("GET", "/hash/"+JoinPath(path), nil)
	if err != nil {
		return "", err
	}

	return string(res), nil
}

func (c *Client) Remove(path ...string) (bool, error) {
	_, code, err := c.Request("DELETE", "/module/"+JoinPath(path), nil)
	if err != nil {
		return false, nil
	}

	return code == 200, nil
}

func (c *Client) Snapshot() (CommitHash, error) {
	res, _, err := c.Request("GET", "/snapshot", nil)
	if err != nil {
		return "", err
	}

	return string(res), nil
}

func (c *Client) Restore(hash CommitHash, path ...string) (bool, error) {
	_, code, err := c.Request("POST", "/restore/"+hash+"/"+JoinPath(path), nil)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) Rollback(path ...string) (bool, error) {
	_, code, err := c.Request("POST", "/rollback/"+JoinPath(path), nil)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) Merge(branch string) (bool, error) {
	_, code, err := c.Request("POST", "/merge/"+branch, nil)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) Gc() (bool, error) {
	_, code, err := c.Request("POST", "/gc", nil)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) CreateBranch(branch string) (bool, error) {
	_, code, err := c.Request("POST", "/branch/"+branch, nil)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) DeleteBranch(branch string) (bool, error) {
	_, code, err := c.Request("DELETE", "/branch/"+branch, nil)
	if err != nil {
		return false, err
	}

	return code == 200, nil
}

func (c *Client) Branches() ([]string, error) {
	res, _, err := c.Request("GET", "/branches", nil)
	if err != nil {
		return nil, err
	}

	var s []string
	err = json.Unmarshal(res, &s)
	if err != nil {
		return nil, err
	}

	return s, nil
}

func (c *Client) Versions(path ...string) ([][]Hash, error) {
	res, _, err := c.Request("GET", "/versions/"+JoinPath(path), nil)
	if err != nil {
		return nil, err
	}

	var s [][]Hash
	err = json.Unmarshal(res, &s)
	if err != nil {
		return nil, err
	}

	return s, nil
}

func (c *Client) List(path ...string) (map[string]Hash, error) {
	res, _, err := c.Request("GET", "/modules/"+JoinPath(path), nil)
	if err != nil {
		return nil, err
	}

	var s map[string]Hash
	err = json.Unmarshal(res, &s)
	return s, err
}

func (c *Client) Contains(path ...string) (bool, error) {
	_, code, err := c.Request("HEAD", "/module/"+JoinPath(path), nil)
	return code == 200, err
}

func (c *Client) CommitInfo(hash CommitHash) (CommitInfo, error) {
	res, _, err := c.Request("GET", "/commit/"+hash, nil)
	if err != nil {
		return CommitInfo{}, err
	}

	var s CommitInfo
	err = json.Unmarshal(res, &s)
	if err != nil {
		return CommitInfo{}, err
	}

	return s, nil
}

func (c *Client) Auth(method string) (bool, error) {
	_, code, err := c.Request(method, "/auth", nil)
	return code == 200, err
}
