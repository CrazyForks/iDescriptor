// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantList, QVariantMap};

use crate::constants::FS_GALLERY_PROVIDER_NAME;
use crate::device_ctx;
use crate::gallery_fs_provider::build_fs_provider;
use crate::gallery_sqlite_provider::{build_sqlite_provider, build_sqlite_vfs_provider};
use crate::qt_threading::QtThreading;
use crate::utils::{MediaFileType, create_album_info, media_file_type};
use crate::{RUNTIME, qvariantmap_insert};
use ::log::{debug, info, warn};
use idevice::afc::AfcClient;
use idevice::afc::opcode::AfcFopenMode;
use macros::QtThreading;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub type GalleryFuture<T> = Pin<Box<dyn Future<Output = anyhow::Result<T>> + Send>>;

pub trait GalleryProvider: Send + Sync {
    fn read_albums(&self) -> GalleryFuture<(Vec<GalleryAlbum>, i32)>;
    fn reload(&self) -> GalleryFuture<(Vec<GalleryAlbum>, i32)>;
    fn query_album(
        &self,
        id: i32,
        media_filter: GalleryMediaFilter,
        most_recent_first: bool,
    ) -> GalleryFuture<Vec<String>>;
    fn query_gallery_size(&self) -> GalleryFuture<u64>;
    fn name(&self) -> String;
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum GalleryBackend {
    Fs,
    #[default]
    Sqlite,
    SqliteVfs,
}

impl GalleryBackend {
    fn from_i32(value: i32) -> Self {
        match value {
            0 => Self::Fs,
            2 => Self::SqliteVfs,
            _ => Self::Sqlite,
        }
    }
}

#[derive(Clone)]
pub struct GalleryAlbum {
    pub id: i32,
    pub name: String,
    pub item_count: i32,
    pub preview_path: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GalleryMediaFilter {
    All,
    Images,
    Videos,
}

impl GalleryMediaFilter {
    fn from_i32(value: i32) -> Self {
        match value {
            1 => Self::Images,
            2 => Self::Videos,
            _ => Self::All,
        }
    }

    fn as_i32(self) -> i32 {
        match self {
            Self::All => 0,
            Self::Images => 1,
            Self::Videos => 2,
        }
    }
}

pub fn matches_media_filter(path: &str, filter: GalleryMediaFilter) -> bool {
    match (filter, media_file_type(path)) {
        (
            GalleryMediaFilter::All,
            MediaFileType::Image | MediaFileType::Heic | MediaFileType::Video,
        ) => true,
        (GalleryMediaFilter::Images, MediaFileType::Image | MediaFileType::Heic) => true,
        (GalleryMediaFilter::Videos, MediaFileType::Video) => true,
        _ => false,
    }
}

#[derive(QObject, Default, QtThreading)]
#[allow(non_snake_case)]
pub struct Query {
    base: qt_base_class!(trait QObject),
    udid: String,
    connection_id: u64,
    ios_version: u32,
    albums: qt_property!(QVariantList; NOTIFY albumsChanged),
    albumsChanged: qt_signal!(),
    failed_albums_count: qt_property!(i32; NOTIFY failedAlbumsCountChanged),
    failedAlbumsCountChanged: qt_signal!(),
    provider: Option<Arc<dyn GalleryProvider>>,
    state: qt_property!(QVariantMap; NOTIFY stateChanged),
    stateChanged: qt_signal!(),
    reloading: qt_property!(bool; NOTIFY reloadingChanged),
    reloadingChanged: qt_signal!(),

