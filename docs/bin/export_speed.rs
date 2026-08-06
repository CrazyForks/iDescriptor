// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::{
    env,
    net::IpAddr,
    path::{Path, PathBuf},
    time::Instant,
};

use idevice::{
    IdeviceService,
    afc::{AfcClient, opcode::AfcFopenMode},
    heartbeat,
    pairing_file::PairingFile,
    provider::{IdeviceProvider, TcpProvider},
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection},
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::task::JoinHandle;

const APP_LABEL: &str = "export-speed";
const OUTPUT_DIR: &str = "./export-test";
const CHUNK_SIZES: &[usize] = &[
    4 * 1024,
    16 * 1024,
    64 * 1024,
    256 * 1024,
    1024 * 1024,
    4 * 1024 * 1024,
];

#[tokio::main]
async fn main() {
    let result = run().await;

    if let Err(err) = tokio::fs::remove_dir_all(OUTPUT_DIR).await {
        if err.kind() != std::io::ErrorKind::NotFound {
            eprintln!("warning: failed to remove {OUTPUT_DIR}: {err}");
        }
    }

    if let Err(err) = result {
        eprintln!("{err:?}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse()?;

    cleanup_output_dir().await?;
    tokio::fs::create_dir_all(OUTPUT_DIR).await?;

    let provider = build_provider(&args).await?;
    let _heartbeat_task = if args.wireless {
        Some(spawn_wireless_heartbeat(provider.as_ref()).await?)
    } else {
        None
    };

    println!("remote path: {}", args.remote_path);
    println!(
        "transport: {}",
        if args.wireless { "wireless" } else { "wired" }
    );
    if let Some(udid) = &args.udid {
        println!("udid: {udid}");
    }
    println!();
    println!(
        "{:>12} {:>14} {:>12} {:>14}",
        "chunk", "bytes", "seconds", "MiB/s"
    );

    for &chunk_size in CHUNK_SIZES {
        let output_path = output_path_for(&args.remote_path, chunk_size);
        let stats = export_once(
            provider.as_ref(),
            &args.remote_path,
            &output_path,
            chunk_size,
        )
        .await?;

        let mib = stats.bytes as f64 / 1024.0 / 1024.0;
        let mib_per_sec = if stats.seconds > 0.0 {
            mib / stats.seconds
        } else {
            0.0
        };

        println!(
            "{:>12} {:>14} {:>12.3} {:>14.2}",
            format_bytes(chunk_size),
            stats.bytes,
            stats.seconds,
            mib_per_sec
        );

        if let Err(err) = tokio::fs::remove_file(&output_path).await {
            eprintln!(
                "warning: failed to remove {}: {err}",
                output_path.to_string_lossy()
            );
        }
    }

    Ok(())
}

async fn spawn_wireless_heartbeat(
    provider: &dyn IdeviceProvider,
) -> Result<JoinHandle<()>, Box<dyn std::error::Error>> {
    let mut heartbeat = heartbeat::HeartbeatClient::connect(provider).await?;

    Ok(tokio::spawn(async move {
        let mut interval = 15_u64;
        let mut fails = 0_u8;

        loop {
            match heartbeat.get_marco(interval).await {
                Ok(next) => {
                    interval = next;
                    fails = 0;
                }
                Err(err) => {
                    fails += 1;
                    eprintln!("warning: heartbeat get_marco failed ({fails}/3): {err:?}");
                    if fails >= 3 {
                        break;
                    }
                    continue;
                }
            }

            if let Err(err) = heartbeat.send_polo().await {
                fails += 1;
                eprintln!("warning: heartbeat send_polo failed ({fails}/3): {err:?}");
                if fails >= 3 {
                    break;
                }
                continue;
            }

            interval += 5;
        }

        eprintln!("warning: wireless heartbeat stopped");
    }))
}

async fn cleanup_output_dir() -> Result<(), std::io::Error> {
    match tokio::fs::remove_dir_all(OUTPUT_DIR).await {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err),
    }
}

async fn build_provider(
    args: &Args,
) -> Result<Box<dyn IdeviceProvider>, Box<dyn std::error::Error>> {
    if args.wireless {
        let pairing_path = args
            .pairing_file_path
            .as_ref()
            .ok_or("wireless mode requires a pairing file path")?;
        let ip = args
            .device_ip
            .as_ref()
            .ok_or("wireless mode requires a device IP")?
            .parse::<IpAddr>()?;
        let pairing_file = PairingFile::read_from_file(pairing_path)?;
        if let (Some(expected_udid), Some(pairing_udid)) = (&args.udid, &pairing_file.udid) {
            if pairing_udid != expected_udid {
                return Err(format!(
                    "pairing file UDID {pairing_udid} does not match requested UDID {expected_udid}"
                )
                .into());
            }
        }

        return Ok(Box::new(TcpProvider {
            addr: ip,
            pairing_file,
            label: APP_LABEL.to_string(),
            scope_id: None,
        }));
    }

    let mut usbmuxd = UsbmuxdConnection::default().await?;
    let device = usbmuxd
        .get_devices()
        .await?
        .into_iter()
        .find(|device| {
            device.connection_type == Connection::Usb
                && args
                    .udid
                    .as_ref()
                    .is_none_or(|udid| device.udid == *udid)
        })
        .ok_or_else(|| match &args.udid {
            Some(udid) => format!("no wired USB device found for UDID {udid}"),
            None => "no wired USB device found".to_string(),
        })?;

    Ok(Box::new(
        device.to_provider(UsbmuxdAddr::default(), APP_LABEL),
    ))
}

async fn export_once(
    provider: &dyn IdeviceProvider,
    remote_path: &str,
    output_path: &Path,
    chunk_size: usize,
) -> Result<ExportStats, Box<dyn std::error::Error>> {
    let mut afc = AfcClient::connect(provider).await?;
    let info = afc.get_file_info(remote_path.to_string()).await?;
    let expected_size = info.size as u64;
    let mut remote = afc.open(remote_path, AfcFopenMode::RdOnly).await?;
    let mut local = tokio::fs::File::create(output_path).await?;
    let mut buffer = vec![0; chunk_size];
    let mut bytes = 0_u64;

    let start = Instant::now();
    loop {
        let read = remote.read(&mut buffer).await?;
        if read == 0 {
            break;
        }

        local.write_all(&buffer[..read]).await?;
        bytes += read as u64;
    }

    local.flush().await?;
    remote.close().await?;

    if expected_size != bytes {
        return Err(format!("expected {expected_size} bytes but exported {bytes} bytes").into());
    }

    Ok(ExportStats {
        bytes,
        seconds: start.elapsed().as_secs_f64(),
    })
}

fn output_path_for(remote_path: &str, chunk_size: usize) -> PathBuf {
    let file_name = Path::new(remote_path)
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("exported-file");

    Path::new(OUTPUT_DIR).join(format!("{chunk_size}-{file_name}"))
}

fn format_bytes(bytes: usize) -> String {
    if bytes >= 1024 * 1024 {
        format!("{} MiB", bytes / 1024 / 1024)
    } else {
        format!("{} KiB", bytes / 1024)
    }
}

struct Args {
    remote_path: String,
    wireless: bool,
    pairing_file_path: Option<String>,
    device_ip: Option<String>,
    udid: Option<String>,
}

impl Args {
    fn parse() -> Result<Self, String> {
        let args = env::args().collect::<Vec<_>>();
        if args.len() < 3 {
            return Err(Self::usage(&args[0]));
        }

        let wireless = parse_bool(&args[2])?;
        if wireless && !(args.len() == 5 || args.len() == 6) {
            return Err(Self::usage(&args[0]));
        }
        if !wireless && !(args.len() == 3 || args.len() == 4) {
            return Err(Self::usage(&args[0]));
        }

        Ok(Self {
            remote_path: args[1].clone(),
            wireless,
            pairing_file_path: args.get(3).cloned(),
            device_ip: args.get(4).cloned(),
            udid: args.get(if wireless { 5 } else { 3 }).cloned(),
        })
    }

    fn usage(bin: &str) -> String {
        format!(
            "usage:\n  {bin} <device-path> false [udid]\n  {bin} <device-path> true <pairing-file-path> <device-ip> [udid]"
        )
    }
}

fn parse_bool(value: &str) -> Result<bool, String> {
    match value.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "wireless" => Ok(true),
        "false" | "0" | "no" | "wired" => Ok(false),
        _ => Err(format!(
            "invalid wireless flag '{value}', expected true/false"
        )),
    }
}

struct ExportStats {
    bytes: u64,
    seconds: f64,
}
