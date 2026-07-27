use crate::constants::{PHOTOS_SQLITE_REMOTE_PATH, PHOTOS_SQLITE_WAL_REMOTE_PATH};
use crate::run_sync;
use anyhow::{Context, anyhow};
use idevice::afc::AfcClient;
use idevice::afc::errors::AfcError;
use idevice::afc::file::OwnedFileDescriptor;
use idevice::afc::opcode::AfcFopenMode;
use idevice::provider::IdeviceProvider;
use idevice::{IdeviceError, IdeviceService};
use log::{debug, warn};
use lru::LruCache;
use once_cell::sync::Lazy;
use rusqlite::{Connection, OpenFlags};
use sqlite_vfs::wip::{WalIndex, WalIndexLock};
use sqlite_vfs::{DatabaseHandle, LockKind, OpenAccess, OpenKind, OpenOptions, Vfs};
use std::borrow::Cow;
use std::collections::HashMap;
use std::io::{Error, ErrorKind, SeekFrom};
use std::num::NonZeroUsize;
use std::ops::Range;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex, OnceLock, RwLock};
use std::time::Duration;
use tokio::io::AsyncSeekExt;
use tokio::sync::Mutex;

pub const GALLERY_AFC_VFS_NAME: &str = "idescriptor-afc-gallery";
//TODO: test on linux and windows
const CACHE_BLOCK_SIZE: usize = 1024 * 1024;
const CACHE_BLOCK_COUNT: usize = 64;
const SNAPSHOT_ATTEMPTS: usize = 3;

static REGISTER_RESULT: OnceLock<Result<(), String>> = OnceLock::new();
static DATABASES: Lazy<RwLock<HashMap<String, Arc<GalleryVfsDatabase>>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));
static WAL_INDEX_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Debug, Eq, PartialEq)]
struct RemoteMetadata {
    size: usize,
    modified: String,
}

struct RemoteDatabase {
    file: Arc<Mutex<Option<OwnedFileDescriptor>>>,
    //FIXME: remove if not needed
    #[allow(dead_code)]
    metadata_afc: Arc<Mutex<AfcClient>>,
    expected: RemoteMetadata,
    cache: StdMutex<LruCache<u64, Arc<Vec<u8>>>>,
}
/*
  vfs is still experimental and doesn't provide much benefit over local copy of the Photos.sqlite file,
  other than not having to copy the entire Photos.sqlite file to local storage
*/
struct GalleryVfsDatabase {
    main: RemoteDatabase,
    wal: Option<Arc<Vec<u8>>>,
    wal_index: Arc<StdMutex<WalIndexState>>,
}

#[derive(Default)]
struct WalIndexState {
    regions: HashMap<u32, [u8; 32768]>,
    locks: HashMap<u8, Vec<(u64, WalIndexLock)>>,
}

#[derive(Clone)]
struct GalleryVfs;

enum GalleryVfsFileData {
    Main(Arc<GalleryVfsDatabase>),
    Wal {
        database: Arc<GalleryVfsDatabase>,
        bytes: Arc<Vec<u8>>,
    },
}

struct GalleryVfsFile {
    data: GalleryVfsFileData,
    lock: LockKind,
}

struct GalleryWalIndex {
    id: u64,
    shared: Arc<StdMutex<WalIndexState>>,
}

pub struct GalleryVfsRegistration {
    virtual_path: Option<String>,
}

impl GalleryVfsRegistration {
    pub fn virtual_path(&self) -> &str {
        self.virtual_path.as_deref().unwrap_or_default()
    }

    pub async fn close(mut self) -> anyhow::Result<()> {
        let Some(virtual_path) = self.virtual_path.take() else {
            return Ok(());
        };
        close_registered_database(virtual_path).await
    }

    pub fn close_in_background(mut self) {
        let Some(virtual_path) = self.virtual_path.take() else {
            return;
        };
        crate::RUNTIME.spawn(async move {
            if let Err(error) = close_registered_database(virtual_path).await {
                warn!("Failed to close gallery VFS AFC descriptor: {error}");
            }
        });
    }
}

impl Drop for GalleryVfsRegistration {
    fn drop(&mut self) {
        let Some(virtual_path) = self.virtual_path.take() else {
            return;
        };
        crate::RUNTIME.spawn(async move {
            if let Err(error) = close_registered_database(virtual_path).await {
                warn!("Failed to close dropped gallery VFS AFC descriptor: {error}");
            }
        });
    }
}