    init: qt_method!(fn(&mut self, gallery_backend: i32)),
    reload: qt_method!(fn(&mut self)),
    read_albums: qt_method!(fn(&mut self)),
    query_album: qt_method!(fn(&mut self, id: i32, media_filter: i32, most_recent_first: bool)),
    resolve_album_export:
        qt_method!(fn(&mut self, request_id: QString, album_id: i32, album_name: QString)),
    albumQueried: qt_signal!(id: i32, media_filter: i32, most_recent_first: bool, items: QStringList),
    albumQueryFailed: qt_signal!(
        id: i32,
        media_filter: i32,
        most_recent_first: bool,
        error: QString
    ),
    albumExportResolved: qt_signal!(
        request_id: QString,
        album_id: i32,
        album_name: QString,
        items: QStringList
    ),
    gallerySizeQueried: qt_signal!(size: u64),
    reloadFinished: qt_signal!(success: bool, revision: i32, error: QString),
    is_init: bool,
    gallery_backend: GalleryBackend,
    revision: i32,
    gallery_load_started_at: Option<Instant>,
}

fn new_state(init: bool, err: &str, backend: &str) -> QVariantMap {
    let mut state = QVariantMap::default();
    qvariantmap_insert!(state, "init", init);
    qvariantmap_insert!(state, "err", QString::from(err));
    qvariantmap_insert!(state, "backend", QString::from(backend));

    state
}

impl Query {
    pub fn with_device_attr(udid: QString, connection_id: u64, ios_version: u32) -> Self {
        let state = new_state(false, "", "");

        let mut def = Self::default();
        def.state = state;
        def.ios_version = ios_version;
        def.udid = udid.to_string();
        def.connection_id = connection_id;
        def
    }

    fn init(&mut self, gallery_backend: i32) {
        if self.is_init {
            debug!("Query: already initialized, skipping init");
            return;
        }
        let gallery_backend = GalleryBackend::from_i32(gallery_backend);
        debug!(
            "Query: initializing with udid={} ios_version={} gallery_backend={gallery_backend:?}",
            self.udid, self.ios_version
        );
        self.gallery_backend = gallery_backend;
        self.is_init = true;
        self.gallery_load_started_at = Some(Instant::now());
        let gallery_load_started_at = self.gallery_load_started_at;
        let udid_clone = self.udid.clone();
        let udid_clone_for_fallback = self.udid.clone();
        let connection_id = self.connection_id;
        let ios_version = self.ios_version;
        let qt_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let res: anyhow::Result<Arc<dyn GalleryProvider>> = (async {
                let device = device_ctx::get_device_for_connection_opt(udid_clone, connection_id)
                    .await
                    .ok_or_else(|| anyhow::anyhow!("device connection is no longer current"))?;
                let prov = match gallery_backend {
                    GalleryBackend::Fs => build_fs_provider(device.afc).await?,
                    GalleryBackend::Sqlite => {
                        build_sqlite_provider(device.afc, ios_version).await?
                    }
                    GalleryBackend::SqliteVfs => {
                        build_sqlite_vfs_provider(device.afc, device.provider, ios_version).await?
                    }
                };

                if gallery_backend == GalleryBackend::Fs {
                    //FIXME:untill there is a better way to query the gallery size for fs backend, we will just return 0
                    // let gallery_size = prov.query_gallery_size().await?;
                    qt_thread.queue(move |s| {
                        s.gallerySizeQueried(0);
                    });
                    /*
                        Better not do this for fs backend
                        as this will most likely succeed
                    */
                    // prov.read_albums().await?;
                } else {
                    let gallery_size = prov.query_gallery_size().await.unwrap_or(0);
                    //fire this immediately so that the diskusage.qml can stop loading as soon as possible
                    qt_thread.queue(move |s| {
                        s.gallerySizeQueried(gallery_size);
                    });
                    prov.read_albums().await?;
                }
                Ok(prov)
            })
            .await;

            match res {
                Ok(provider) => {
                    info!(
                        "Gallery provider ready for albums page: backend={} elapsed={:?}",
                        provider.name(),
                        gallery_load_started_at
                            .map(|started_at| started_at.elapsed())
                            .unwrap_or_default()
                    );
                    qt_thread.queue(move |s| {
                        println!("Gallery provider initialized successfully");
                        let state = new_state(true, "", &provider.name());
                        s.provider = Some(provider);
                        s.state = state;
                        s.stateChanged();
                    });
                }
                Err(e) => {
                    warn!(
                        "Gallery provider initialization failed after {:?}: {e}",
                        gallery_load_started_at
                            .map(|started_at| started_at.elapsed())
                            .unwrap_or_default()
                    );
                    println!("Gallery provider initialization failed: {}", e.to_string());
                    qt_thread.queue(move |s| {
                        s.gallerySizeQueried(0);
                    });

                    /*
                        fallback to fs if sqlite fails to query properly
                        currently iOS 15....26 support is good
                    */
                    if gallery_backend != GalleryBackend::Fs {
                        let fs_res: anyhow::Result<Arc<dyn GalleryProvider>> = async {
                            let afc_arc = device_ctx::get_device_for_connection_opt(
                                udid_clone_for_fallback,
                                connection_id,
                            )
                            .await
                            .ok_or_else(|| {
                                anyhow::anyhow!("device connection is no longer current")
                            })?
                            .afc;
                            let prov = build_fs_provider(afc_arc).await?;
                            prov.read_albums().await?;
                            Ok(prov)
                        }
                        .await;

                        match fs_res {
                            Ok(fs) => {
                                qt_thread.queue(move |s| {
                                    println!("Fallback fs provider initialized successfully");
                                    let state = new_state(true, "", &fs.name());
                                    s.provider = Some(fs);
                                    s.state = state;
                                    s.stateChanged();
                                });
                            }
                            Err(e) => {
                                debug!(
                                    "Failed to fallback to fs backend for gallery: {}",
                                    e.to_string()
                                );
                                qt_thread.queue(move |s| {
                                    let state =
                                        new_state(false, &e.to_string(), FS_GALLERY_PROVIDER_NAME);
                                    s.state = state;
                                    s.stateChanged();
                                });
                            }
                        };
                    } else {
                        qt_thread.queue(move |s| {
                            let state = new_state(false, &e.to_string(), FS_GALLERY_PROVIDER_NAME);
                            s.state = state;
                            s.stateChanged();
                        });
                    }
                }
            };
        });
    }

