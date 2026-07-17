pub use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantList, QVariantMap};

use crate::constants::{
    ALBUM_CONTENTS_QUERY_TEMPLATE, FAVS_ALBUM_ID, FAVS_ALBUM_QUERY, FAVS_QUERY,
    FS_GALLERY_PROVIDER_NAME, IOS_15_ALBUM_QUERY_STATEMENT, IOS_26_ALBUM_QUERY_STATEMENT,
    PHOTOS_SQLITE_REMOTE_PATH, PHOTOS_SQLITE_SHM_REMOTE_PATH, PHOTOS_SQLITE_WAL_REMOTE_PATH,
    RECENTS_ALBUM_ID, RECENTS_ALBUM_QUERY, RECENTS_QUERY, SQLITE_GALLERY_PROVIDER_NAME,
};
use crate::device_ctx;
use crate::gallery::{
    GalleryAlbum, GalleryFuture, GalleryMediaFilter, GalleryProvider, export_afc_file,
    matches_media_filter,
};
use crate::qt_threading::QtThreading;
use crate::utils::{MediaFileType, TempDirGuard, create_album_info, media_file_type};
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

pub struct SqliteGalleryProvider {
    connection: Option<Arc<Mutex<Connection>>>,
    temp_dir: PathBuf,
    ios_version: u32,
    assets_table_name: String,
    assets_table_album_column: String,
    name: String,
}

impl GalleryProvider for SqliteGalleryProvider {
    fn name(&self) -> String {
        self.name.clone()
    }

    fn read_albums(&self) -> GalleryFuture<(Vec<GalleryAlbum>, i32)> {
        let con_arc = self
            .connection
            .as_ref()
            .expect("sqlite gallery connection is set")
            .clone();
        let ios_ver = self.ios_version;

        Box::pin(async move {
            println!("Reading via Sqlite provider for ios {ios_ver}");
            let conn = con_arc.lock().await;
            let mut albums = Vec::new();
            let mut failed_albums_count: i32 = 0;

            // FIXME: can this be better handled ?
            let placeholder_or_empty = (String::default(), String::default(), 0);

            //recents
            let (fname, fdir, count) =
                explore_recents_album(&conn).unwrap_or(placeholder_or_empty.clone());

            albums.push(GalleryAlbum {
                id: RECENTS_ALBUM_ID,
                name: String::from("Recents"),
                item_count: count,
                preview_path: join_device_path(&fdir, &fname),
            });

            //favs
            let (fname, fdir, count) =
                explore_favs_album(&conn).unwrap_or(placeholder_or_empty.clone());
            albums.push(GalleryAlbum {
                id: FAVS_ALBUM_ID,
                name: String::from("Favorites"),
                item_count: count,
                preview_path: join_device_path(&fdir, &fname),
            });

            match explore_other_albums(&conn, ios_ver) {
                Ok((other_albums, other_failed_albums_count)) => {
                    albums.extend(other_albums);
                    failed_albums_count += other_failed_albums_count;
                }
                Err(err) => {
                    failed_albums_count += 1;
                    debug!("Failed to explore other albums: {err}");
                }
            }
            debug!("Failed to read {failed_albums_count} albums");

            Ok((albums, failed_albums_count))
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
                FAVS_ALBUM_ID => query_favs_album(con_arc, media_filter, most_recent_first).await,
                RECENTS_ALBUM_ID => {
                    query_recents_album(con_arc, media_filter, most_recent_first).await
                }
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

pub async fn build_sqlite_provider(
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
        name: SQLITE_GALLERY_PROVIDER_NAME.into(),
    }))
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

async fn query_favs_album(
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

async fn query_recents_album(
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

fn join_device_path(dir: &str, file_name: &str) -> String {
    format!("{}/{}", dir.trim_end_matches('/'), file_name)
}

//used in init
fn explore_recents_album(conn: &Connection) -> anyhow::Result<(String, String, i32)> {
    let mut recents_stmt = conn.prepare(RECENTS_ALBUM_QUERY)?;

    let recents_row = recents_stmt.query_row([], |r| {
        let fname: String = r.get(0)?;
        let fdir: String = r.get(1)?;
        let count: i32 = r.get(2)?;
        Ok((fname, fdir, count))
    })?;

    Ok(recents_row)
}

fn explore_favs_album(conn: &Connection) -> anyhow::Result<(String, String, i32)> {
    let mut favs_stmt = conn.prepare(FAVS_ALBUM_QUERY)?;

    let favs_row = favs_stmt.query_row([], |r| {
        let fname: String = r.get(0)?;
        let fdir: String = r.get(1)?;
        let count: i32 = r.get(2)?;
        Ok((fname, fdir, count))
    })?;

    Ok(favs_row)
}

fn explore_other_albums(
    conn: &Connection,
    ios_ver: u32,
) -> anyhow::Result<(Vec<GalleryAlbum>, i32)> {
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

    let mut albums = Vec::new();
    let mut failed_albums_count = 0;
    for row_res in rows_iter {
        match row_res {
            Ok((album_id, title, item_count, asset_dir, asset_file_name)) => {
                albums.push(GalleryAlbum {
                    id: album_id,
                    name: title,
                    item_count,
                    preview_path: join_device_path(&asset_dir, &asset_file_name),
                });
            }
            Err(_) => failed_albums_count += 1,
        }
    }

    Ok((albums, failed_albums_count))
}
