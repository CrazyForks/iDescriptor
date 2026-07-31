use std::{
    ffi::c_void,
    os::windows::ffi::OsStringExt,
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

use idevice::{IdeviceError, afc::errors::AfcError, afc::opcode::AfcFopenMode};
use tokio::runtime::Handle;
use widestring::U16CStr;
use windows::Win32::Foundation::{
    STATUS_ACCESS_DENIED, STATUS_DEVICE_NOT_CONNECTED, STATUS_DIRECTORY_NOT_EMPTY,
    STATUS_DISK_FULL, STATUS_FILE_IS_A_DIRECTORY, STATUS_FILE_NOT_AVAILABLE,
    STATUS_INVALID_PARAMETER, STATUS_IO_DEVICE_ERROR, STATUS_NOT_A_DIRECTORY, STATUS_NOT_FOUND,
    STATUS_NOT_SUPPORTED, STATUS_OBJECT_NAME_COLLISION,
};
use winfsp::{
    FspError,
    filesystem::{
        DirInfo, DirMarker, FileInfo, FileSecurity, FileSystemContext, OpenFileInfo, VolumeInfo,
        WideNameInfo,
    },
};

use crate::afc::{AfcSession, RemoteDeviceInfo, RemoteFileInfo};

const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
const FILE_DIRECTORY_FILE: u32 = 0x1;
const FILE_WRITE_DATA: u32 = 0x2;
const FILE_APPEND_DATA: u32 = 0x4;
const IO_REPARSE_TAG_SYMLINK: u32 = 0xA000000C;

#[derive(Debug)]
pub(crate) struct IfuseFileContext {
    path: String,
    descriptor: Option<u64>,
    directory: bool,
    delete_pending: AtomicBool,
    directory_entries: Mutex<Option<Vec<DirectoryEntry>>>,
}

#[derive(Debug)]
struct DirectoryEntry {
    name: String,
    info: RemoteFileInfo,
}

pub(crate) struct IfuseFilesystem {
    runtime: Handle,
    session: Mutex<AfcSession>,
    volume_label: Mutex<String>,
}

impl IfuseFilesystem {
    pub fn new(runtime: Handle, session: AfcSession, volume_label: String) -> Self {
        Self {
            runtime,
            session: Mutex::new(session),
            volume_label: Mutex::new(volume_label),
        }
    }

    fn run<T>(
        &self,
        operation: impl std::future::Future<Output = Result<T, IdeviceError>>,
    ) -> winfsp::Result<T> {
        self.runtime.block_on(operation).map_err(map_idevice_error)
    }

    fn stat(&self, path: &str) -> winfsp::Result<RemoteFileInfo> {
        let mut session = self.session.lock().unwrap();
        self.run(session.get_file_info(path))
    }

    fn fill_info(&self, path: &str, output: &mut FileInfo) -> winfsp::Result<RemoteFileInfo> {
        let info = self.stat(path)?;
        *output = file_info(&info);
        Ok(info)
    }

    fn create_context(
        &self,
        path: String,
        directory: bool,
        descriptor: Option<u64>,
    ) -> IfuseFileContext {
        IfuseFileContext {
            path,
            descriptor,
            directory,
            delete_pending: AtomicBool::new(false),
            directory_entries: Mutex::new(None),
        }
    }
}

impl FileSystemContext for IfuseFilesystem {
    type FileContext = IfuseFileContext;

    fn get_security_by_name(
        &self,
        file_name: &U16CStr,
        _security_descriptor: Option<&mut [c_void]>,
        _reparse_point_resolver: impl FnOnce(&U16CStr) -> Option<FileSecurity>,
    ) -> winfsp::Result<FileSecurity> {
        let path = afc_path(file_name);
        let info = self.stat(&path)?;
        Ok(FileSecurity {
            reparse: info.kind == "S_IFLNK",
            sz_security_descriptor: 0,
            attributes: file_attributes(&info),
        })
    }

    fn open(
        &self,
        file_name: &U16CStr,
        _create_options: u32,
        granted_access: winfsp_sys::FILE_ACCESS_RIGHTS,
        file_info: &mut OpenFileInfo,
    ) -> winfsp::Result<Self::FileContext> {
        let path = afc_path(file_name);
        let info = self.fill_info(&path, file_info.as_mut())?;
        let directory = info.kind == "S_IFDIR";
        let descriptor = if directory {
            None
        } else {
            let mode = access_mode(granted_access as u32);
            let mut session = self.session.lock().unwrap();
            Some(self.run(session.open(&path, mode))?)
        };
        Ok(self.create_context(path, directory, descriptor))
    }

    fn close(&self, context: Self::FileContext) {
        if let Some(descriptor) = context.descriptor {
            let mut session = self.session.lock().unwrap();
            if let Err(error) = self.run(session.close(descriptor)) {
                log::warn!(
                    "failed to close AFC descriptor for {}: {error}",
                    context.path
                );
            }
        }
    }

    fn create(
        &self,
        file_name: &U16CStr,
        create_options: u32,
        _granted_access: winfsp_sys::FILE_ACCESS_RIGHTS,
        _file_attributes: winfsp_sys::FILE_FLAGS_AND_ATTRIBUTES,
        _security_descriptor: Option<&[c_void]>,
        allocation_size: u64,
        extra_buffer: Option<&[u8]>,
        extra_buffer_is_reparse_point: bool,
        file_info: &mut OpenFileInfo,
    ) -> winfsp::Result<Self::FileContext> {
        let path = afc_path(file_name);
        if extra_buffer_is_reparse_point {
            let target = parse_symlink_reparse(extra_buffer.unwrap_or_default())?;
            let mut session = self.session.lock().unwrap();
            self.run(session.symlink(&target, &path))?;
            self.fill_info(&path, file_info.as_mut())?;
            return Ok(self.create_context(path, false, None));
        }

        if create_options & FILE_DIRECTORY_FILE != 0 {
            let mut session = self.session.lock().unwrap();
            self.run(session.mkdir(&path))?;
            self.fill_info(&path, file_info.as_mut())?;
            return Ok(self.create_context(path, true, None));
        }

        let descriptor = {
            let mut session = self.session.lock().unwrap();
            let descriptor = self.run(session.open(&path, AfcFopenMode::Wr))?;
            if allocation_size != 0 {
                self.run(session.truncate(descriptor, allocation_size))?;
            }
            descriptor
        };
        self.fill_info(&path, file_info.as_mut())?;
        Ok(self.create_context(path, false, Some(descriptor)))
    }

    fn cleanup(&self, context: &Self::FileContext, _file_name: Option<&U16CStr>, _flags: u32) {
        if context.delete_pending.load(Ordering::Acquire) {
            let mut session = self.session.lock().unwrap();
            if let Err(error) = self.run(session.remove(&context.path)) {
                log::warn!("failed to delete AFC path {}: {error}", context.path);
            }
        }
    }

    fn flush(
        &self,
        context: Option<&Self::FileContext>,
        file_info: &mut FileInfo,
    ) -> winfsp::Result<()> {
        if let Some(context) = context {
            self.fill_info(&context.path, file_info)?;
        }
        Ok(())
    }

    fn get_file_info(
        &self,
        context: &Self::FileContext,
        file_info: &mut FileInfo,
    ) -> winfsp::Result<()> {
        self.fill_info(&context.path, file_info)?;
        Ok(())
    }

    fn overwrite(
        &self,
        context: &Self::FileContext,
        _file_attributes: winfsp_sys::FILE_FLAGS_AND_ATTRIBUTES,
        _replace_file_attributes: bool,
        allocation_size: u64,
        _extra_buffer: Option<&[u8]>,
        file_info: &mut FileInfo,
    ) -> winfsp::Result<()> {
        let descriptor = context
            .descriptor
            .ok_or_else(|| FspError::NTSTATUS(STATUS_FILE_IS_A_DIRECTORY.0))?;
        let mut session = self.session.lock().unwrap();
        self.run(session.truncate(descriptor, allocation_size))?;
        drop(session);
        self.fill_info(&context.path, file_info)?;
        Ok(())
    }

    fn read_directory(
        &self,
        context: &Self::FileContext,
        _pattern: Option<&U16CStr>,
        marker: DirMarker,
        buffer: &mut [u8],
    ) -> winfsp::Result<u32> {
        if !context.directory {
            return Err(STATUS_NOT_A_DIRECTORY.into());
        }
        if marker.is_none() {
            let names = {
                let mut session = self.session.lock().unwrap();
                self.run(session.list_dir(&context.path))?
            };
            let mut entries = Vec::with_capacity(names.len());
            for name in names {
                if name == "." || name == ".." {
                    continue;
                }
                let child = join_afc_path(&context.path, &name);
                let info = self.stat(&child)?;
                entries.push(DirectoryEntry { name, info });
            }
            entries.sort_unstable_by(|left, right| left.name.cmp(&right.name));
            *context.directory_entries.lock().unwrap() = Some(entries);
        }

        let marker = marker.inner().map(String::from_utf16_lossy);
        let entries = context.directory_entries.lock().unwrap();
        let entries = entries.as_deref().unwrap_or_default();
        let start = directory_start(entries, marker.as_deref());
        let mut cursor = 0;
        let mut reached_end = true;

        for entry in &entries[start..] {
            let mut directory_info: DirInfo<255> = DirInfo::new();
            *directory_info.file_info_mut() = file_info(&entry.info);
            directory_info.set_name(&entry.name)?;
            if !directory_info.append_to_buffer(buffer, &mut cursor) {
                reached_end = false;
                break;
            }
        }

        if reached_end {
            DirInfo::<255>::finalize_buffer(buffer, &mut cursor);
        }
        Ok(cursor)
    }

    fn rename(
        &self,
        _context: &Self::FileContext,
        file_name: &U16CStr,
        new_file_name: &U16CStr,
        replace_if_exists: bool,
    ) -> winfsp::Result<()> {
        let from = afc_path(file_name);
        let to = afc_path(new_file_name);
        let mut session = self.session.lock().unwrap();
        if replace_if_exists && self.run(session.get_file_info(&to)).is_ok() {
            self.run(session.remove(&to))?;
        }
        self.run(session.rename(&from, &to))
    }

    fn set_basic_info(
        &self,
        context: &Self::FileContext,
        _file_attributes: u32,
        _creation_time: u64,
        _last_access_time: u64,
        last_write_time: u64,
        _last_change_time: u64,
        file_info: &mut FileInfo,
    ) -> winfsp::Result<()> {
        if last_write_time != 0 {
            let nanoseconds = windows_time_to_unix_nanos(last_write_time);
            let mut session = self.session.lock().unwrap();
            self.run(session.set_mtime(&context.path, nanoseconds))?;
        }
        self.fill_info(&context.path, file_info)?;
        Ok(())
    }

    fn set_delete(
        &self,
        context: &Self::FileContext,
        _file_name: &U16CStr,
        delete_file: bool,
    ) -> winfsp::Result<()> {
        if delete_file && context.directory {
            let mut session = self.session.lock().unwrap();
            let children = self.run(session.list_dir(&context.path))?;
            if children.iter().any(|name| name != "." && name != "..") {
                return Err(STATUS_DIRECTORY_NOT_EMPTY.into());
            }
        }
        context.delete_pending.store(delete_file, Ordering::Release);
        Ok(())
    }

    fn set_file_size(
        &self,
        context: &Self::FileContext,
        new_size: u64,
        _set_allocation_size: bool,
        file_info: &mut FileInfo,
    ) -> winfsp::Result<()> {
        let descriptor = context
            .descriptor
            .ok_or_else(|| FspError::NTSTATUS(STATUS_FILE_IS_A_DIRECTORY.0))?;
        let mut session = self.session.lock().unwrap();
        self.run(session.truncate(descriptor, new_size))?;
        drop(session);
        self.fill_info(&context.path, file_info)?;
        Ok(())
    }

    fn read(
        &self,
        context: &Self::FileContext,
        buffer: &mut [u8],
        offset: u64,
    ) -> winfsp::Result<u32> {
        let descriptor = context
            .descriptor
            .ok_or_else(|| FspError::NTSTATUS(STATUS_FILE_IS_A_DIRECTORY.0))?;
        let mut session = self.session.lock().unwrap();
        let bytes = self.run(session.read_at(descriptor, offset, buffer.len()))?;
        buffer[..bytes.len()].copy_from_slice(&bytes);
        Ok(bytes.len() as u32)
    }

    fn write(
        &self,
        context: &Self::FileContext,
        buffer: &[u8],
        offset: u64,
        write_to_eof: bool,
        _constrained_io: bool,
        file_info: &mut FileInfo,
    ) -> winfsp::Result<u32> {
        let descriptor = context
            .descriptor
            .ok_or_else(|| FspError::NTSTATUS(STATUS_FILE_IS_A_DIRECTORY.0))?;
        let offset = if write_to_eof {
            self.stat(&context.path)?.size
        } else {
            offset
        };
        let mut session = self.session.lock().unwrap();
        let written = self.run(session.write_at(descriptor, offset, buffer))?;
        drop(session);
        self.fill_info(&context.path, file_info)?;
        Ok(written as u32)
    }

    fn get_volume_info(&self, output: &mut VolumeInfo) -> winfsp::Result<()> {
        let info: RemoteDeviceInfo = {
            let mut session = self.session.lock().unwrap();
            self.run(session.get_device_info())?
        };
        output.total_size = info.total_bytes;
        output.free_size = info.free_bytes;
        output.set_volume_label(self.volume_label.lock().unwrap().as_str());
        Ok(())
    }

    fn set_volume_label(
        &self,
        volume_label: &U16CStr,
        volume_info: &mut VolumeInfo,
    ) -> winfsp::Result<()> {
        let label = wide_string(volume_label);
        *self.volume_label.lock().unwrap() = label.clone();
        self.get_volume_info(volume_info)?;
        volume_info.set_volume_label(label);
        Ok(())
    }

    fn get_reparse_point_by_name(
        &self,
        file_name: &U16CStr,
        _is_directory: bool,
        buffer: &mut [u8],
    ) -> winfsp::Result<u64> {
        let info = self.stat(&afc_path(file_name))?;
        let target = info
            .link_target
            .ok_or_else(|| FspError::NTSTATUS(STATUS_NOT_SUPPORTED.0))?;
        write_symlink_reparse(&target, buffer)
    }

    fn get_reparse_point(
        &self,
        context: &Self::FileContext,
        _file_name: &U16CStr,
        buffer: &mut [u8],
    ) -> winfsp::Result<u64> {
        let info = self.stat(&context.path)?;
        let target = info
            .link_target
            .ok_or_else(|| FspError::NTSTATUS(STATUS_NOT_SUPPORTED.0))?;
        write_symlink_reparse(&target, buffer)
    }

    fn set_reparse_point(
        &self,
        context: &Self::FileContext,
        _file_name: &U16CStr,
        buffer: &[u8],
    ) -> winfsp::Result<()> {
        let target = parse_symlink_reparse(buffer)?;
        let mut session = self.session.lock().unwrap();
        self.run(session.remove(&context.path))?;
        self.run(session.symlink(&target, &context.path))
    }
}

fn afc_path(path: &U16CStr) -> String {
    let value = wide_string(path).replace('\\', "/");
    if value.is_empty() || value == "/" {
        "/".into()
    } else if value.starts_with('/') {
        value
    } else {
        format!("/{value}")
    }
}

fn wide_string(value: &U16CStr) -> String {
    std::ffi::OsString::from_wide(value.as_slice())
        .to_string_lossy()
        .into_owned()
}

fn join_afc_path(parent: &str, name: &str) -> String {
    if parent == "/" {
        format!("/{name}")
    } else {
        format!("{parent}/{name}")
    }
}

fn directory_start(entries: &[DirectoryEntry], marker: Option<&str>) -> usize {
    marker.map_or(0, |marker| {
        entries.partition_point(|entry| entry.name.as_str() <= marker)
    })
}

fn access_mode(access: u32) -> AfcFopenMode {
    if access & FILE_APPEND_DATA != 0 {
        AfcFopenMode::RdAppend
    } else if access & FILE_WRITE_DATA != 0 {
        AfcFopenMode::Rw
    } else {
        AfcFopenMode::RdOnly
    }
}

fn file_attributes(info: &RemoteFileInfo) -> u32 {
    match info.kind.as_str() {
        "S_IFDIR" => FILE_ATTRIBUTE_DIRECTORY,
        "S_IFLNK" => FILE_ATTRIBUTE_REPARSE_POINT,
        _ => FILE_ATTRIBUTE_NORMAL,
    }
}

fn file_info(info: &RemoteFileInfo) -> FileInfo {
    let creation = unix_nanos_to_windows_time(info.birthtime_ns);
    let modified = unix_nanos_to_windows_time(info.mtime_ns);
    FileInfo {
        file_attributes: file_attributes(info),
        reparse_tag: (info.kind == "S_IFLNK")
            .then_some(IO_REPARSE_TAG_SYMLINK)
            .unwrap_or(0),
        allocation_size: info.blocks.saturating_mul(4096).max(info.size),
        file_size: info.size,
        creation_time: creation,
        last_access_time: modified,
        last_write_time: modified,
        change_time: modified,
        ..Default::default()
    }
}

const WINDOWS_EPOCH_TICKS: i128 = 116_444_736_000_000_000;

fn unix_nanos_to_windows_time(nanoseconds: i64) -> u64 {
    (WINDOWS_EPOCH_TICKS + i128::from(nanoseconds) / 100).max(0) as u64
}

fn windows_time_to_unix_nanos(ticks: u64) -> u64 {
    (i128::from(ticks).saturating_sub(WINDOWS_EPOCH_TICKS).max(0) * 100) as u64
}

fn map_idevice_error(error: IdeviceError) -> FspError {
    let status = match error {
        IdeviceError::Afc(AfcError::ObjectNotFound) | IdeviceError::DeviceNotFound => {
            STATUS_NOT_FOUND
        }
        IdeviceError::Afc(AfcError::ObjectExists) => STATUS_OBJECT_NAME_COLLISION,
        IdeviceError::Afc(AfcError::ObjectIsDir) => STATUS_FILE_IS_A_DIRECTORY,
        IdeviceError::Afc(AfcError::PermDenied) => STATUS_ACCESS_DENIED,
        IdeviceError::Afc(AfcError::NoSpaceLeft) => STATUS_DISK_FULL,
        IdeviceError::Afc(AfcError::DirNotEmpty) => STATUS_DIRECTORY_NOT_EMPTY,
        IdeviceError::Afc(AfcError::InvalidArg) => STATUS_INVALID_PARAMETER,
        IdeviceError::Afc(AfcError::OpNotSupported) => STATUS_NOT_SUPPORTED,
        IdeviceError::Afc(AfcError::ServiceNotConnected)
        | IdeviceError::NoEstablishedConnection => STATUS_DEVICE_NOT_CONNECTED,
        IdeviceError::Timeout | IdeviceError::Afc(AfcError::OpTimeout) => STATUS_FILE_NOT_AVAILABLE,
        _ => STATUS_IO_DEVICE_ERROR,
    };
    FspError::NTSTATUS(status.0)
}

fn write_symlink_reparse(target: &str, buffer: &mut [u8]) -> winfsp::Result<u64> {
    let target = target.replace('/', "\\");
    let wide: Vec<u16> = target.encode_utf16().collect();
    let path_bytes = wide.len() * 2;
    let total = 20 + path_bytes * 2;
    if buffer.len() < total {
        return Err(FspError::NTSTATUS(STATUS_INVALID_PARAMETER.0));
    }
    buffer[..total].fill(0);
    buffer[0..4].copy_from_slice(&IO_REPARSE_TAG_SYMLINK.to_le_bytes());
    buffer[4..6].copy_from_slice(&((12 + path_bytes * 2) as u16).to_le_bytes());
    buffer[8..10].copy_from_slice(&0u16.to_le_bytes());
    buffer[10..12].copy_from_slice(&(path_bytes as u16).to_le_bytes());
    buffer[12..14].copy_from_slice(&(path_bytes as u16).to_le_bytes());
    buffer[14..16].copy_from_slice(&(path_bytes as u16).to_le_bytes());
    buffer[16..20].copy_from_slice(&1u32.to_le_bytes());
    for (index, character) in wide.iter().chain(wide.iter()).enumerate() {
        let offset = 20 + index * 2;
        buffer[offset..offset + 2].copy_from_slice(&character.to_le_bytes());
    }
    Ok(total as u64)
}

fn parse_symlink_reparse(buffer: &[u8]) -> winfsp::Result<String> {
    if buffer.len() < 20
        || u32::from_le_bytes(buffer[0..4].try_into().unwrap()) != IO_REPARSE_TAG_SYMLINK
    {
        return Err(FspError::NTSTATUS(STATUS_NOT_SUPPORTED.0));
    }
    let offset = u16::from_le_bytes(buffer[12..14].try_into().unwrap()) as usize;
    let length = u16::from_le_bytes(buffer[14..16].try_into().unwrap()) as usize;
    let start = 20 + offset;
    let end = start.saturating_add(length);
    if end > buffer.len() || length % 2 != 0 {
        return Err(FspError::NTSTATUS(STATUS_INVALID_PARAMETER.0));
    }
    let wide = buffer[start..end]
        .chunks_exact(2)
        .map(|bytes| u16::from_le_bytes([bytes[0], bytes[1]]))
        .collect::<Vec<_>>();
    Ok(String::from_utf16_lossy(&wide).replace('\\', "/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn access_modes_match_windows_rights() {
        assert!(matches!(access_mode(0), AfcFopenMode::RdOnly));
        assert!(matches!(access_mode(FILE_WRITE_DATA), AfcFopenMode::Rw));
        assert!(matches!(
            access_mode(FILE_APPEND_DATA),
            AfcFopenMode::RdAppend
        ));
    }

    #[test]
    fn directory_marker_advances_past_the_last_returned_entry() {
        let info = RemoteFileInfo {
            kind: "S_IFDIR".into(),
            ..RemoteFileInfo::default()
        };
        let entries = ["alpha", "beta", "gamma"]
            .into_iter()
            .map(|name| DirectoryEntry {
                name: name.to_owned(),
                info: info.clone(),
            })
            .collect::<Vec<_>>();

        assert_eq!(directory_start(&entries, None), 0);
        assert_eq!(directory_start(&entries, Some("alpha")), 1);
        assert_eq!(directory_start(&entries, Some("beta")), 2);
        assert_eq!(directory_start(&entries, Some("gamma")), entries.len());
        assert_eq!(directory_start(&entries, Some("alpine")), 1);
    }

    #[test]
    fn timestamps_round_trip_at_afc_precision() {
        let value = 1_700_000_000_123_456_700i64;
        let windows = unix_nanos_to_windows_time(value);
        assert_eq!(windows_time_to_unix_nanos(windows), value as u64);
    }

    #[test]
    fn symlink_reparse_round_trip() {
        let mut data = vec![0; 1024];
        let size = write_symlink_reparse("../Documents/file", &mut data).unwrap() as usize;
        assert_eq!(
            parse_symlink_reparse(&data[..size]).unwrap(),
            "../Documents/file"
        );
    }

    #[test]
    fn maps_common_afc_failures_to_ntstatus() {
        assert_eq!(
            map_idevice_error(IdeviceError::Afc(AfcError::ObjectNotFound)).to_ntstatus(),
            STATUS_NOT_FOUND.0
        );
        assert_eq!(
            map_idevice_error(IdeviceError::Afc(AfcError::PermDenied)).to_ntstatus(),
            STATUS_ACCESS_DENIED.0
        );
        assert_eq!(
            map_idevice_error(IdeviceError::Afc(AfcError::NoSpaceLeft)).to_ntstatus(),
            STATUS_DISK_FULL.0
        );
    }

    #[test]
    fn converts_afc_metadata_for_windows() {
        let remote = RemoteFileInfo {
            size: 7,
            blocks: 2,
            birthtime_ns: 1_700_000_000_000_000_000,
            mtime_ns: 1_700_000_001_000_000_000,
            kind: "S_IFDIR".into(),
            link_target: None,
        };
        let converted = file_info(&remote);
        assert_eq!(converted.file_attributes, FILE_ATTRIBUTE_DIRECTORY);
        assert_eq!(converted.file_size, 7);
        assert_eq!(converted.allocation_size, 8192);
        assert!(converted.last_write_time > converted.creation_time);
    }
}
