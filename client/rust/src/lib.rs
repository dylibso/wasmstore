pub use anyhow::Error;

mod hash;
mod path;

pub use hash::{Commit, Hash};
pub use path::Path;

pub struct Client {
    url: reqwest::Url,
    client: reqwest::Client,
    version: Version,
    auth: Option<String>,
    branch: Option<String>,
}

#[derive(serde::Deserialize)]
pub struct CommitInfo {
    pub hash: Commit,
    pub parents: Option<Vec<Commit>>,
    pub date: i64,
    pub author: String,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Version {
    V1,
}

impl Client {
    pub fn new(url: impl reqwest::IntoUrl, version: Version) -> Result<Client, Error> {
        let url = url.into_url()?;

        let client = reqwest::Client::new();

        Ok(Client {
            url,
            client,
            version,
            auth: None,
            branch: None,
        })
    }

    pub fn with_auth(mut self, auth: String) -> Client {
        self.auth = Some(auth);
        self
    }

    pub fn with_branch(mut self, branch: String) -> Client {
        self.branch = Some(branch);
        self
    }

    pub async fn request(
        &self,
        method: reqwest::Method,
        endpoint: impl AsRef<str>,
        body: Option<Vec<u8>>,
    ) -> Result<reqwest::Response, Error> {
        let url = self.url.join(endpoint.as_ref())?;
        let mut builder = self.client.request(method, url);

        if let Some(auth) = &self.auth {
            builder = builder.header("Wasmstore-Auth", auth);
        }

        if let Some(branch) = &self.branch {
            builder = builder.header("Wasmstore-Branch", branch);
        }

        if let Some(body) = body {
            builder = builder.body(body);
        }

        let res = builder.send().await?;
        Ok(res)
    }

    fn endpoint(&self, endpoint: &str) -> String {
        let v = match self.version {
            Version::V1 => "v1",
        };
        format!("/api/{v}{endpoint}")
    }

    pub async fn find(&self, path: impl Into<Path>) -> Result<Option<(Vec<u8>, Hash)>, Error> {
        let path = path.into();
        let p = format!("/module/{}", path.to_string());
        let res = self
            .request(reqwest::Method::GET, self.endpoint(&p), None)
            .await?;
        if res.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }

        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        let hash = res
            .headers()
            .get("Wasmstore-Hash")
            .expect("Wasmstore-Hash header is unset in find response")
            .to_str()?
            .to_string();
        let b = res.bytes().await?;
        Ok(Some((b.to_vec(), Hash(hash))))
    }

