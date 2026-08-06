// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use anyhow::Result;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

pub type Data = HashMap<String, Vec<String>>;

static CACHE: Lazy<RwLock<Option<Arc<Data>>>> = Lazy::new(|| RwLock::new(None));

async fn fetch() -> Result<Arc<Data>> {
    let value = reqwest::get(crate::IMAGE_LIST_URL)
        .await?
        .json::<serde_json::Value>()
        .await?;
    let data: Data = serde_json::from_value(value[">0.5.0"].clone())?;
    Ok(Arc::new(data))
}

pub async fn get() -> Result<Arc<Data>> {
    if let Some(data) = CACHE.read().await.as_ref() {
        return Ok(data.clone());
    }

    let mut cache = CACHE.write().await;
    if let Some(data) = cache.as_ref() {
        return Ok(data.clone());
    }

    let data = fetch().await?;
    *cache = Some(data.clone());
    Ok(data)
}

pub async fn refresh() -> Result<Arc<Data>> {
    let data = fetch().await?;
    *CACHE.write().await = Some(data.clone());
    Ok(data)
}

pub async fn clear_cache() {
    *CACHE.write().await = None;
}
