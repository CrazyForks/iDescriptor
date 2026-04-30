use cxx_qt::{Constructor, CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QList, QMap, QMapPair_QString_QVariant, QString, QVariant};

use crate::POSSIBLE_ROOT;
use crate::{APP_DEVICE_STATE, RUNTIME, afc, run_sync};
use cxx_qt_lib::{QHash, QHashPair_QString_QVariant};
use idevice::afc::{AfcClient, opcode::AfcFopenMode};
use idevice::{
    IdeviceError, IdeviceService, diagnostics_relay::DiagnosticsRelayClient,
    house_arrest::HouseArrestClient, installation_proxy::InstallationProxyClient,
    provider::IdeviceProvider,
};
use once_cell::sync::Lazy;
use plist::Dictionary as PlistDictionary;
use plist_macro::plist;
use regex::Regex;
use rusqlite::{Connection, Rows};
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

#[cxx_qt::bridge]
mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        include!("cxx-qt-lib/qlist.h");
        include!("cxx-qt-lib/qbytearray.h");
        include!("cxx-qt-lib/qmap.h");
        include!("cxx-qt-lib/qvariant.h");

        type QString = cxx_qt_lib::QString;
        type QList_QString = cxx_qt_lib::QList<QString>;
        type QByteArray = cxx_qt_lib::QByteArray;
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QMap_QString_QVariant, albums)]
        #[qproperty(QString, error)]
        #[qproperty(bool, is_init)]
        #[qproperty(bool, is_err)]
        type Query = super::RQuery;

        #[qinvokable]
        fn init(self: Pin<&mut Self>, udid: &QString);

        #[qinvokable]
        fn read_albums(self: Pin<&mut Self>);

        #[qinvokable]
        fn query_album(self: Pin<&mut Self>, id: i32);

        #[qsignal]
        fn album_queried(self: Pin<&mut Self>, id: i32, items: QList_QString);

    }
    impl cxx_qt::Threading for Query {}
}

#[derive(Default)]
pub struct RQuery {
    udid: QString,
    albums: QMap<QMapPair_QString_QVariant>,
    error: QString,
    connection: Option<Arc<Mutex<Connection>>>,
    is_init: bool,
    is_err: bool,
}

