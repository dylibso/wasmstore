import sys

sys.path.insert(0, ".")

from wasmstore import Client

def test_client():
    client = Client()
    modules = client.list()
    if len(modules) > 0:
        first = list(modules.keys())[0]
        assert (client.find(first) is not None)