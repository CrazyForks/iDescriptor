use std::collections::HashMap;

use idevice::{
    IdeviceError,
    afc::{
        AfcClient, MAGIC,
        opcode::{AfcFopenMode, AfcOpcode, LinkType},
        packet::{AfcPacket, AfcPacketHeader},
    },
};

pub(crate) const MAX_TRANSFER: usize = 1024 * 1024;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct RemoteFileInfo {
    pub size: u64,
    pub blocks: u64,
    pub birthtime_ns: i64,
    pub mtime_ns: i64,
    pub kind: String,
    pub link_target: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct RemoteDeviceInfo {
    pub model: String,
    pub total_bytes: u64,
    pub free_bytes: u64,
    pub block_size: u64,
}

pub(crate) struct AfcSession {
    client: AfcClient,
    packet_number: u64,
}

impl AfcSession {
    pub fn new(client: AfcClient) -> Self {
        Self {
            client,
            packet_number: 0,
        }
    }

    async fn request(
        &mut self,
        operation: AfcOpcode,
        header_payload: Vec<u8>,
        payload: Vec<u8>,
    ) -> Result<AfcPacket, IdeviceError> {
        let header_payload_len = AfcPacketHeader::LEN + header_payload.len() as u64;
        let packet = AfcPacket {
            header: AfcPacketHeader {
                magic: MAGIC,
                entire_len: header_payload_len + payload.len() as u64,
                header_payload_len,
                packet_num: self.packet_number,
                operation,
            },
            header_payload,
            payload,
        };
        self.packet_number = self.packet_number.wrapping_add(1);
        self.client.send(packet).await?;
        self.client.read().await
    }

    pub async fn list_dir(&mut self, path: &str) -> Result<Vec<String>, IdeviceError> {
        let reply = self
            .request(AfcOpcode::ReadDir, nul_terminated(path), Vec::new())
            .await?;
        Ok(parse_strings(&reply.payload))
    }

    pub async fn get_file_info(&mut self, path: &str) -> Result<RemoteFileInfo, IdeviceError> {
        let reply = self
            .request(AfcOpcode::GetFileInfo, nul_terminated(path), Vec::new())
            .await?;
        let mut values = parse_pairs(&reply.payload)?;
        let link_target = values
            .remove("st_link_target")
            .or_else(|| values.remove("LinkTarget"));
        Ok(RemoteFileInfo {
            size: take_number(&mut values, "st_size")?,
            blocks: take_number(&mut values, "st_blocks")?,
            birthtime_ns: take_signed(&mut values, "st_birthtime")?,
            mtime_ns: take_signed(&mut values, "st_mtime")?,
            kind: take_value(&mut values, "st_ifmt")?,
            link_target,
        })
    }

    pub async fn get_device_info(&mut self) -> Result<RemoteDeviceInfo, IdeviceError> {
        let reply = self
            .request(AfcOpcode::GetDevInfo, Vec::new(), Vec::new())
            .await?;
        let mut values = parse_pairs(&reply.payload)?;
        Ok(RemoteDeviceInfo {
            model: take_value(&mut values, "Model")?,
            total_bytes: take_number(&mut values, "FSTotalBytes")?,
            free_bytes: take_number(&mut values, "FSFreeBytes")?,
            block_size: take_number(&mut values, "FSBlockSize")?,
        })
    }

    pub async fn mkdir(&mut self, path: &str) -> Result<(), IdeviceError> {
        self.request(AfcOpcode::MakeDir, nul_terminated(path), Vec::new())
            .await?;
        Ok(())
    }

    pub async fn remove(&mut self, path: &str) -> Result<(), IdeviceError> {
        self.request(AfcOpcode::RemovePath, nul_terminated(path), Vec::new())
            .await?;
        Ok(())
    }

    pub async fn rename(&mut self, from: &str, to: &str) -> Result<(), IdeviceError> {
        let mut data = nul_terminated(from);
        data.extend(nul_terminated(to));
        self.request(AfcOpcode::RenamePath, data, Vec::new())
            .await?;
        Ok(())
    }

    pub async fn symlink(&mut self, target: &str, link: &str) -> Result<(), IdeviceError> {
        let mut data = (LinkType::Symlink as u64).to_le_bytes().to_vec();
        data.extend(nul_terminated(target));
        data.extend(nul_terminated(link));
        self.request(AfcOpcode::MakeLink, data, Vec::new()).await?;
        Ok(())
    }

    pub async fn set_mtime(&mut self, path: &str, nanoseconds: u64) -> Result<(), IdeviceError> {
        let data = timestamp_path_payload(path, nanoseconds);
        self.request(AfcOpcode::SetFileTime, data, Vec::new())
            .await?;
        Ok(())
    }

    pub async fn open(&mut self, path: &str, mode: AfcFopenMode) -> Result<u64, IdeviceError> {
        let mut data = (mode as u64).to_le_bytes().to_vec();
        data.extend(nul_terminated(path));
        let reply = self.request(AfcOpcode::FileOpen, data, Vec::new()).await?;
        let bytes = reply.header_payload.get(..8).ok_or_else(|| {
            IdeviceError::UnexpectedResponse("AFC FileOpen response is missing a descriptor".into())
        })?;
        Ok(u64::from_le_bytes(bytes.try_into().unwrap()))
    }

    pub async fn close(&mut self, descriptor: u64) -> Result<(), IdeviceError> {
        self.request(
            AfcOpcode::FileClose,
            descriptor.to_le_bytes().to_vec(),
            Vec::new(),
        )
        .await?;
        Ok(())
    }

    pub async fn truncate(&mut self, descriptor: u64, size: u64) -> Result<(), IdeviceError> {
        self.request(
            AfcOpcode::FileSetSize,
            [descriptor.to_le_bytes(), size.to_le_bytes()].concat(),
            Vec::new(),
        )
        .await?;
        Ok(())
    }

    async fn seek(&mut self, descriptor: u64, offset: u64) -> Result<(), IdeviceError> {
        self.request(
            AfcOpcode::FileSeek,
            [
                descriptor.to_le_bytes(),
                0u64.to_le_bytes(),
                (offset as i64).to_le_bytes(),
            ]
            .concat(),
            Vec::new(),
        )
        .await?;
        Ok(())
    }

    pub async fn read_at(
        &mut self,
        descriptor: u64,
        offset: u64,
        length: usize,
    ) -> Result<Vec<u8>, IdeviceError> {
        self.seek(descriptor, offset).await?;
        let mut output = Vec::with_capacity(length);
        for wanted in chunks(length) {
            let reply = self
                .request(
                    AfcOpcode::Read,
                    [descriptor.to_le_bytes(), (wanted as u64).to_le_bytes()].concat(),
                    Vec::new(),
                )
                .await?;
            if reply.payload.is_empty() {
                break;
            }
            let received = reply.payload.len();
            output.extend(reply.payload);
            if received < wanted {
                break;
            }
        }
        Ok(output)
    }

    pub async fn write_at(
        &mut self,
        descriptor: u64,
        offset: u64,
        bytes: &[u8],
    ) -> Result<usize, IdeviceError> {
        self.seek(descriptor, offset).await?;
        for chunk in bytes.chunks(MAX_TRANSFER) {
            self.request(
                AfcOpcode::Write,
                descriptor.to_le_bytes().to_vec(),
                chunk.to_vec(),
            )
            .await?;
        }
        Ok(bytes.len())
    }
}

fn nul_terminated(value: &str) -> Vec<u8> {
    let mut bytes = value.as_bytes().to_vec();
    bytes.push(0);
    bytes
}

fn timestamp_path_payload(path: &str, nanoseconds: u64) -> Vec<u8> {
    let mut data = nanoseconds.to_le_bytes().to_vec();
    data.extend(nul_terminated(path));
    data
}

fn parse_strings(bytes: &[u8]) -> Vec<String> {
    bytes
        .split(|byte| *byte == 0)
        .filter(|value| !value.is_empty())
        .map(|value| String::from_utf8_lossy(value).into_owned())
        .collect()
}

fn parse_pairs(bytes: &[u8]) -> Result<HashMap<String, String>, IdeviceError> {
    let strings = parse_strings(bytes);
    if strings.len() % 2 != 0 {
        return Err(IdeviceError::UnexpectedResponse(
            "AFC returned malformed key/value data".into(),
        ));
    }
    Ok(strings
        .chunks_exact(2)
        .map(|pair| (pair[0].clone(), pair[1].clone()))
        .collect())
}

fn take_value(values: &mut HashMap<String, String>, key: &str) -> Result<String, IdeviceError> {
    values
        .remove(key)
        .ok_or_else(|| IdeviceError::UnexpectedResponse(format!("AFC response is missing {key}")))
}

fn take_number(values: &mut HashMap<String, String>, key: &str) -> Result<u64, IdeviceError> {
    take_value(values, key)?
        .parse()
        .map_err(|_| IdeviceError::UnexpectedResponse(format!("AFC response has an invalid {key}")))
}

fn take_signed(values: &mut HashMap<String, String>, key: &str) -> Result<i64, IdeviceError> {
    take_value(values, key)?
        .parse()
        .map_err(|_| IdeviceError::UnexpectedResponse(format!("AFC response has an invalid {key}")))
}

pub(crate) fn chunks(length: usize) -> impl Iterator<Item = usize> {
    let full = length / MAX_TRANSFER;
    let remainder = length % MAX_TRANSFER;
    (0..full)
        .map(|_| MAX_TRANSFER)
        .chain((remainder != 0).then_some(remainder))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_at_one_megabyte() {
        assert_eq!(chunks(0).collect::<Vec<_>>(), Vec::<usize>::new());
        assert_eq!(chunks(MAX_TRANSFER).collect::<Vec<_>>(), [MAX_TRANSFER]);
        assert_eq!(
            chunks(MAX_TRANSFER * 2 + 7).collect::<Vec<_>>(),
            [MAX_TRANSFER, MAX_TRANSFER, 7]
        );
    }

    #[test]
    fn rejects_malformed_pairs() {
        assert!(parse_pairs(b"key\0value\0orphan\0").is_err());
    }

    #[test]
    fn file_time_payload_matches_afc_layout() {
        let payload = timestamp_path_payload("/DCIM", 42);
        assert_eq!(&payload[..8], &42u64.to_le_bytes());
        assert_eq!(&payload[8..], b"/DCIM\0");
    }
}