async fn close_registered_database(virtual_path: String) -> anyhow::Result<()> {
    let database = DATABASES
        .write()
        .map_err(|_| anyhow!("Gallery VFS registry lock is poisoned"))?
        .remove(&virtual_path);
    let Some(database) = database else {
        return Ok(());
    };

    let file = database.main.file.lock().await.take();
    if let Some(file) = file {
        file.close()
            .await
            .context("Failed to close Photos.sqlite AFC descriptor")?;
        debug!("Closed Photos.sqlite AFC descriptor for gallery VFS generation {virtual_path}");
    }
    Ok(())
}

pub async fn open_gallery_vfs_connection(
    afc: Arc<Mutex<AfcClient>>,
    provider: Arc<Mutex<Box<dyn IdeviceProvider>>>,
) -> anyhow::Result<(Connection, GalleryVfsRegistration)> {
    ensure_vfs_registered()?;

    let (main_metadata, wal) = capture_stable_remote_files(afc.clone()).await?;
    debug!("Creating dedicated AFC connection for the gallery VFS");
    let dedicated_afc = {
        let provider = provider.lock().await;
        AfcClient::connect(provider.as_ref())
            .await
            .context("Failed to create the gallery VFS AFC connection")?
    };
    debug!("Opening Photos.sqlite on the dedicated gallery VFS AFC connection");
    let main_file = dedicated_afc
        .open_owned(PHOTOS_SQLITE_REMOTE_PATH, AfcFopenMode::RdOnly)
        .await
        .context("Failed to open Photos.sqlite for the gallery VFS")?;

    let virtual_path = format!("idescriptor-gallery-{}.sqlite", uuid::Uuid::new_v4());
    let database = Arc::new(GalleryVfsDatabase {
        main: RemoteDatabase {
            file: Arc::new(Mutex::new(Some(main_file))),
            metadata_afc: afc,
            expected: main_metadata,
            cache: StdMutex::new(LruCache::new(
                NonZeroUsize::new(CACHE_BLOCK_COUNT).expect("cache capacity is non-zero"),
            )),
        },
        wal: wal.map(Arc::new),
        wal_index: Arc::new(StdMutex::new(WalIndexState::default())),
    });

    DATABASES
        .write()
        .map_err(|_| anyhow!("Gallery VFS registry lock is poisoned"))?
        .insert(virtual_path.clone(), database);

    let registration = GalleryVfsRegistration {
        virtual_path: Some(virtual_path.clone()),
    };
    let flags = OpenFlags::SQLITE_OPEN_READ_ONLY
        | OpenFlags::SQLITE_OPEN_URI
        | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    let open_path = virtual_path.clone();
    debug!("Opening SQLite connection through the gallery VFS");
    let connection = match tokio::task::spawn_blocking(move || -> anyhow::Result<Connection> {
        let connection =
            Connection::open_with_flags_and_vfs(&open_path, flags, GALLERY_AFC_VFS_NAME)
                .context("Failed to open Photos.sqlite through the AFC VFS")?;
        connection.execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA temp_store = MEMORY;
             PRAGMA mmap_size = 0;
             PRAGMA cache_size = -32768;",
        )?;
        Ok(connection)
    })
    .await
    {
        Ok(Ok(connection)) => connection,
        Ok(Err(error)) => {
            if let Err(close_error) = registration.close().await {
                warn!("Failed to clean up gallery VFS after open error: {close_error}");
            }
            return Err(error);
        }
        Err(error) => {
            if let Err(close_error) = registration.close().await {
                warn!("Failed to clean up gallery VFS after worker error: {close_error}");
            }
            return Err(anyhow!("Gallery VFS SQLite worker failed: {error}"));
        }
    };
    debug!("SQLite connection opened through the gallery VFS");

    Ok((connection, registration))
}

fn ensure_vfs_registered() -> anyhow::Result<()> {
    let result = REGISTER_RESULT.get_or_init(|| {
        sqlite_vfs::register(GALLERY_AFC_VFS_NAME, GalleryVfs, false)
            .map_err(|error| error.to_string())
    });

    result
        .as_ref()
        .map(|_| ())
        .map_err(|error| anyhow!("Failed to register gallery AFC VFS: {error}"))
}

