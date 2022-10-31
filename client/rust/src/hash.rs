#[derive(Debug, PartialEq, Eq, Clone, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
#[serde(transparent)]
pub struct Hash(pub String);

impl From<String> for Hash {
    fn from(s: String) -> Self {
        Hash(s)
    }
}

impl From<Hash> for String {
    fn from(h: Hash) -> Self {
        h.0
    }
}

impl AsRef<str> for Hash {
    fn as_ref(&self) -> &str {
        self.0.as_str()
    }
}

#[derive(Debug, PartialEq, Eq, Clone, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
#[serde(transparent)]
pub struct Commit(pub String);

impl From<String> for Commit {
    fn from(s: String) -> Self {
        Commit(s)
    }
}

impl From<Commit> for String {
    fn from(h: Commit) -> Self {
        h.0
    }
}

impl AsRef<str> for Commit {
    fn as_ref(&self) -> &str {
        self.0.as_str()
    }
}