    fn reload(&mut self) {
        if self.reloading {
            debug!("Query: reload already in progress, skipping");
            return;
        }

        let Some(provider) = self.provider.clone() else {
            debug!("Query: no provider available, cannot reload");
            return;
        };

        self.reloading = true;
        self.reloadingChanged();
        self.state[QString::from("err")] = QVariant::from(QString::default());
        self.stateChanged();

        let q_thread = self.qt_thread();
        let started_at = Instant::now();
        RUNTIME.spawn(async move {
            let result = provider.reload().await;
            match &result {
                Ok((provider_albums, failed_albums_count)) => info!(
                    "Gallery albums page reloaded: backend={} albums={} failed_albums={} elapsed={:?}",
                    provider.name(),
                    provider_albums.len(),
                    failed_albums_count,
                    started_at.elapsed()
                ),
                Err(error) => warn!(
                    "Gallery albums page reload failed: backend={} elapsed={:?} error={error}",
                    provider.name(),
                    started_at.elapsed()
                ),
            }
            q_thread.queue(move |query| {
                // saturating_add is probably overkill
                let next_revision = query.revision.saturating_add(1);
                match result {
                    Ok((provider_albums, failed_albums_count)) => {
                        query.albums = albums_to_variant_list(provider_albums);
                        query.failed_albums_count = failed_albums_count;
                        query.state[QString::from("init")] = QVariant::from(true);
                        query.state[QString::from("err")] = QVariant::from(QString::default());
                        query.revision = next_revision;
                        query.albumsChanged();
                        query.failedAlbumsCountChanged();
                        query.stateChanged();
                    }
                    Err(err) => {
                        let error = err.to_string();
                        query.state[QString::from("init")] = QVariant::from(false);
                        query.state[QString::from("err")] =
                            QVariant::from(QString::from(error.clone()));
                        query.stateChanged();
                        query.reloading = false;
                        query.reloadingChanged();
                        query.reloadFinished(false, query.revision, QString::from(error));

                        return;
                    }
                }

                query.reloading = false;
                query.reloadingChanged();
                query.reloadFinished(true, query.revision, QString::default());
            });
        });
    }

