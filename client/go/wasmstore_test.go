package wasmstore

import (
	"testing"
)

func TestClient(t *testing.T) {
	client, err := NewClient("http://127.0.0.1:6384", nil)
	if err != nil {
		t.Error(err)
	}

	modules, err := client.List()
	if err != nil {
		t.Error(err)
	}

	if len(modules) == 0 {
		return
	}

	for k, v := range modules {
		a, ok, err := client.Find(k)
		if err != nil {
			t.Error(err)
		}

		if !ok {
			t.Error("not ok")
		}

		b, ok, err := client.Find(v)
		if err != nil {
			t.Error(err)
		}

		if !ok {
			t.Error("not ok")
		}

		if len(a) != len(b) {
			t.Error("values have different lengths")
		}
		for i := range a {
			if a[i] != b[i] {
				t.Error("values don't match")
			}
		}
		break
	}
}