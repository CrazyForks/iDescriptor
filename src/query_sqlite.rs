use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantList, QVariantMap};

use crate::RUNTIME;
use crate::constants::{
    ALBUM_CONTENTS_QUERY_TEMPLATE, FAVS_ALBUM_ID, FAVS_ALBUM_QUERY, FAVS_QUERY,
    IOS_15_ALBUM_QUERY_STATEMENT, IOS_26_ALBUM_QUERY_STATEMENT, RECENTS_ALBUM_ID,
    RECENTS_ALBUM_QUERY, RECENTS_QUERY,
};
use crate::device_ctx;
use crate::qt_threading::QtThreading;
use crate::utils::create_album_info;
use idevice::afc::AfcClient;
use idevice::afc::opcode::AfcFopenMode;
use macros::QtThreading;
use rusqlite::{Connection, OptionalExtension};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;
use ::log::debug;

const PHOTOS_SQLITE_REMOTE_PATH: &str = "/PhotoData/Photos.sqlite";
const PHOTOS_SQLITE_SHM_REMOTE_PATH: &str = "/PhotoData/Photos.sqlite-shm";
const PHOTOS_SQLITE_WAL_REMOTE_PATH: &str = "/PhotoData/Photos.sqlite-wal";

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
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut remote_file = afc.open(remote_path, AfcFopenMode::RdOnly).await?;
    let mut local_file = tokio::fs::File::create(local_path).await?;
    let mut chunk = vec![0u8; 64 * 1024];

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

#[derive(QObject, Default, QtThreading)]
pub struct Query {
    base: qt_base_class!(trait QObject),
    udid: String,
    ios_version: u32,
    albums: qt_property!(QVariantList; NOTIFY albums_changed),
    albums_changed: qt_signal!(),
    connection: Option<Arc<Mutex<Connection>>>,
    temp_dir: Option<PathBuf>,
    assets_table_name: Option<String>,
    assets_table_album_column: Option<String>,
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),

    init: qt_method!(fn(&mut self)),
    read_albums: qt_method!(fn(&mut self)),
    query_album: qt_method!(fn(&mut self, id: i32)),
    album_queried: qt_signal!(id: i32, items: QStringList),
    is_init: bool
}

impl Query {
    pub fn with_device_attr(udid: QString, ios_version: u32) -> Self {
        let mut state = QVariantMap::default();
        state.insert(QString::from("init"), QVariant::from(false));
        state.insert(QString::from("err"), QVariant::from(QString::default()));

        let mut def = Self::default();
        def.state = state;
        def.ios_version = ios_version;
        def.udid = udid.to_string();
        def
    }

