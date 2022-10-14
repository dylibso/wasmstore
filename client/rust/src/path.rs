use crate::*;

#[derive(Debug, PartialEq, Eq, Clone, PartialOrd, Ord)]
pub enum Path {
    String(String),
    Vec(Vec<String>),
}

impl From<String> for Path {
    fn from(s: String) -> Self {
        Path::String(s)
    }
}

impl From<Hash> for Path {
    fn from(s: Hash) -> Self {
        Path::String(s.0)
    }
}

impl From<&Hash> for Path {
    fn from(s: &Hash) -> Self {
        Path::String(s.0.clone())
    }
}

impl From<Vec<String>> for Path {
    fn from(s: Vec<String>) -> Self {
        Path::Vec(s)
    }
}

impl From<Vec<&str>> for Path {
    fn from(v: Vec<&str>) -> Self {
        Path::Vec(v.iter().map(|x| x.to_string()).collect())
    }
}

impl From<&[&str]> for Path {
    fn from(v: &[&str]) -> Self {
        Path::Vec(v.iter().map(|x| x.to_string()).collect())
    }
}

impl From<&str> for Path {
    fn from(v: &str) -> Self {
        Path::String(v.to_string())
    }
}

impl ToString for Path {
    fn to_string(&self) -> String {
        match self {
            Path::String(s) => s.clone(),
            Path::Vec(v) => v.join("/"),
        }
    }
}
