package wasmstore

import (
	"encoding/json"
	"io"
	"io/ioutil"
	"net/http"
	"net/url"
	"strings"
)

type Client struct {
	URL    *url.URL
	Config *Config
}

type Config struct {
	Auth    string
	Branch  string
	Version string
}

func makePath(path []string) string {
	return strings.Join(path[:], "/")
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
	res, code, err := c.Request("GET", "/module/"+makePath(path), nil)
	if err != nil {
		return nil, false, err
	}

	return res, code == 200, nil
}

func (c *Client) Add(wasm io.Reader, path ...string) (string, error) {
	res, _, err := c.Request("POST", "/module/"+makePath(path), wasm)
	if err != nil {
		return "", err
	}

	return string(res), nil
}

func (c *Client) Remove(path ...string) (bool, error) {
	_, code, err := c.Request("DELETE", "/module/"+makePath(path), nil)
	if err != nil {
		return false, nil
	}

	return code == 200, nil
}

func (c *Client) Snapshot() (string, error) {
	res, _, err := c.Request("GET", "/snapshot", nil)
	if err != nil {
		return "", err
	}

	return string(res), nil
}

func (c *Client) Restore(hash string) (bool, error) {
	_, code, err := c.Request("POST", "/restore/"+hash, nil)
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

func (c *Client) List(path ...string) ([]string, error) {
	res, _, err := c.Request("GET", "/modules/"+makePath(path), nil)
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