    pub async fn hash(&self, path: impl Into<Path>) -> Result<Option<Hash>, Error> {
        let path = path.into();
        let p = format!("/hash/{}", path.to_string());
        let res = self
            .request(reqwest::Method::GET, self.endpoint(&p), None)
            .await?;
        if res.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }

        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }

        let b = res.text().await?;
        Ok(Some(Hash(b)))
    }

    pub async fn add(&self, path: impl Into<Path>, data: Vec<u8>) -> Result<Hash, Error> {
        let path = path.into();
        let p = format!("/module/{}", path.to_string());
        let res = self
            .request(reqwest::Method::POST, self.endpoint(&p), Some(data))
            .await?;

        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }

        let b = res.text().await?;
        Ok(Hash(b))
    }

    pub async fn remove(&self, path: impl Into<Path>) -> Result<(), Error> {
        let path = path.into();
        let p = format!("/module/{}", path.to_string());
        let res = self
            .request(reqwest::Method::DELETE, self.endpoint(&p), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn gc(&self) -> Result<(), Error> {
        let res = self
            .request(reqwest::Method::POST, self.endpoint("/gc"), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn list(
        &self,
        path: impl Into<Path>,
    ) -> Result<std::collections::BTreeMap<Path, Hash>, Error> {
        let path = path.into();
        let p = format!("/modules/{}", path.to_string());
        let res = self
            .request(reqwest::Method::GET, self.endpoint(&p), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        let res: std::collections::BTreeMap<String, String> = res.json().await?;
        Ok(res
            .into_iter()
            .map(|(k, v)| (Path::String(k), Hash(v)))
            .collect())
    }

    pub async fn versions(&self, path: impl Into<Path>) -> Result<Vec<(Hash, Commit)>, Error> {
        let url = format!("/versions/{}", path.into().to_string());
        let res = self
            .request(reqwest::Method::GET, self.endpoint(&url), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(res.json().await?)
    }

    pub async fn branches(&self) -> Result<Vec<String>, Error> {
        let res = self
            .request(reqwest::Method::GET, self.endpoint("/branches"), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(res.json().await?)
    }

    pub async fn create_branch(&self, name: impl AsRef<str>) -> Result<(), Error> {
        let p = format!("/branch/{}", name.as_ref());
        let res = self
            .request(reqwest::Method::POST, self.endpoint(&p), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn delete_branch(&self, name: impl AsRef<str>) -> Result<(), Error> {
        let p = format!("/branch/{}", name.as_ref());
        let res = self
            .request(reqwest::Method::DELETE, self.endpoint(&p), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn snapshot(&self) -> Result<Commit, Error> {
        let res = self
            .request(reqwest::Method::GET, self.endpoint("/snapshot"), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        let hash = res.text().await?;
        Ok(Commit(hash))
    }

    pub async fn restore(&self, hash: &Commit) -> Result<(), Error> {
        let res = self
            .request(
                reqwest::Method::POST,
                self.endpoint(&format!("/restore/{}", hash.0)),
                None,
            )
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn restore_path(&self, hash: &Commit, path: impl Into<Path>) -> Result<(), Error> {
        let res = self
            .request(
                reqwest::Method::POST,
                self.endpoint(&format!("/restore/{}/{}", hash.0, path.into().to_string())),
                None,
            )
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn rollback(&self, path: impl Into<Path>) -> Result<(), Error> {
        let res = self
            .request(
                reqwest::Method::POST,
                self.endpoint(&format!("/rollback/{}", path.into().to_string())),
                None,
            )
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        Ok(())
    }

    pub async fn contains(&self, path: impl Into<Path>) -> Result<bool, Error> {
        let res = self
            .request(
                reqwest::Method::HEAD,
                self.endpoint(&format!("/module/{}", path.into().to_string())),
                None,
            )
            .await?;
        Ok(res.status().is_success())
    }

    pub async fn set(&self, path: impl Into<Path>, hash: &Hash) -> Result<Hash, Error> {
        let path = path.into();
        let p = format!("/hash/{}/{}", hash.0, path.to_string());
        let res = self
            .request(reqwest::Method::POST, self.endpoint(&p), None)
            .await?;

        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }

        let b = res.text().await?;
        Ok(Hash(b))
    }

    pub async fn commit_info(&self, commit: &Commit) -> Result<CommitInfo, Error> {
        let p = format!("/commit/{}", commit.0);
        let res = self
            .request(reqwest::Method::GET, self.endpoint(&p), None)
            .await?;
        if !res.status().is_success() {
            return Err(Error::msg(res.text().await?));
        }
        let res: CommitInfo = res.json().await?;
        Ok(res)
    }
}

#[cfg(test)]
mod tests {
    use crate::*;

    #[tokio::test]
    async fn basic_test() {
        let client = Client::new("http://127.0.0.1:6384", Version::V1).unwrap();

        let data = std::fs::read("../../test/a.wasm").unwrap();
        let hash = client.add("test.wasm", data).await;
        println!("HASH: {hash:?}");

        let data = client.find(hash.unwrap()).await.unwrap();
        let data1 = client.find("test.wasm").await.unwrap();

        let hash = client.snapshot().await.unwrap();
        client.commit_info(&hash).await.unwrap();

        assert!(data.is_some());
        assert!(data1.is_some());
        assert_eq!(data, data1);
    }
}