async fn capture_stable_remote_files(
    afc: Arc<Mutex<AfcClient>>,
) -> anyhow::Result<(RemoteMetadata, Option<Vec<u8>>)> {
    for attempt in 1..=SNAPSHOT_ATTEMPTS {
        let mut afc = afc.lock().await;
        let main_before = remote_metadata(&mut afc, PHOTOS_SQLITE_REMOTE_PATH)
            .await?
            .context("Required Photos.sqlite is missing from the device")?;
        let wal_before = remote_metadata(&mut afc, PHOTOS_SQLITE_WAL_REMOTE_PATH).await?;
        let wal = match wal_before.as_ref() {
            Some(_) => Some(read_remote_file(&mut afc, PHOTOS_SQLITE_WAL_REMOTE_PATH).await?),
            None => None,
        };
        let main_after = remote_metadata(&mut afc, PHOTOS_SQLITE_REMOTE_PATH)
            .await?
            .context("Required Photos.sqlite disappeared from the device")?;
        let wal_after = remote_metadata(&mut afc, PHOTOS_SQLITE_WAL_REMOTE_PATH).await?;

        if main_before == main_after && wal_before == wal_after {
            if let (Some(metadata), Some(bytes)) = (wal_after.as_ref(), wal.as_ref()) {
                if metadata.size != bytes.len() {
                    warn!(
                        "Gallery WAL size changed while reading: stat={} read={}",
                        metadata.size,
                        bytes.len()
                    );
                    continue;
                }
            }
            debug!(
                "Captured stable gallery VFS generation on attempt {attempt}: main={} bytes, wal={} bytes",
                main_after.size,
                wal.as_ref().map_or(0, Vec::len)
            );
            return Ok((main_after, wal));
        }

        warn!("Gallery database changed during VFS capture attempt {attempt}");
    }

    Err(anyhow!(
        "Photos.sqlite kept changing while preparing the gallery VFS"
    ))
}

async fn remote_metadata(
    afc: &mut AfcClient,
    path: &str,
) -> anyhow::Result<Option<RemoteMetadata>> {
    match afc.get_file_info(path).await {
        Ok(info) => Ok(Some(RemoteMetadata {
            size: info.size,
            modified: info.modified.to_string(),
        })),
        Err(error) if is_missing_file_error(&error) => Ok(None),
        Err(error) => Err(error).with_context(|| format!("Failed to stat {path}")),
    }
}

async fn read_remote_file(afc: &mut AfcClient, path: &str) -> anyhow::Result<Vec<u8>> {
    let mut file = afc
        .open(path, AfcFopenMode::RdOnly)
        .await
        .with_context(|| format!("Failed to open {path}"))?;
    let result = file
        .read_entire()
        .await
        .with_context(|| format!("Failed to read {path}"));
    file.close().await.ok();
    result
}

fn is_missing_file_error(error: &IdeviceError) -> bool {
    matches!(
        error,
        IdeviceError::NotFound | IdeviceError::Afc(AfcError::ObjectNotFound)
    )
}

impl RemoteDatabase {
    fn read_exact_at(&self, output: &mut [u8], offset: u64) -> Result<(), Error> {
        output.fill(0);
        let requested_end = offset.saturating_add(output.len() as u64);
        let readable_end = requested_end.min(self.expected.size as u64);
        if offset >= readable_end {
            return Err(ErrorKind::UnexpectedEof.into());
        }

        let mut output_offset = 0usize;
        let mut current = offset;
        while current < readable_end {
            let block_index = current / CACHE_BLOCK_SIZE as u64;
            let block_offset = (current % CACHE_BLOCK_SIZE as u64) as usize;
            let block = self.cached_block(block_index)?;
            let available = block.len().saturating_sub(block_offset);
            if available == 0 {
                return Err(Error::new(
                    ErrorKind::UnexpectedEof,
                    "AFC returned a short gallery database block",
                ));
            }
            let remaining = (readable_end - current) as usize;
            let copy_len = available.min(remaining);
            output[output_offset..output_offset + copy_len]
                .copy_from_slice(&block[block_offset..block_offset + copy_len]);
            output_offset += copy_len;
            current += copy_len as u64;
        }

        if readable_end < requested_end {
            Err(ErrorKind::UnexpectedEof.into())
        } else {
            Ok(())
        }
    }

