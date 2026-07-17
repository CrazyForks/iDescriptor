use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantList, QVariantMap};

use crate::constants::{
    ALBUM_CONTENTS_QUERY_TEMPLATE, FAVS_ALBUM_ID, FAVS_ALBUM_QUERY, FAVS_QUERY,
    FS_GALLERY_PROVIDER_NAME, IOS_15_ALBUM_QUERY_STATEMENT, IOS_26_ALBUM_QUERY_STATEMENT,
    RECENTS_ALBUM_ID, RECENTS_ALBUM_QUERY, RECENTS_QUERY, SQLITE_GALLERY_PROVIDER_NAME,
};
use crate::device_ctx;
use crate::gallery_fs_provider::build_fs_provider;
use crate::gallery_sqlite_provider::{SqliteGalleryProvider, build_sqlite_provider};
use crate::qt_threading::QtThreading;
use crate::utils::{MediaFileType, create_album_info, media_file_type};
use crate::{RUNTIME, qvariantmap_insert};
use ::log::debug;
use anyhow::{Context, anyhow};
use idevice::afc::AfcClient;
use idevice::afc::opcode::AfcFopenMode;
use macros::QtThreading;
use rusqlite::{Connection, OptionalExtension};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;

pub type GalleryFuture<T> = Pin<Box<dyn Future<Output = anyhow::Result<T>> + Send>>;

pub trait GalleryProvider: Send + Sync {
    fn read_albums(&self) -> GalleryFuture<(Vec<GalleryAlbum>, i32)>;
    fn query_album(
        &self,
        id: i32,
        media_filter: GalleryMediaFilter,
        most_recent_first: bool,
    ) -> GalleryFuture<Vec<String>>;
    fn name(&self) -> String;
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
    ios_version: u32,
    albums: qt_property!(QVariantList; NOTIFY albumsChanged),
    albumsChanged: qt_signal!(),
    failed_albums_count: qt_property!(i32; NOTIFY failedAlbumsCountChanged),
    failedAlbumsCountChanged: qt_signal!(),
    provider: Option<Arc<dyn GalleryProvider>>,
    state: qt_property!(QVariantMap; NOTIFY stateChanged),
    stateChanged: qt_signal!(),

    init: qt_method!(fn(&mut self, use_sqlite_backend: bool)),
    read_albums: qt_method!(fn(&mut self)),
    query_album: qt_method!(fn(&mut self, id: i32, media_filter: i32, most_recent_first: bool)),
    resolve_album_export:
        qt_method!(fn(&mut self, request_id: QString, album_id: i32, album_name: QString)),
    albumQueried: qt_signal!(id: i32, media_filter: i32, most_recent_first: bool, items: QStringList),
    albumExportResolved: qt_signal!(
        request_id: QString,
        album_id: i32,
        album_name: QString,
        items: QStringList
    ),
    is_init: bool,
}

fn new_state(init: bool, err: &str, backend: &str) -> QVariantMap {
    let mut state = QVariantMap::default();
    qvariantmap_insert!(state, "init", init);
    qvariantmap_insert!(state, "err", QString::from(err));
    qvariantmap_insert!(state, "backend", QString::from(backend));

    state
}

impl Query {
    pub fn with_device_attr(udid: QString, ios_version: u32) -> Self {
        let state = new_state(false, "", "");

        let mut def = Self::default();
        def.state = state;
        def.ios_version = ios_version;
        def.udid = udid.to_string();
        def
    }