    fn init(&mut self) {
        if (self.is_init) {
            debug!("Query: already initialized, skipping init");
            return;
        }
        self.is_init = true;
        let udid_clone = self.udid.clone();
        let qt_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let res: anyhow::Result<()> = (async {
                let temp_dir = std::env::temp_dir()
                    .join(format!("idescriptor-photos-db-{}", uuid::Uuid::new_v4()));
                tokio::fs::create_dir_all(&temp_dir).await?;
                // this is so that if we fail to export the db, we don't leave a temp dir behind
                let temp_dir_guard = TempDirGuard::new(temp_dir);

                let gallery_db_path: PathBuf = temp_dir_guard.path().join("Photos.sqlite");
                let gallery_db_shm_path: PathBuf = temp_dir_guard.path().join("Photos.sqlite-shm");
                let gallery_db_wal_path: PathBuf = temp_dir_guard.path().join("Photos.sqlite-wal");

                {
                    let afc_arc = device_ctx::get_device(udid_clone).await?.afc;
                    let mut afc = afc_arc.lock().await;

                    if let Err(e) =
                        export_afc_file(&mut afc, PHOTOS_SQLITE_REMOTE_PATH, &gallery_db_path).await
                    {
                        // FIXME: surface this to QML instead of panicking once we know how
                        // to recover from a missing or inaccessible Photos.sqlite.
                        panic!("Failed to export required Photos.sqlite from device: {}", e);
                    }

                    if let Err(e) = export_afc_file(
                        &mut afc,
                        PHOTOS_SQLITE_SHM_REMOTE_PATH,
                        &gallery_db_shm_path,
                    )
                    .await
                    {
                        println!("Skipping optional Photos.sqlite-shm export: {}", e);
                    }

                    if let Err(e) = export_afc_file(
                        &mut afc,
                        PHOTOS_SQLITE_WAL_REMOTE_PATH,
                        &gallery_db_wal_path,
                    )
                    .await
                    {
                        println!("Skipping optional Photos.sqlite-wal export: {}", e);
                    }
                }

                let conn: Connection = Connection::open(gallery_db_path)?;

                /*
                    we need to get the dynamic asset table name from the table
                    iOS seems to be bumping the version with every major iOS update
                */
                let mut assets_table_name: Option<String> = None;
                let mut assets_table_album_column: Option<String> = None;
                {
                    let mut stm =
                        conn.prepare("SELECT name FROM sqlite_master WHERE type='table'")?;
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

                if assets_table_name.is_none() {
                    anyhow::bail!("Couldn't find the assets table");
                }

                if assets_table_album_column.is_none() {
                    anyhow::bail!("Couldn't find assets_table_album_column");
                }

                let temp_dir = temp_dir_guard.keep();
                qt_thread.queue(|s| {
                    s.connection = Some(Arc::new(Mutex::new(conn)));
                    s.temp_dir = Some(temp_dir);
                    s.assets_table_name = assets_table_name;
                    s.assets_table_album_column = assets_table_album_column;
                });

                Ok(())
            })
            .await;
            match res {
                Ok(_) => {
                    qt_thread.queue(move |s| {
                        s.state[QString::from("err")] = QVariant::from(QString::default());
                        s.state[QString::from("init")] = QVariant::from(true);
                        // FIXME:
                        // q_self.albums = albums;

                        s.state_changed();
                    });
                }
                Err(e) => {
                    // eprintln!("Failed to read sqlite db");
                    qt_thread.queue(move |s| {
                        s.state[QString::from("err")] =
                            QVariant::from(QString::from(e.to_string()));
                        s.state[QString::from("init")] = QVariant::from(false);
                        // FIXME:
                        // q_self.albums = albums;

                        s.state_changed();
                    });
                }
            };
        });
    }

    fn read_albums(&mut self) {
        let q_thread = self.qt_thread();
        let con_arc = match &self.connection {
            Some(c) => c.clone(),
            None => {
                println!("NO CONN");
                return;
            }
        };

        let ios_ver = self.ios_version;
        RUNTIME.spawn(async move {
            println!("Runtime spawn for read_albums");
            let mut albums = QVariantList::default();
            let res: Result<(), Box<dyn std::error::Error + Send + Sync>> = (async {
                let conn = con_arc.lock().await;
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

                let recents_album_data = create_album_info("Recents",RECENTS_ALBUM_ID, count, fdir, fname);

                albums.push(
                    QVariant::from(&QString::from(recents_album_data)),
                );

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

                let favs_album_data = create_album_info("Favorites", FAVS_ALBUM_ID, count, fdir, fname);

                albums.push(
                    QVariant::from(&QString::from(favs_album_data)),
                );

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

                    let album_data =
                        create_album_info(title.as_str(), album_id, item_count, asset_dir, asset_file_name);

                    albums.push(
                        QVariant::from(&QString::from(album_data)),
                    );
                }

                Ok(())
            })
            .await;

            if let Err(e) = res {
                q_thread.queue(move |q_self| {
                    println!("Error reading albums {}", e.to_string());
                    q_self.state[QString::from("err")] =
                        QVariant::from(QString::from(e.to_string()));
                    q_self.albums = albums;
                    q_self.albums_changed();
                    // q_self.state_changed()
                });
            } else {
                q_thread.queue(move |q_self| {
                    println!("Albums read fine firing events");
                    q_self.state[QString::from("err")] = QVariant::from(QString::default());
                    q_self.albums = albums;

                    q_self.albums_changed();
                    // q_self.state_changed()
                })
            }
        });
    }

    fn query_album(&mut self, id: i32) {
        let con_arc = match &self.connection {
            Some(c) => c.clone(),
            None => return,
        };

        match id {
            FAVS_ALBUM_ID => {
                return self.query_favs();
            }
            RECENTS_ALBUM_ID => {
                return self.query_recents();
            }
            /* continue if something else */
            _ => {}
        };

        let q_thread = self.qt_thread();
        let table_name = self.assets_table_name.clone().unwrap();
        let album_column = self.assets_table_album_column.clone().unwrap();
        RUNTIME.spawn(async move {
            let res: Result<QStringList, Box<dyn std::error::Error + Send + Sync>> = (async {
                let con = con_arc.lock().await;
                let mut list: QStringList = QStringList::default();
                let mut stmt = con.prepare(
                    &ALBUM_CONTENTS_QUERY_TEMPLATE
                        .replace("{table}", &table_name)
                        .replace("{album}", &album_column),
                )?;

                let row_iter = stmt.query_map([id], |r| {
                    let fdir: String = r.get(0)?;
                    let fname: String = r.get(1)?;
                    Ok((fdir, fname))
                })?;

                for item in row_iter {
                    let (fdir, fname) = item?;
                    let full_path = format!("{}/{}", fdir, fname);
                    list.push(QString::from(full_path));
                }
                Ok(list)
            })
            .await;

            match res {
                Ok(list) => {
                    println!("Album loaded has length :{}", list.len());
                    q_thread.queue(move |q| {
                        q.album_queried(id, list);
                    });
                }
                Err(e) => {
                    println!("Error querying album {}", e.to_string())
                }
            }
        });
    }

    fn query_favs(&mut self) {
        let q_thread = self.qt_thread();
        let con_arc = match &self.connection {
            Some(c) => c.clone(),
            None => {
                println!("NO CONN");
                return;
            }
        };

        RUNTIME.spawn(async move {
            let res: anyhow::Result<QStringList> = async {
                let con = con_arc.lock().await;
                let mut list: QStringList = QStringList::default();

                //favs album
                let mut favs_stmt = con.prepare(FAVS_QUERY)?;

                let favs_iter = favs_stmt.query_map([], |r| {
                    let fname: String = r.get(0)?;
                    let fdir: String = r.get(1)?;
                    Ok((fname, fdir))
                })?;

                for fav_item in favs_iter {
                    let (fname, fdir) = fav_item?;
                    list.push(QString::from(format!("{}/{}", fdir, fname)));
                }

                Ok(list)
            }
            .await;

            match res {
                Ok(list) => {
                    println!("Album loaded has length :{}", list.len());
                    q_thread.queue(move |q| {
                        q.album_queried(FAVS_ALBUM_ID, list);
                    });
                }
                Err(e) => {
                    println!("Error querying album {}", e.to_string())
                }
            }
        });
    }

    fn query_recents(&mut self) {
        let q_thread = self.qt_thread();
        let con_arc = match &self.connection {
            Some(c) => c.clone(),
            None => {
                println!("NO CONN");
                return;
            }
        };

        RUNTIME.spawn(async move {
            let res: anyhow::Result<QStringList> = async {
                let con = con_arc.lock().await;
                let mut list: QStringList = QStringList::default();

                //recents album
                let mut recents_stmt = con.prepare(RECENTS_QUERY)?;

                let recents_iter = recents_stmt.query_map([], |r| {
                    let fname: String = r.get(0)?;
                    let fdir: String = r.get(1)?;
                    Ok((fname, fdir))
                })?;

                for recent_item in recents_iter {
                    let (fname, fdir) = recent_item?;
                    list.push(QString::from(format!("{}/{}", fdir, fname)));
                }

                Ok(list)
            }
            .await;

            match res {
                Ok(list) => {
                    println!("Album loaded has length :{}", list.len());
                    q_thread.queue(move |q| {
                        q.album_queried(RECENTS_ALBUM_ID, list);
                    });
                }
                Err(e) => {
                    println!("Error querying album {}", e.to_string())
                }
            }
        });
    }
}

impl Drop for Query {
    fn drop(&mut self) {
        self.connection = None;

        if let Some(temp_dir) = self.temp_dir.take() {
            if let Err(e) = std::fs::remove_dir_all(&temp_dir) {
                println!("Failed to remove temp gallery database dir: {}", e);
            }
        }
    }
}