    fn cached_block(&self, block_index: u64) -> Result<Arc<Vec<u8>>, Error> {
        if let Some(block) = self
            .cache
            .lock()
            .map_err(|_| Error::other("Gallery VFS cache lock is poisoned"))?
            .get(&block_index)
            .cloned()
        {
            return Ok(block);
        }

        let offset = block_index * CACHE_BLOCK_SIZE as u64;
        let read_len = (self.expected.size as u64)
            .saturating_sub(offset)
            .min(CACHE_BLOCK_SIZE as u64) as usize;
        // let expected = self.expected.clone();
        // let metadata_afc = self.metadata_afc.clone();
        let file = self.file.clone();
        let bytes = run_sync(async move {
            //TODO: should we do this?
            // let current = {
            //     let mut afc = metadata_afc.lock().await;
            //     remote_metadata(&mut afc, PHOTOS_SQLITE_REMOTE_PATH).await
            // }
            // .map_err(to_io_error)?
            // .ok_or_else(|| Error::new(ErrorKind::NotFound, "Photos.sqlite disappeared"))?;
            // if current != expected {
            //     return Err(Error::new(
            //         ErrorKind::Other,
            //         "Photos.sqlite changed; refresh the gallery",
            //     ));
            // }

            let mut file = file.lock().await;
            let file = file
                .as_mut()
                .ok_or_else(|| Error::other("Photos.sqlite AFC descriptor is closed"))?;
            file.seek(SeekFrom::Start(offset))
                .await
                .map_err(to_io_error)?;
            let bytes = file.read_n(read_len).await.map_err(to_io_error)?;
            if bytes.len() != read_len {
                return Err(Error::new(
                    ErrorKind::UnexpectedEof,
                    "AFC returned a short Photos.sqlite read",
                ));
            }
            Ok(bytes)
        })?;

        let block = Arc::new(bytes);
        self.cache
            .lock()
            .map_err(|_| Error::other("Gallery VFS cache lock is poisoned"))?
            .put(block_index, block.clone());
        Ok(block)
    }
}

fn to_io_error(error: impl std::fmt::Display) -> Error {
    Error::other(error.to_string())
}

impl Vfs for GalleryVfs {
    type Handle = GalleryVfsFile;

    fn open(&self, db: &str, options: OpenOptions) -> Result<Self::Handle, Error> {
        if options.access != OpenAccess::Read {
            return Err(Error::new(
                ErrorKind::PermissionDenied,
                "Gallery VFS is read-only",
            ));
        }

        let base = match options.kind {
            OpenKind::MainDb => db,
            OpenKind::Wal => db
                .strip_suffix("-wal")
                .ok_or_else(|| Error::new(ErrorKind::NotFound, "Invalid gallery WAL path"))?,
            _ => {
                return Err(Error::new(
                    ErrorKind::PermissionDenied,
                    "Gallery VFS only exposes the database and WAL",
                ));
            }
        };
        let database = DATABASES
            .read()
            .map_err(|_| Error::other("Gallery VFS registry lock is poisoned"))?
            .get(base)
            .cloned()
            .ok_or_else(|| Error::new(ErrorKind::NotFound, "Unknown gallery VFS database"))?;

        let data = match options.kind {
            OpenKind::MainDb => GalleryVfsFileData::Main(database),
            OpenKind::Wal => GalleryVfsFileData::Wal {
                bytes: database
                    .wal
                    .clone()
                    .ok_or_else(|| Error::new(ErrorKind::NotFound, "Gallery WAL is absent"))?,
                database,
            },
            _ => unreachable!(),
        };

        Ok(GalleryVfsFile {
            data,
            lock: LockKind::None,
        })
    }

    fn delete(&self, _db: &str) -> Result<(), Error> {
        Err(Error::new(
            ErrorKind::PermissionDenied,
            "Gallery VFS is read-only",
        ))
    }

    fn exists(&self, db: &str) -> Result<bool, Error> {
        let databases = DATABASES
            .read()
            .map_err(|_| Error::other("Gallery VFS registry lock is poisoned"))?;
        if let Some(base) = db.strip_suffix("-wal") {
            return Ok(databases
                .get(base)
                .is_some_and(|database| database.wal.is_some()));
        }
        Ok(databases.contains_key(db))
    }

    fn temporary_name(&self) -> String {
        format!("idescriptor-gallery-temp-{}", uuid::Uuid::new_v4())
    }

    fn random(&self, buffer: &mut [i8]) {
        let random = uuid::Uuid::new_v4();
        for (index, byte) in buffer.iter_mut().enumerate() {
            *byte = random.as_bytes()[index % 16] as i8;
        }
    }

    fn sleep(&self, duration: Duration) -> Duration {
        std::thread::sleep(duration);
        duration
    }

    fn access(&self, db: &str, write: bool) -> Result<bool, Error> {
        if write {
            return Ok(false);
        }
        self.exists(db)
    }

    fn full_pathname<'a>(&self, db: &'a str) -> Result<Cow<'a, str>, Error> {
        Ok(Cow::Borrowed(db))
    }
}

impl DatabaseHandle for GalleryVfsFile {
    type WalIndex = GalleryWalIndex;

    fn size(&self) -> Result<u64, Error> {
        match &self.data {
            GalleryVfsFileData::Main(database) => Ok(database.main.expected.size as u64),
            GalleryVfsFileData::Wal { bytes, .. } => Ok(bytes.len() as u64),
        }
    }

