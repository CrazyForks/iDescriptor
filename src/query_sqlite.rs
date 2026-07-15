use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantList, QVariantMap};

use crate::{RUNTIME, qvariantmap_insert};
use crate::constants::{
    ALBUM_CONTENTS_QUERY_TEMPLATE, FAVS_ALBUM_ID, FAVS_ALBUM_QUERY, FAVS_QUERY,
    IOS_15_ALBUM_QUERY_STATEMENT, IOS_26_ALBUM_QUERY_STATEMENT, RECENTS_ALBUM_ID,
    RECENTS_ALBUM_QUERY, RECENTS_QUERY, FS_GALLERY_PROVIDER_NAME, SQLITE_GALLERY_PROVIDER_NAME
};
use crate::device_ctx;
use crate::qt_threading::QtThreading;
use crate::utils::{MediaFileType, create_album_info, media_file_type};
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

const PHOTOS_SQLITE_REMOTE_PATH: &str = "/PhotoData/Photos.sqlite";
const PHOTOS_SQLITE_SHM_REMOTE_PATH: &str = "/PhotoData/Photos.sqlite-shm";
const PHOTOS_SQLITE_WAL_REMOTE_PATH: &str = "/PhotoData/Photos.sqlite-wal";
const DCIM_REMOTE_PATH: &str = "/DCIM";

type GalleryFuture<T> = Pin<Box<dyn Future<Output = anyhow::Result<T>> + Send>>;

trait GalleryProvider: Send + Sync {
    fn read_albums(&self) -> GalleryFuture<Vec<GalleryAlbum>>;
    fn query_album(
        &self,
        id: i32,
        media_filter: GalleryMediaFilter,
        most_recent_first: bool,
    ) -> GalleryFuture<Vec<String>>;
    fn name(&self) -> String;
}