impl qobject::Query {
    fn init(mut self: Pin<&mut Self>, udid: &QString) {
        let udid_clone = udid.clone();
        let qt_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let res: Result<(), Box<dyn std::error::Error + Send + Sync>> = (async {
                let mut gallery_db_bytes = {
                    let afc_arc = {
                        let device = APP_DEVICE_STATE
                            .lock()
                            .await
                            .get(&udid_clone.to_string())
                            .cloned();
                        match device {
                            Some(d) => d.afc.clone(),
                            None => return Err("Device not found".into()),
                        }
                    };

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

                //FIXME:need to drop vec somewhere safe
                /*
                    std::mem::forget is needed because vec is dropped but
                    sqlite still needs, we need to manually drop the vec
                */
                std::mem::forget(gallery_db_bytes);

                qt_thread
                    .queue(|mut s| {
                        s.as_mut().rust_mut().connection = Some(Arc::new(Mutex::new(conn)));
                    })
                    .ok();

                Ok(())
            })
            .await;
            match res {
                Ok(_) => {
                    qt_thread.queue(move |s| s.set_is_init(true)).ok();
                    qt_thread.queue(move |s| s.set_is_err(false)).ok();
                }
                Err(e) => {
                    // eprintln!("Failed to read sqlite db");
                    qt_thread.queue(move |s| s.set_is_init(false)).ok();
                    qt_thread.queue(move |s| s.set_is_err(true)).ok();
                }
            };
        });
    }

    fn read_albums(mut self: Pin<&mut Self>) {
        let q_thread = self.qt_thread();
        let con_arc = match &self.connection {
            Some(c) => c.clone(),
            None => {
                println!("WTF NO CONN");
                return;
            }
        };

        RUNTIME.spawn(async move {
            let mut albums = QMap::<QMapPair_QString_QVariant>::default();
            let res: Result<(), Box<dyn std::error::Error + Send + Sync>> = (async {
                //recents album

                let conn = con_arc.lock().await;
                let mut recents_stmt = conn.prepare(
                    "
                        SELECT 
                        ZASSET.ZFILENAME as 'FNAME',
                        ZASSET.ZDIRECTORY as 'DIR',
                        (SELECT COUNT(*) FROM ZASSET) as 'COUNT'
                        FROM ZASSET
                        ORDER BY ZASSET.Z_PK DESC
                        LIMIT 1
                ",
                )?;

                let (fname, fdir, count) = recents_stmt.query_row([], |r| {
                    let fname: String = r.get(0)?;
                    let fdir: String = r.get(1)?;
                    let count: i32 = r.get(2)?;
                    Ok((fname, fdir, count))
                })?;

                let recents_album_data =
                    json!({ "item_count" : count, "file_path" : format!("{}/{}",fdir,fname)})
                        .to_string();

                albums.insert(
                    QString::from("Recents"),
                    QVariant::from(&QString::from(recents_album_data)),
                );

                //favs
                let mut favs_stmt = conn.prepare(
                    "
                    SELECT 
                        ZASSET.ZFILENAME,
                        ZASSET.ZDIRECTORY,  
                        (SELECT COUNT(*) FROM ZASSET WHERE ZASSET.ZFAVORITE = 1)  
                    FROM ZASSET
                    WHERE ZASSET.ZFAVORITE = 1
                    ORDER BY ZASSET.Z_PK DESC
                    LIMIT 1
                ",
                )?;

                let (fname, fdir, count) = favs_stmt.query_row([], |r| {
                    let fname: String = r.get(0)?;
                    let fdir: String = r.get(1)?;
                    let count: i32 = r.get(2)?;
                    Ok((fname, fdir, count))
                })?;

                let favs_album_data =
                    json!({"item_count" : count, "file_path" : format!("{}/{}",fdir,fname) })
                        .to_string();

                albums.insert(
                    QString::from("Favorites"),
                    QVariant::from(&QString::from(favs_album_data)),
                );

                // IOS 26
                // let mut stmt = conn.prepare(
                //     "SELECT
                //             ZGENERICALBUM.Z_PK,
                //             ZGENERICALBUM.ZTITLE,
                //             ZGENERICALBUM.ZCACHEDCOUNT,
                //             ZASSET.ZDIRECTORY,
                //             ZASSET.ZFILENAME
                //         FROM ZGENERICALBUM
                //         LEFT JOIN ZASSET ON ZGENERICALBUM.Z_ENT = ZASSET.Z_PK
                //         WHERE ZGENERICALBUM.Z_ENT IS NOT NULL
                //         AND ZGENERICALBUM.ZTITLE IS NOT NULL
                //         AND ZGENERICALBUM.ZCACHEDCOUNT IS NOT 0
                //     ",
                // )?;

                let mut stmt = conn.prepare(
                    "SELECT   
                            ZGENERICALBUM.Z_PK,
                            ZGENERICALBUM.ZTITLE,  
                            ZGENERICALBUM.ZCACHEDCOUNT,  
                            ZASSET.ZDIRECTORY,  
                            ZASSET.ZFILENAME  
                        FROM ZGENERICALBUM
                        LEFT JOIN ZASSET ON ZGENERICALBUM.ZKEYASSET = ZASSET.Z_PK  
                        WHERE ZGENERICALBUM.ZKEYASSET IS NOT NULL
                    ",
                )?;

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

                    let album_data = crate::utils::create_album_info(
                        album_id,
                        item_count,
                        asset_dir,
                        asset_file_name,
                    );

                    albums.insert(
                        QString::from(title),
                        QVariant::from(&QString::from(album_data)),
                    );
                }

                Ok(())
            })
            .await;

            if let Err(e) = res {
                q_thread
                    .queue(move |q_self| {
                        q_self.set_error(QString::from(e.to_string()));
                    })
                    .ok();

                q_thread
                    .queue(move |q_self| {
                        q_self.set_albums(albums);
                    })
                    .ok();
            } else {
                q_thread
                    .queue(move |q_self| {
                        q_self.set_error(QString::default());
                    })
                    .ok();

                q_thread
                    .queue(move |q_self| {
                        q_self.set_albums(albums);
                    })
                    .ok();
            }
        });
    }

    fn query_album(self: Pin<&mut Self>, id: i32) {
        let con_arc = match &self.connection {
            Some(c) => c.clone(),
            None => return,
        };
        let q_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let res: Result<QList<QString>, Box<dyn std::error::Error + Send + Sync>> = (async {
                let con = con_arc.lock().await;
                let mut list: QList<QString> = QList::default();
                let mut stmt = con.prepare(&format!(
                    "
                    SELECT
                        ZASSET.ZDIRECTORY,  
                        ZASSET.ZFILENAME
                    FROM ZASSET WHERE ZASSET.Z_OPT = {}
                ",
                    id
                ))?;

                let row_iter = stmt.query_map([], |r| {
                    let fdir: String = r.get(0)?;
                    let fname: String = r.get(1)?;
                    Ok((fdir, fname))
                })?;

                for item in row_iter {
                    let (fdir, fname) = item?;
                    let full_path = format!("{}/{}", fdir, fname);
                    list.append(QString::from(full_path));
                }
                Ok((list))
            })
            .await;

            match res {
                Ok(list) => {
                    q_thread
                        .queue(move |q| {
                            q.album_queried(id, list);
                        })
                        .ok();
                }
                Err(_) => {
                    println!("Error querying album")
                }
            }
        });
    }

    fn query_favs(self: Pin<&mut Self>) {}

    fn query_recents(self: Pin<&mut Self>) {}
}

// fn get_album_query_sql(ios_ver : i32, id : i32) {
//     let assets_table = crate::utils::get_sqlite_assets_name(ios_ver);

//     format!("
//         SELECT
//             {}.ZDIRECTORY,
//             {}.ZFILENAME
//         FROM {} WHERE
//             {}.Z_OPT = {}

//     ")

// }