    fn read_exact_at(&mut self, output: &mut [u8], offset: u64) -> Result<(), Error> {
        match &self.data {
            GalleryVfsFileData::Main(database) => database.main.read_exact_at(output, offset),
            GalleryVfsFileData::Wal { bytes, .. } => {
                output.fill(0);
                let offset = offset as usize;
                if offset >= bytes.len() {
                    return Err(ErrorKind::UnexpectedEof.into());
                }
                let copy_len = output.len().min(bytes.len() - offset);
                output[..copy_len].copy_from_slice(&bytes[offset..offset + copy_len]);
                if copy_len != output.len() {
                    Err(ErrorKind::UnexpectedEof.into())
                } else {
                    Ok(())
                }
            }
        }
    }

    fn write_all_at(&mut self, _buf: &[u8], _offset: u64) -> Result<(), Error> {
        Err(Error::new(
            ErrorKind::PermissionDenied,
            "Gallery VFS is read-only",
        ))
    }

    fn sync(&mut self, _data_only: bool) -> Result<(), Error> {
        Ok(())
    }

    fn set_len(&mut self, _size: u64) -> Result<(), Error> {
        Err(Error::new(
            ErrorKind::PermissionDenied,
            "Gallery VFS is read-only",
        ))
    }

    fn lock(&mut self, lock: LockKind) -> Result<bool, Error> {
        self.lock = lock;
        Ok(true)
    }

    fn unlock(&mut self, lock: LockKind) -> Result<bool, Error> {
        self.lock = lock;
        Ok(true)
    }

    fn reserved(&mut self) -> Result<bool, Error> {
        Ok(self.lock >= LockKind::Reserved)
    }

    fn current_lock(&self) -> Result<LockKind, Error> {
        Ok(self.lock)
    }

    fn wal_index(&self, _readonly: bool) -> Result<Self::WalIndex, Error> {
        let shared = match &self.data {
            GalleryVfsFileData::Main(database) | GalleryVfsFileData::Wal { database, .. } => {
                database.wal_index.clone()
            }
        };
        Ok(GalleryWalIndex {
            id: WAL_INDEX_ID.fetch_add(1, Ordering::Relaxed),
            shared,
        })
    }
}

impl WalIndex for GalleryWalIndex {
    fn map(&mut self, region: u32) -> Result<[u8; 32768], Error> {
        Ok(self
            .shared
            .lock()
            .map_err(|_| Error::other("Gallery WAL index lock is poisoned"))?
            .regions
            .get(&region)
            .copied()
            .unwrap_or([0; 32768]))
    }

    fn lock(&mut self, locks: Range<u8>, lock: WalIndexLock) -> Result<bool, Error> {
        let mut state = self
            .shared
            .lock()
            .map_err(|_| Error::other("Gallery WAL index lock is poisoned"))?;

        if lock == WalIndexLock::None {
            for byte in locks {
                if let Some(holders) = state.locks.get_mut(&byte) {
                    holders.retain(|(owner, _)| *owner != self.id);
                }
            }
            return Ok(true);
        }

        for byte in locks.clone() {
            let conflict = state.locks.get(&byte).is_some_and(|holders| {
                holders.iter().any(|(owner, held)| {
                    *owner != self.id
                        && (*held == WalIndexLock::Exclusive || lock == WalIndexLock::Exclusive)
                })
            });
            if conflict {
                return Ok(false);
            }
        }

        for byte in locks {
            let holders = state.locks.entry(byte).or_default();
            holders.retain(|(owner, _)| *owner != self.id);
            holders.push((self.id, lock));
        }
        Ok(true)
    }

    fn delete(self) -> Result<(), Error> {
        let mut state = self
            .shared
            .lock()
            .map_err(|_| Error::other("Gallery WAL index lock is poisoned"))?;
        state.regions.clear();
        state.locks.clear();
        Ok(())
    }

    fn pull(&mut self, region: u32, data: &mut [u8; 32768]) -> Result<(), Error> {
        *data = self
            .shared
            .lock()
            .map_err(|_| Error::other("Gallery WAL index lock is poisoned"))?
            .regions
            .get(&region)
            .copied()
            .unwrap_or([0; 32768]);
        Ok(())
    }

    fn push(&mut self, region: u32, data: &[u8; 32768]) -> Result<(), Error> {
        self.shared
            .lock()
            .map_err(|_| Error::other("Gallery WAL index lock is poisoned"))?
            .regions
            .insert(region, *data);
        Ok(())
    }
}
