use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantMap};

use crate::constants::{
    ALBUM_CONTENTS_QUERY_TEMPLATE, FAVS_ALBUM_ID, FAVS_ALBUM_QUERY, FAVS_QUERY,
    IOS_15_ALBUM_QUERY_STATEMENT, IOS_26_ALBUM_QUERY_STATEMENT, RECENTS_ALBUM_ID,
    RECENTS_ALBUM_QUERY, RECENTS_QUERY,
};
use crate::device_ctx;
use crate::qt_threading::{QtThread, QtThreading};
use crate::utils::create_album_info;
use crate::{RUNTIME, run_sync};
use idevice::afc::{AfcClient, opcode::AfcFopenMode};
use rusqlite::{Connection, OptionalExtension, Rows};
use serde_json::json;
use std::default;
use std::fmt::format;
use std::path::PathBuf;
use std::sync::Arc;
use std::{io::SeekFrom, pin::Pin};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio::net::TcpListener;
use tokio::sync::Mutex;

use tokio::sync::oneshot;

#[derive(QObject, Default)]
pub struct Query {
    base: qt_base_class!(trait QObject),
    udid: String,
    ios_version: u32,
    albums: qt_property!(QVariantMap; NOTIFY albums_changed),
    albums_changed: qt_signal!(),
    connection: Option<Arc<Mutex<Connection>>>,
    assets_table_name: Option<String>,
    assets_table_album_column: Option<String>,
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),

    init: qt_method!(fn(&mut self)),
    read_albums: qt_method!(fn(&mut self)),
    query_album: qt_method!(fn(&mut self, id: i32)),
    album_queried: qt_signal!(id: i32, items: QStringList),
}

impl QtThreading for Query {
    fn qt_thread(&self) -> crate::qt_threading::QtThread<Self>
    where
        Self: Sized,
    {
        QtThread::new(self)
    }
}

impl Query {
    pub fn with_device_attr(udid: QString, ios_version: u32) -> Self {
        let mut state = QVariantMap::default();
        state.insert(QString::from("init"), QVariant::from(false));
        state.insert(QString::from("err"), QVariant::from(QString::default()));
        Self {
            state,
            ios_version,
            udid: udid.to_string(),
            ..Default::default()
        }
    }

    fn init(&mut self) {
        let udid_clone = self.udid.clone();
        let qt_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let res: Result<(), Box<dyn std::error::Error + Send + Sync>> = (async {
                let mut gallery_db_bytes = {
                    let afc_arc = device_ctx::get_device(udid_clone).await?.afc;
                    let mut afc = afc_arc.lock().await;
                    let mut fd = afc
                        .open("/PhotoData/Photos.sqlite", AfcFopenMode::RdOnly)
                        .await?;
                    fd.read_entire().await?
                };

                let conn: Connection = Connection::open_in_memory()?;

                // HACK: WAL -> legacy mode patch
                if gallery_db_bytes.len() > 20 && gallery_db_bytes[18] == 0x02 {
                    gallery_db_bytes[18] = 0x01;
                    gallery_db_bytes[19] = 0x01;
                }

                unsafe {
                    let db_ptr = rusqlite::ffi::sqlite3_deserialize(
                        conn.handle(),
                        b"main\0".as_ptr() as *const std::os::raw::c_char,
                        gallery_db_bytes.as_mut_ptr(),
                        gallery_db_bytes.len() as i64,
                        gallery_db_bytes.len() as i64,
                        rusqlite::ffi::SQLITE_DESERIALIZE_READONLY as u32,
                    );
                    if db_ptr != rusqlite::ffi::SQLITE_OK {
                        return Err("Failed to deserialize SQLite database".into());
                    }
                };

                //FIXME:need to drop the vec somewhere safe
                /*
                    std::mem::forget is needed because vec is dropped but
                    sqlite still needs it, we need to manually drop the vec
                */
                std::mem::forget(gallery_db_bytes);

                /*
                    we need to get the dynamic asset table name from the table
                    iOS seems to be bumping the version with every major iOS update
                    but not sure why
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
                    return Err("Couldn't find the assets table".into());
                }

                if assets_table_album_column.is_none() {
                    return Err("Couldn't find assets_table_album_column".into());
                }

                qt_thread.queue(|s| {
                    s.connection = Some(Arc::new(Mutex::new(conn)));
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
            let mut albums = QVariantMap::default();
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

                let recents_album_data = create_album_info(RECENTS_ALBUM_ID, count, fdir, fname);

                albums.insert(
                    QString::from("Recents"),
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

                let favs_album_data = create_album_info(FAVS_ALBUM_ID, count, fdir, fname);

                albums.insert(
                    QString::from("Favorites"),
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
                        create_album_info(album_id, item_count, asset_dir, asset_file_name);

                    albums.insert(
                        QString::from(title),
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