#[derive(Clone)]
struct GalleryAlbum {
    id: i32,
    name: String,
    item_count: i32,
    preview_path: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GalleryMediaFilter {
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

fn matches_media_filter(path: &str, filter: GalleryMediaFilter) -> bool {
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

struct FsGalleryProvider {
    afc: Arc<Mutex<AfcClient>>,
    name: String
}

impl GalleryProvider for FsGalleryProvider {
    fn name(&self) -> String {
        self.name.clone()
    }

    fn read_albums(&self) -> GalleryFuture<Vec<GalleryAlbum>> {
        let afc = self.afc.clone();
        Box::pin(async move { read_fs_albums(afc).await })
    }

    fn query_album(
        &self,
        id: i32,
        media_filter: GalleryMediaFilter,
        most_recent_first: bool,
    ) -> GalleryFuture<Vec<String>> {
        let afc = self.afc.clone();
        let folder_path = format!("{}/{}APPLE", DCIM_REMOTE_PATH, id);

        Box::pin(async move {
            let mut afc = afc.lock().await;
            let file_names = afc.list_dir(&folder_path).await?;
            let mut items = Vec::new();
            for file_name in file_names {
                if file_name == "."
                    || file_name == ".."
                    || !matches_media_filter(&file_name, media_filter)
                {
                    continue;
                }

                let file_path = format!("{}/{}", folder_path, file_name);
                match afc.get_file_info(&file_path).await {
                    Ok(info) if info.st_ifmt != "S_IFDIR" => {
                        items.push((file_path, info.modified));
                    }
                    Ok(_) => {}
                    Err(e) => {
                        println!("Skipping DCIM file {}: {}", file_path, e);
                    }
                }
            }

            items.sort_by(|a, b| {
                let ordering = a.1.cmp(&b.1).then_with(|| a.0.cmp(&b.0));
                if most_recent_first {
                    ordering.reverse()
                } else {
                    ordering
                }
            });

            Ok(items.into_iter().map(|(path, _)| path).collect())
        })
    }
}

struct SqliteGalleryProvider {
    connection: Option<Arc<Mutex<Connection>>>,
    temp_dir: PathBuf,
    ios_version: u32,
    assets_table_name: String,
    assets_table_album_column: String,
    name: String
}

impl GalleryProvider for SqliteGalleryProvider {
    fn name(&self) -> String {
        self.name.clone()
    }

    fn read_albums(&self) -> GalleryFuture<Vec<GalleryAlbum>> {
        let con_arc = self
            .connection
            .as_ref()
            .expect("sqlite gallery connection is set")
            .clone();
        let ios_ver = self.ios_version;

        Box::pin(async move {
            println!("Runtime spawn for read_albums");
            let conn = con_arc.lock().await;
            let mut albums = Vec::new();

            //recents album
            let mut recents_stmt = conn.prepare(RECENTS_ALBUM_QUERY)?;

            // FIXME: can this be better handled ?
            let placeholder_or_empty = (String::default(), String::from("EMPTY"), 0);

            let recents_row = recents_stmt
                .query_row([], |r| {
                    let fname: String = r.get(0)?;
                    let fdir: String = r.get(1)?;
                    let count: i32 = r.get(2)?;
                    Ok((fname, fdir, count))
                })
                .optional()?;

            let (fname, fdir, count) = recents_row.unwrap_or(placeholder_or_empty.clone());
            albums.push(GalleryAlbum {
                id: RECENTS_ALBUM_ID,
                name: String::from("Recents"),
                item_count: count,
                preview_path: join_device_path(&fdir, &fname),
            });

            //favs
            let mut favs_stmt = conn.prepare(FAVS_ALBUM_QUERY)?;

            let favs_row = favs_stmt
                .query_row([], |r| {
                    let fname: String = r.get(0)?;
                    let fdir: String = r.get(1)?;
                    let count: i32 = r.get(2)?;
                    Ok((fname, fdir, count))
                })
                .optional()?;

            let (fname, fdir, count) = favs_row.unwrap_or(placeholder_or_empty.clone());
            albums.push(GalleryAlbum {
                id: FAVS_ALBUM_ID,
                name: String::from("Favorites"),
                item_count: count,
                preview_path: join_device_path(&fdir, &fname),
            });

            let q_stm = if ios_ver > 15 {
                IOS_26_ALBUM_QUERY_STATEMENT
            } else {
                IOS_15_ALBUM_QUERY_STATEMENT
            };

            let mut stmt = conn.prepare(q_stm)?;

            let rows_iter = stmt.query_map([], |row| {
                let album_id: i32 = row.get(0)?;
                let title: String = row.get(1)?;
                let item_count: i32 = row.get(2)?;
                let asset_dir: String = row.get(3)?;
                let asset_file_name: String = row.get(4)?;
                Ok((album_id, title, item_count, asset_dir, asset_file_name))
            })?;

            for row_res in rows_iter {
                let (album_id, title, item_count, asset_dir, asset_file_name) = row_res?;
                albums.push(GalleryAlbum {
                    id: album_id,
                    name: title,
                    item_count,
                    preview_path: join_device_path(&asset_dir, &asset_file_name),
                });
            }

            Ok(albums)
        })
    }

    fn query_album(
        &self,
        id: i32,
        media_filter: GalleryMediaFilter,
        most_recent_first: bool,
    ) -> GalleryFuture<Vec<String>> {
        let con_arc = self
            .connection
            .as_ref()
            .expect("sqlite gallery connection is set")
            .clone();
        let table_name = self.assets_table_name.clone();
        let album_column = self.assets_table_album_column.clone();

        Box::pin(async move {
            match id {
                FAVS_ALBUM_ID => query_favs(con_arc, media_filter, most_recent_first).await,
                RECENTS_ALBUM_ID => query_recents(con_arc, media_filter, most_recent_first).await,
                _ => {
                    query_sqlite_album(
                        con_arc,
                        table_name,
                        album_column,
                        id,
                        media_filter,
                        most_recent_first,
                    )
                    .await
                }
            }
        })
    }
}

impl Drop for SqliteGalleryProvider {
    fn drop(&mut self) {
        self.connection = None;

        if let Err(e) = std::fs::remove_dir_all(&self.temp_dir) {
            println!("Failed to remove temp gallery database dir: {}", e);
        }
    }
}

struct TempDirGuard {
    path: Option<PathBuf>,
}

impl TempDirGuard {
    fn new(path: PathBuf) -> Self {
        Self { path: Some(path) }
    }

    fn path(&self) -> &Path {
        self.path.as_deref().expect("temp dir path is set")
    }

    fn keep(mut self) -> PathBuf {
        self.path.take().expect("temp dir path is set")
    }
}

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        if let Some(path) = self.path.take() {
            if let Err(e) = std::fs::remove_dir_all(&path) {
                println!("Failed to remove temp gallery database dir: {}", e);
            }
        }
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

async fn export_afc_file(
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

fn join_device_path(dir: &str, file_name: &str) -> String {
    format!("{}/{}", dir.trim_end_matches('/'), file_name)
}

fn split_device_path(path: &str) -> (String, String) {
    match path.rsplit_once('/') {
        Some((dir, name)) => (dir.to_string(), name.to_string()),
        None => (String::default(), path.to_string()),
    }
}

fn is_apple_dcim_folder(name: &str) -> bool {
    apple_dcim_folder_id(name).is_some()
}

fn apple_dcim_folder_id(name: &str) -> Option<i32> {
    name.strip_suffix("APPLE")
        .filter(|suffix| !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit()))
        .and_then(|suffix| suffix.parse().ok())
}

fn is_previewable_media_file(path: &str) -> bool {
    matches!(
        media_file_type(path),
        MediaFileType::Image | MediaFileType::Heic | MediaFileType::Video
    )
}

async fn build_sqlite_provider(
    afc: &mut AfcClient,
    ios_version: u32,
) -> anyhow::Result<Arc<dyn GalleryProvider>> {
    let temp_dir =
        std::env::temp_dir().join(format!("idescriptor-photos-db-{}", uuid::Uuid::new_v4()));
    tokio::fs::create_dir_all(&temp_dir).await?;
    // this is so that if we fail to export the db, we don't leave a temp dir behind
    let temp_dir_guard = TempDirGuard::new(temp_dir);

    let gallery_db_path: PathBuf = temp_dir_guard.path().join("Photos.sqlite");
    let gallery_db_shm_path: PathBuf = temp_dir_guard.path().join("Photos.sqlite-shm");
    let gallery_db_wal_path: PathBuf = temp_dir_guard.path().join("Photos.sqlite-wal");

    export_afc_file(afc, PHOTOS_SQLITE_REMOTE_PATH, &gallery_db_path)
        .await
        // FIXME: surface this to QML with a better recovery message once we know
        // how missing or inaccessible Photos.sqlite should be presented.
        .context("Failed to export required Photos.sqlite from device")?;

    if let Err(e) = export_afc_file(afc, PHOTOS_SQLITE_SHM_REMOTE_PATH, &gallery_db_shm_path).await
    {
        println!("Skipping optional Photos.sqlite-shm export: {}", e);
    }

    if let Err(e) = export_afc_file(afc, PHOTOS_SQLITE_WAL_REMOTE_PATH, &gallery_db_wal_path).await
    {
        println!("Skipping optional Photos.sqlite-wal export: {}", e);
    }

    let conn: Connection = Connection::open(gallery_db_path)?;

    /*
        we need to get the dynamic asset table name from the table
        iOS seems to be bumping the version with every major iOS update
    */
    let mut assets_table_name: Option<String> = None;
    let mut assets_table_album_column: Option<String> = None;
    {
        let mut stm = conn.prepare("SELECT name FROM sqlite_master WHERE type='table'")?;
        let table_iter = stm.query_map([], |r| r.get::<_, String>(0))?;

        let re = regex::Regex::new(r"^Z_\d+ASSETS$")?;

        for table in table_iter {
            let table_name = table?;

            if re.is_match(&table_name) {
                println!("Found assets table: {}", table_name);
                //extract the prefix from for example Z_27ASSETS
                assets_table_album_column = match table_name.strip_suffix("ASSETS") {
                    // Z_27ALBUMS
                    Some(pre) => Some(String::from(format!("{}ALBUMS", pre))),
                    None => None,
                };
                println!(
                    "Found assets_table_album_column: {}",
                    assets_table_album_column.clone().unwrap()
                );

                assets_table_name = Some(table_name);
                break;
            }
        }
    };

    let assets_table_name =
        assets_table_name.ok_or_else(|| anyhow!("Couldn't find the assets table"))?;
    let assets_table_album_column = assets_table_album_column
        .ok_or_else(|| anyhow!("Couldn't find assets_table_album_column"))?;

    let temp_dir = temp_dir_guard.keep();
    Ok(Arc::new(SqliteGalleryProvider {
        connection: Some(Arc::new(Mutex::new(conn))),
        temp_dir,
        ios_version,
        assets_table_name,
        assets_table_album_column,
        name : SQLITE_GALLERY_PROVIDER_NAME.into()
    }))
}

async fn read_fs_albums(afc: Arc<Mutex<AfcClient>>) -> anyhow::Result<Vec<GalleryAlbum>> {
    let mut afc = afc.lock().await;

    let mut folder_names = afc
        .list_dir(DCIM_REMOTE_PATH)
        .await
        .context("Failed to list /DCIM")?;

    folder_names.retain(|name| name != "." && name != ".." && is_apple_dcim_folder(name));
    folder_names.sort();

    let mut albums = Vec::new();
    for folder_name in folder_names {
        let folder_path = format!("{}/{}", DCIM_REMOTE_PATH, folder_name);
        let info = match afc.get_file_info(&folder_path).await {
            Ok(info) => info,
            Err(e) => {
                println!("Skipping DCIM folder {}: {}", folder_path, e);
                continue;
            }
        };

        if info.st_ifmt != "S_IFDIR" {
            continue;
        }

        let mut file_names = match afc.list_dir(&folder_path).await {
            Ok(names) => names,
            Err(e) => {
                println!("Skipping unreadable DCIM folder {}: {}", folder_path, e);
                continue;
            }
        };

        file_names.retain(|name| name != "." && name != ".." && is_previewable_media_file(name));
        // file_names.sort();

        let mut paths = Vec::new();
        for file_name in &file_names {
            let file_path = format!("{}/{}", folder_path, file_name);
            paths.push(file_path);
            break;
            // match afc.get_file_info(&file_path).await {
            //     Ok(info) if info.st_ifmt != "S_IFDIR" => paths.push(file_path),
            //     Ok(_) => {}
            //     Err(e) => {
            //         println!("Skipping DCIM file {}: {}", file_path, e);
            //     }
            // }
        }

        if paths.is_empty() {
            continue;
        }

        let Some(album_id) = apple_dcim_folder_id(&folder_name) else {
            continue;
        };
        albums.push(GalleryAlbum {
            id: album_id,
            name: folder_name,
            item_count: file_names.len() as i32,
            preview_path: paths[0].clone(),
        });
    }

    Ok(albums)
}

async fn build_fs_provider(afc: Arc<Mutex<AfcClient>>) -> anyhow::Result<Arc<dyn GalleryProvider>> {
    Ok(Arc::new(FsGalleryProvider { afc, name: FS_GALLERY_PROVIDER_NAME.into() }))
}

async fn query_sqlite_album(
    con_arc: Arc<Mutex<Connection>>,
    table_name: String,
    album_column: String,
    id: i32,
    media_filter: GalleryMediaFilter,
    most_recent_first: bool,
) -> anyhow::Result<Vec<String>> {
    let con = con_arc.lock().await;
    let mut paths = Vec::new();
    let query = format!(
        "{} ORDER BY ZASSET.Z_PK {}",
        ALBUM_CONTENTS_QUERY_TEMPLATE
            .replace("{table}", &table_name)
            .replace("{album}", &album_column),
        sqlite_order_direction(most_recent_first),
    );
    let mut stmt = con.prepare(&query)?;

    let row_iter = stmt.query_map([id], |r| {
        let fdir: String = r.get(0)?;
        let fname: String = r.get(1)?;
        Ok((fdir, fname))
    })?;

    for item in row_iter {
        let (fdir, fname) = item?;
        let path = join_device_path(&fdir, &fname);
        if matches_media_filter(&path, media_filter) {
            paths.push(path);
        }
    }

    Ok(paths)
}

fn sqlite_order_direction(most_recent_first: bool) -> &'static str {
    if most_recent_first { "DESC" } else { "ASC" }
}

fn sqlite_ordered_query(query: &str, most_recent_first: bool) -> String {
    query.replace(
        "ORDER BY ZASSET.Z_PK DESC",
        &format!(
            "ORDER BY ZASSET.Z_PK {}",
            sqlite_order_direction(most_recent_first)
        ),
    )
}

async fn query_favs(
    con_arc: Arc<Mutex<Connection>>,
    media_filter: GalleryMediaFilter,
    most_recent_first: bool,
) -> anyhow::Result<Vec<String>> {
    let con = con_arc.lock().await;
    let mut paths = Vec::new();

    //favs album
    let query = sqlite_ordered_query(FAVS_QUERY, most_recent_first);
    let mut favs_stmt = con.prepare(&query)?;

    let favs_iter = favs_stmt.query_map([], |r| {
        let fname: String = r.get(0)?;
        let fdir: String = r.get(1)?;
        Ok((fname, fdir))
    })?;

    for fav_item in favs_iter {
        let (fname, fdir) = fav_item?;
        let path = join_device_path(&fdir, &fname);
        if matches_media_filter(&path, media_filter) {
            paths.push(path);
        }
    }

    Ok(paths)
}

async fn query_recents(
    con_arc: Arc<Mutex<Connection>>,
    media_filter: GalleryMediaFilter,
    most_recent_first: bool,
) -> anyhow::Result<Vec<String>> {
    let con = con_arc.lock().await;
    let mut paths = Vec::new();

    //recents album
    let query = sqlite_ordered_query(RECENTS_QUERY, most_recent_first);
    let mut recents_stmt = con.prepare(&query)?;

    let recents_iter = recents_stmt.query_map([], |r| {
        let fname: String = r.get(0)?;
        let fdir: String = r.get(1)?;
        Ok((fname, fdir))
    })?;

    for recent_item in recents_iter {
        let (fname, fdir) = recent_item?;
        let path = join_device_path(&fdir, &fname);
        if matches_media_filter(&path, media_filter) {
            paths.push(path);
        }
    }

    Ok(paths)
}

#[derive(QObject, Default, QtThreading)]
#[allow(non_snake_case)]
pub struct Query {
    base: qt_base_class!(trait QObject),
    udid: String,
    ios_version: u32,
    albums: qt_property!(QVariantList; NOTIFY albumsChanged),
    albumsChanged: qt_signal!(),
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

fn new_state(init:bool, err :&str, backend: &str) -> QVariantMap {
    let mut state = QVariantMap::default();
    qvariantmap_insert!(state,"init", init);
    qvariantmap_insert!(state,"err", QString::from(err));
    qvariantmap_insert!(state,"backend", QString::from(backend));

    state
}

impl Query {
    pub fn with_device_attr(udid: QString, ios_version: u32) -> Self {
        let state = new_state(false,"","");

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
                        let state = new_state(true,"", &provider.name());
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
                        let fs_res :anyhow::Result<Arc<dyn GalleryProvider>> = async {
                            let afc_arc = device_ctx::get_device(udid_clone_for_fallback).await?.afc;
                            let prov = build_fs_provider(afc_arc).await?;
                            prov.read_albums().await?;
                            Ok(prov)
                        }.await;
                        
                        match fs_res {
                            Ok(fs) => {
                                qt_thread.queue(move |s| {
                                    println!("Fallback fs provider initialized successfully");
                                    let state = new_state(true,"", &fs.name());
                                    s.provider = Some(fs);
                                    s.state = state;
                                    s.stateChanged();
                                });
                            }
                            Err(e) => {
                                debug!("Failed to fallback to fs backend for gallery: {}",e.to_string());
                                qt_thread.queue(move |s| {
                                    let state = new_state(false,&e.to_string(), FS_GALLERY_PROVIDER_NAME);
                                    s.state = state;
                                    s.stateChanged();

                                });
                            }
                        };
                    } else {
                        qt_thread.queue(move |s| {
                            let state = new_state(false,&e.to_string(), FS_GALLERY_PROVIDER_NAME);
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
                Ok(provider_albums) => {
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
                    })
                }
                Err(e) => {
                    q_thread.queue(move |q_self| {
                        println!("Error reading albums {}", e);
                        q_self.state[QString::from("err")] =
                            QVariant::from(QString::from(e.to_string()));
                        q_self.albums = albums;
                        q_self.albumsChanged();
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