    fn read_albums(&mut self) {
        let q_thread = self.qt_thread();
        let provider = match &self.provider {
            Some(provider) => provider.clone(),
            None => {
                debug!("Query: no provider available, cannot read albums");
                return;
            }
        };
        let backend_name = provider.name();
        let read_started_at = Instant::now();
        let gallery_load_started_at = self.gallery_load_started_at;

        RUNTIME.spawn(async move {
            let mut albums = QVariantList::default();
            match provider.read_albums().await {
                Ok((provider_albums, failed_albums_count)) => {
                    info!(
                        "Gallery albums page loaded: backend={} albums={} failed_albums={} read_elapsed={:?} total_elapsed={:?}",
                        backend_name,
                        provider_albums.len(),
                        failed_albums_count,
                        read_started_at.elapsed(),
                        gallery_load_started_at
                            .map(|started_at| started_at.elapsed())
                            .unwrap_or_default()
                    );
                    albums = albums_to_variant_list(provider_albums);

                    q_thread.queue(move |q_self| {
                        println!("Albums read fine firing events");
                        q_self.state[QString::from("err")] = QVariant::from(QString::default());
                        q_self.albums = albums;
                        q_self.albumsChanged();
                        q_self.failed_albums_count = failed_albums_count;
                        q_self.failedAlbumsCountChanged();
                        q_self.stateChanged();
                    })
                }
                Err(e) => {
                    warn!(
                        "Gallery albums page load failed: backend={} read_elapsed={:?} total_elapsed={:?} error={e}",
                        backend_name,
                        read_started_at.elapsed(),
                        gallery_load_started_at
                            .map(|started_at| started_at.elapsed())
                            .unwrap_or_default()
                    );
                    q_thread.queue(move |q_self| {
                        println!("Error reading albums {}", e);
                        q_self.state[QString::from("err")] =
                            QVariant::from(QString::from(e.to_string()));
                        q_self.albums = albums;
                        q_self.albumsChanged();
                        q_self.failed_albums_count = 0;
                        q_self.failedAlbumsCountChanged();
                        q_self.stateChanged();
                    });
                }
            }
        });
    }

    fn query_album(&mut self, id: i32, media_filter: i32, most_recent_first: bool) {
        let media_filter = GalleryMediaFilter::from_i32(media_filter);
        let media_filter_id = media_filter.as_i32();
        let provider = match &self.provider {
            Some(provider) => provider.clone(),
            None => {
                self.albumQueryFailed(
                    id,
                    media_filter_id,
                    most_recent_first,
                    QString::from("Gallery provider is not initialized"),
                );
                return;
            }
        };

        let revision = self.revision;
        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            match provider
                .query_album(id, media_filter, most_recent_first)
                .await
            {
                Ok(paths) => {
                    let mut list: QStringList = QStringList::default();
                    for path in paths {
                        list.push(QString::from(path));
                    }

                    println!("Album loaded has length :{}", list.len());
                    q_thread.queue(move |q| {
                        if q.revision == revision {
                            q.albumQueried(id, media_filter_id, most_recent_first, list);
                        } else {
                            debug!(
                                "Discarding stale album query for revision {revision}; current revision is {}",
                                q.revision
                            );
                        }
                    });
                }
                Err(e) => {
                    let error = e.to_string();
                    println!("Error querying album {error}");
                    q_thread.queue(move |q| {
                        if q.revision == revision {
                            q.albumQueryFailed(
                                id,
                                media_filter_id,
                                most_recent_first,
                                QString::from(error),
                            );
                        }
                    });
                }
            }
        });
    }

    fn resolve_album_export(&mut self, request_id: QString, album_id: i32, album_name: QString) {
        let provider = match &self.provider {
            Some(provider) => provider.clone(),
            None => return,
        };

        let request_id = request_id.to_string();
        let album_name = album_name.to_string();
        let q_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            match provider
                .query_album(album_id, GalleryMediaFilter::All, true)
                .await
            {
                Ok(paths) => {
                    let mut list = QStringList::default();
                    for path in paths {
                        list.push(QString::from(path));
                    }

                    q_thread.queue(move |q| {
                        q.albumExportResolved(
                            QString::from(request_id),
                            album_id,
                            QString::from(album_name),
                            list,
                        );
                    });
                }
                Err(e) => {
                    println!("Error resolving album export {}", e.to_string());
                    q_thread.queue(move |q| {
                        q.albumExportResolved(
                            QString::from(request_id),
                            album_id,
                            QString::from(album_name),
                            QStringList::default(),
                        );
                    });
                }
            }
        });
    }
}

