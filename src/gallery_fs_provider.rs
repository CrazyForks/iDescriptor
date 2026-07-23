use qmetaobject::prelude::*;
use qttypes::{QStringList, QVariantList, QVariantMap};

use crate::constants::{
    ALBUM_CONTENTS_QUERY_TEMPLATE, DCIM_REMOTE_PATH, FAVS_ALBUM_ID, FAVS_ALBUM_QUERY, FAVS_QUERY,
    FS_GALLERY_PROVIDER_NAME, IOS_15_ALBUM_QUERY_STATEMENT, IOS_26_ALBUM_QUERY_STATEMENT,
    RECENTS_ALBUM_ID, RECENTS_ALBUM_QUERY, RECENTS_QUERY, SQLITE_GALLERY_PROVIDER_NAME,
};
use crate::device_ctx;
use crate::gallery::{
    GalleryAlbum, GalleryFuture, GalleryMediaFilter, GalleryProvider, apple_dcim_folder_id,
    is_apple_dcim_folder, is_previewable_media_file, matches_media_filter,
};
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

struct FsGalleryProvider {
    afc: Arc<Mutex<AfcClient>>,
    name: String,
}

impl GalleryProvider for FsGalleryProvider {
    fn name(&self) -> String {
        self.name.clone()
    }

    fn read_albums(&self) -> GalleryFuture<(Vec<GalleryAlbum>, i32)> {
        let afc = self.afc.clone();
        Box::pin(async move { Ok((read_fs_albums(afc).await?, 0)) })
    }

    fn reload(&self) -> GalleryFuture<(Vec<GalleryAlbum>, i32)> {
        self.read_albums()
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

    // TODO: can we do something here?
    fn query_gallery_size(&self) -> GalleryFuture<u64> {
        Box::pin(async move { Ok(0) })
    }
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

pub async fn build_fs_provider(
    afc: Arc<Mutex<AfcClient>>,
) -> anyhow::Result<Arc<dyn GalleryProvider>> {
    Ok(Arc::new(FsGalleryProvider {
        afc,
        name: FS_GALLERY_PROVIDER_NAME.into(),
    }))
}