    fn init(&mut self, use_sqlite_backend: bool) {
        if self.is_init {
            debug!("Query: already initialized, skipping init");
            return;
        }
        debug!(
            "Query: initializing with udid={} ios_version={} use_sqlite_backend={}",
            self.udid, self.ios_version, use_sqlite_backend
        );
        self.is_init = true;
        let udid_clone = self.udid.clone();
        let udid_clone_for_fallback = self.udid.clone();
        let ios_version = self.ios_version;
        let qt_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let res: anyhow::Result<Arc<dyn GalleryProvider>> = (async {
                let afc_arc = device_ctx::get_device(udid_clone).await?.afc;
                if use_sqlite_backend {
                    let mut afc = afc_arc.lock().await;
                    let prov = build_sqlite_provider(&mut afc, ios_version).await?;
                    prov.read_albums().await?;
                    Ok(prov)
                } else {
                    let prov = build_fs_provider(afc_arc).await?;
                    /*
                        Better not do this for fs backend
                        as this will most likely succeed
                    */
                    // prov.read_albums().await?;
                    Ok(prov)
                }
            })
            .await;

            match res {
                Ok(provider) => {
                    qt_thread.queue(move |s| {
                        println!("Gallery provider initialized successfully");
                        let state = new_state(true, "", &provider.name());
                        s.provider = Some(provider);
                        s.state = state;
                        s.stateChanged();
                    });
                }
                Err(e) => {
                    println!("Gallery provider initialization failed: {}", e.to_string());

                    /*
                        fallback to fs if sqlite fails to query properly
                        currently iOS 15....26 support is good
                    */
                    if use_sqlite_backend {
                        let fs_res: anyhow::Result<Arc<dyn GalleryProvider>> = async {
                            let afc_arc =
                                device_ctx::get_device(udid_clone_for_fallback).await?.afc;
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

    fn read_albums(&mut self) {
        let q_thread = self.qt_thread();
        let provider = match &self.provider {
            Some(provider) => provider.clone(),
            None => {
                println!("NO GALLERY PROVIDER");
                return;
            }
        };

        RUNTIME.spawn(async move {
            let mut albums = QVariantList::default();
            match provider.read_albums().await {
                Ok((provider_albums, failed_albums_count)) => {
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

                    q_thread.queue(move |q_self| {
                        println!("Albums read fine firing events");
                        q_self.state[QString::from("err")] = QVariant::from(QString::default());
                        q_self.albums = albums;
                        q_self.albumsChanged();
                        q_self.failed_albums_count = failed_albums_count;
                        q_self.failedAlbumsCountChanged();
                    })
                }
                Err(e) => {
                    q_thread.queue(move |q_self| {
                        println!("Error reading albums {}", e);
                        q_self.state[QString::from("err")] =
                            QVariant::from(QString::from(e.to_string()));
                        q_self.albums = albums;
                        q_self.albumsChanged();
                        q_self.failed_albums_count = 0;
                        q_self.failedAlbumsCountChanged();
                    });
                }
            }
        });
    }

    fn query_album(&mut self, id: i32, media_filter: i32, most_recent_first: bool) {
        let provider = match &self.provider {
            Some(provider) => provider.clone(),
            None => return,
        };

        let media_filter = GalleryMediaFilter::from_i32(media_filter);
        let media_filter_id = media_filter.as_i32();
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
                        q.albumQueried(id, media_filter_id, most_recent_first, list);
                    });
                }
                Err(e) => {
                    println!("Error querying album {}", e.to_string())
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

fn split_device_path(path: &str) -> (String, String) {
    match path.rsplit_once('/') {
        Some((dir, name)) => (dir.to_string(), name.to_string()),
        None => (String::default(), path.to_string()),
    }
}

// FIXME:we need patch the sqlite if , wal or shm
#[allow(dead_code)]
fn patch_wal_legacy_mode(bytes: &mut [u8]) {
    // HACK: WAL -> legacy mode patch
    // This is still needed for the old path where we can only export Photos.sqlite.
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
    let mut local_file = tokio::fs::File::create(local_path).await?;
    let mut chunk = vec![0u8; 1024 * 1024];

    loop {
        let n = remote_file.read(&mut chunk).await?;
        if n == 0 {
            break;
        }
        local_file.write_all(&chunk[..n]).await?;
    }

    local_file.flush().await?;
    remote_file.close().await.ok();
    Ok(())
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