fn albums_to_variant_list(provider_albums: Vec<GalleryAlbum>) -> QVariantList {
    let mut albums = QVariantList::default();
    for album in provider_albums {
        let (asset_dir, asset_file_name) = split_device_path(&album.preview_path);
        let album_data = create_album_info(
            &album.name,
            album.id,
            album.item_count,
            asset_dir,
            asset_file_name,
        );
        albums.push(QVariant::from(&QString::from(album_data)));
    }
    albums
}

fn split_device_path(path: &str) -> (String, String) {
    match path.rsplit_once('/') {
        Some((dir, name)) => (dir.to_string(), name.to_string()),
        None => (String::default(), path.to_string()),
    }
}

#[allow(dead_code)]
fn patch_wal_legacy_mode(bytes: &mut [u8]) {
    // HACK: WAL -> legacy mode patch
    if bytes.len() > 20 && bytes[18] == 0x02 {
        bytes[18] = 0x01;
        bytes[19] = 0x01;
    }
}

pub async fn export_afc_file(
    afc: &mut AfcClient,
    remote_path: &str,
    local_path: &Path,
) -> anyhow::Result<()> {
    let mut remote_file = afc.open(remote_path, AfcFopenMode::RdOnly).await?;
    let transfer_result: anyhow::Result<()> = async {
        let mut local_file = tokio::fs::File::create(local_path).await?;
        let mut chunk = vec![0u8; crate::io_manager::DEFAULT_CHUNK_SIZE];

        loop {
            let n = remote_file.read(&mut chunk).await?;
            if n == 0 {
                break;
            }
            local_file.write_all(&chunk[..n]).await?;
        }

        local_file.flush().await?;
        Ok(())
    }
    .await;

    let close_result = remote_file.close().await;
    match (transfer_result, close_result) {
        (Ok(()), Ok(())) => Ok(()),
        (Ok(()), Err(close_error)) => Err(close_error.into()),
        (Err(transfer_error), Ok(())) => Err(transfer_error),
        (Err(transfer_error), Err(close_error)) => {
            warn!("Failed to close {remote_path} after transfer error: {close_error}");
            Err(transfer_error)
        }
    }
}

pub fn is_apple_dcim_folder(name: &str) -> bool {
    apple_dcim_folder_id(name).is_some()
}

pub fn apple_dcim_folder_id(name: &str) -> Option<i32> {
    name.strip_suffix("APPLE")
        .filter(|suffix| !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit()))
        .and_then(|suffix| suffix.parse().ok())
}

pub fn is_previewable_media_file(path: &str) -> bool {
    matches!(
        media_file_type(path),
        MediaFileType::Image | MediaFileType::Heic | MediaFileType::Video
    )
}
