use crate::{RUNTIME, qt_threading::QtThreading};
use anyhow::{Context, Result, anyhow, bail};
use idevice::{
    ReadWrite,
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdDevice},
};
use log::{debug, error, info, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use ssh2::Session;
use std::{
    io::{ErrorKind, Read, Write},
    net::{SocketAddr, TcpStream},
    sync::mpsc,
    thread,
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    sync::oneshot,
};

const DEVICE_SSH_PORT: u16 = 22;
const FORWARD_BUFFER_SIZE: usize = 32768;

struct TerminalSession {
    session_id: String,
    input_tx: mpsc::Sender<Vec<u8>>,
    stop_tx: Option<oneshot::Sender<()>>,
}

impl Drop for TerminalSession {
    fn drop(&mut self) {
        let _ = self.input_tx.send(Vec::new());
        if let Some(stop_tx) = self.stop_tx.take() {
            let _ = stop_tx.send(());
        }
    }
}

#[derive(QObject, Default, QtThreading)]
pub struct Jailbroken {
    base: qt_base_class!(trait QObject),
    connect_ssh: qt_method!(
        fn(
            &mut self,
            session_id: QString,
            connection_type: QString,
            device_udid: QString,
            host_address: QString,
            port: i32,
            password: QString,
        )
    ),
    send_input: qt_method!(fn(&mut self, session_id: QString, text: QString)),
    disconnect_session: qt_method!(fn(&mut self, session_id: QString)),
    shutdown: qt_method!(fn(&mut self)),
    output_received: qt_signal!(session_id: QString, text: QString),
    connection_state_changed: qt_signal!(session_id: QString, state: QString, message: QString),
    session: Option<TerminalSession>,
}

impl Jailbroken {
    fn connect_ssh(
        &mut self,
        session_id: QString,
        connection_type: QString,
        device_udid: QString,
        host_address: QString,
        port: i32,
        password: QString,
    ) {
        let session_id = session_id.to_string();
        if session_id.is_empty() {
            return;
        }

        if self.session.is_some() {
            error!(
                "refusing to create SSH session {session_id}: backend already has an active session"
            );
            return;
        }

        let connection_type = connection_type.to_string();
        let device_udid = device_udid.to_string();
        let host_address = host_address.to_string();
        let port = if port > 0 {
            port as u16
        } else {
            DEVICE_SSH_PORT
        };
        let password = password.to_string();

        let (input_tx, input_rx) = mpsc::channel::<Vec<u8>>();
        let q_thread = self.qt_thread();
        let q_thread_for_error = self.qt_thread();
        let session_id_for_error = session_id.clone();

        self.emit_state(&session_id, "loading", "Connecting to SSH server...");

        if connection_type == "wired" {
            let session_id_for_async = session_id.clone();
            self.session = Some(TerminalSession {
                session_id: session_id.clone(),
                input_tx,
                stop_tx: None,
            });

            RUNTIME.spawn(async move {
                match start_wired_forward(device_udid.clone()).await {
                    Ok((local_port, stop_tx)) => {
                        let session_id_for_store = session_id_for_async.clone();
                        let session_id_for_worker = session_id_for_async.clone();

                        q_thread.queue(move |backend| {
                            if let Some(session) = backend.session.as_mut()
                                && session.session_id == session_id_for_store
                            {
                                session.stop_tx = Some(stop_tx);

                                spawn_ssh_worker(
                                    backend.qt_thread(),
                                    session_id_for_worker,
                                    "127.0.0.1".to_string(),
                                    local_port,
                                    password,
                                    input_rx,
                                );
                            } else {
                                debug!(
                                    "wired SSH session {session_id_for_store} was closed before tunnel startup completed"
                                );
                                let _ = stop_tx.send(());
                            }
                        });
                    }
                    Err(err) => {
                        error!("failed to start wired SSH tunnel: {err:#}");
                        q_thread_for_error.queue(move |backend| {
                            backend.disconnect_by_id(&session_id_for_error);
                            backend.emit_state(
                                &session_id_for_error,
                                "error",
                                &format!("Failed to start USB tunnel: {err:#}"),
                            );
                        });
                    }
                }
            });
        } else {
            self.session = Some(TerminalSession {
                session_id: session_id.clone(),
                input_tx,
                stop_tx: None,
            });

            spawn_ssh_worker(q_thread, session_id, host_address, port, password, input_rx);
        }
    }

    fn send_input(&mut self, session_id: QString, text: QString) {
        let session_id = session_id.to_string();
        let text = text.to_string();
        if let Some(session) = self.session.as_ref()
            && session.session_id == session_id
        {
            if let Err(err) = session.input_tx.send(text.into_bytes()) {
                warn!("failed to queue SSH input for {session_id}: {err}");
            }
        } else {
            warn!("ignoring SSH input for inactive session {session_id}");
        }
    }

    fn disconnect_session(&mut self, session_id: QString) {
        self.disconnect_by_id(&session_id.to_string());
    }

    fn shutdown(&mut self) {
        if let Some(session) = self.session.take() {
            info!("shutting down SSH session {}", session.session_id);
        }
    }

    fn disconnect_by_id(&mut self, session_id: &str) {
        if self
            .session
            .as_ref()
            .is_some_and(|session| session.session_id == session_id)
        {
            self.session.take();
            debug!("disconnected SSH session {session_id}");
        }
    }

    fn emit_output(&mut self, session_id: &str, text: &str) {
        self.output_received(QString::from(session_id), QString::from(text));
    }

    fn emit_state(&mut self, session_id: &str, state: &str, message: &str) {
        self.connection_state_changed(
            QString::from(session_id),
            QString::from(state),
            QString::from(message),
        );
    }
}

impl Drop for Jailbroken {
    fn drop(&mut self) {
        if let Some(session) = self.session.take() {
            info!(
                "dropping Jailbroken backend with active SSH session {}",
                session.session_id
            );
        }
    }
}

fn spawn_ssh_worker(
    q_thread: crate::qt_threading::QtThread<Jailbroken>,
    session_id: String,
    host: String,
    port: u16,
    password: String,
    input_rx: mpsc::Receiver<Vec<u8>>,
) {
    thread::spawn(move || {
        let result = run_ssh_session(&q_thread, &session_id, &host, port, &password, input_rx);
        if let Err(err) = result {
            error!("SSH session failed for {session_id}: {err:#}");
            let message = format!("{err:#}");
            q_thread.queue(move |backend| {
                backend.disconnect_by_id(&session_id);
                backend.emit_state(&session_id, "error", &message);
            });
        }
    });
}

fn run_ssh_session(
    q_thread: &crate::qt_threading::QtThread<Jailbroken>,
    session_id: &str,
    host: &str,
    port: u16,
    password: &str,
    input_rx: mpsc::Receiver<Vec<u8>>,
) -> Result<()> {
    let address = format!("{host}:{port}");
    info!("connecting SSH session {session_id} to {address}");

    let tcp =
        TcpStream::connect(&address).with_context(|| format!("Failed to connect to {address}"))?;
    tcp.set_read_timeout(Some(Duration::from_millis(80)))?;
    tcp.set_write_timeout(Some(Duration::from_secs(5)))?;

    let mut session = Session::new().context("Failed to create SSH session")?;
    session.set_tcp_stream(tcp);
    session.handshake().context("SSH handshake failed")?;
    session
        .userauth_password("root", password)
        .context("SSH authentication failed")?;

    if !session.authenticated() {
        bail!("SSH authentication failed");
    }

    let mut channel = session
        .channel_session()
        .context("Failed to create SSH channel")?;
    channel
        .request_pty("xterm", None, Some((80, 24, 0, 0)))
        .context("Failed to request SSH PTY")?;
    channel.shell().context("Failed to start SSH shell")?;
    session.set_blocking(false);

    let connected_id = session_id.to_string();
    q_thread.queue(move |backend| {
        backend.emit_state(&connected_id, "connected", "SSH connected");
    });

    let mut buffer = [0u8; 4096];
    loop {
        while let Ok(input) = input_rx.try_recv() {
            if input.is_empty() {
                let _ = channel.close();
                return Ok(());
            }
            channel
                .write_all(&input)
                .context("Failed to write SSH input")?;
            channel.flush().ok();
        }

        match channel.read(&mut buffer) {
            Ok(0) => {
                if channel.eof() {
                    break;
                }
            }
            Ok(n) => {
                let text = String::from_utf8_lossy(&buffer[..n]).to_string();
                let output_id = session_id.to_string();
                q_thread.queue(move |backend| {
                    backend.emit_output(&output_id, &text);
                });
            }
            Err(err) if err.kind() == ErrorKind::WouldBlock => {}
            Err(err) => return Err(err).context("Failed to read SSH output"),
        }

        if channel.eof() {
            break;
        }

        thread::sleep(Duration::from_millis(20));
    }

    let closed_id = session_id.to_string();
    q_thread.queue(move |backend| {
        backend.disconnect_by_id(&closed_id);
        backend.emit_state(&closed_id, "closed", "SSH connection closed");
    });

    Ok(())
}

async fn start_wired_forward(udid: String) -> Result<(u16, oneshot::Sender<()>)> {
    if udid.is_empty() {
        bail!("Missing device UDID for wired SSH tunnel");
    }

    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .context("Failed to bind local SSH tunnel")?;
    let local_port = listener.local_addr()?.port();
    let (stop_tx, stop_rx) = oneshot::channel();

    RUNTIME.spawn(async move {
        if let Err(err) = forward_wired_ssh(listener, udid, stop_rx).await {
            error!("wired SSH forwarder stopped with error: {err:#}");
        }
    });

    debug!("wired SSH tunnel listening on 127.0.0.1:{local_port}");
    Ok((local_port, stop_tx))
}

async fn forward_wired_ssh(
    listener: TcpListener,
    udid: String,
    mut stop_rx: oneshot::Receiver<()>,
) -> Result<()> {
    loop {
        tokio::select! {
            _ = &mut stop_rx => {
                debug!("wired SSH forwarder stop requested");
                return Ok(());
            }
            accepted = listener.accept() => {
                let (client_stream, client_addr) = accepted.context("Failed to accept local SSH tunnel connection")?;
                let udid = udid.clone();
                RUNTIME.spawn(async move {
                    if let Err(err) = handle_forward_client(client_stream, client_addr, udid).await {
                        error!("SSH tunnel client failed: {err:#}");
                    }
                });
            }
        }
    }
}

async fn handle_forward_client(
    mut client_stream: tokio::net::TcpStream,
    client_addr: SocketAddr,
    udid: String,
) -> Result<()> {
    debug!("accepted SSH tunnel client from {client_addr}");
    let usbmuxd_addr = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let device = get_wired_device(&usbmuxd_addr, &udid).await?;
    let device_stream = connect_to_device(&device, DEVICE_SSH_PORT, &usbmuxd_addr).await?;

    let (mut client_read, mut client_write) = client_stream.split();
    let (mut device_read, mut device_write) = tokio::io::split(device_stream);

    let client_to_device = async {
        let mut buffer = vec![0u8; FORWARD_BUFFER_SIZE];
        loop {
            let n = client_read.read(&mut buffer).await?;
            if n == 0 {
                break;
            }
            device_write.write_all(&buffer[..n]).await?;
        }
        anyhow::Ok(())
    };

    let device_to_client = async {
        let mut buffer = vec![0u8; FORWARD_BUFFER_SIZE];
        loop {
            let n = device_read.read(&mut buffer).await?;
            if n == 0 {
                break;
            }
            client_write.write_all(&buffer[..n]).await?;
        }
        anyhow::Ok(())
    };

    tokio::select! {
        result = client_to_device => result?,
        result = device_to_client => result?,
    }

    debug!("SSH tunnel client {client_addr} closed");
    Ok(())
}

async fn get_wired_device(usbmuxd_addr: &UsbmuxdAddr, udid: &str) -> Result<UsbmuxdDevice> {
    let mut usbmuxd = usbmuxd_addr.connect(1).await?;
    let device = usbmuxd.get_device(udid).await?;
    if device.connection_type != Connection::Usb {
        bail!("Selected device is not connected over USB");
    }
    Ok(device)
}

async fn connect_to_device(
    device: &UsbmuxdDevice,
    port: u16,
    usbmuxd_addr: &UsbmuxdAddr,
) -> Result<Box<dyn ReadWrite>> {
    match &device.connection_type {
        Connection::Usb => {
            let conn = usbmuxd_addr.connect(device.device_id).await?;
            let idevice = conn
                .connect_to_device(device.device_id, port, "idescriptor-ssh")
                .await?;
            idevice
                .get_socket()
                .ok_or_else(|| anyhow!("Unable to get device socket"))
        }
        // This should never happen
        // SSH can connect over network already, no need to forward
        // if the connection is wireless we should error out
        Connection::Network(ip_addr) => {
            return Err(anyhow!("Device is connected over network ({ip_addr}), "));
        }
        Connection::Unknown(desc) => Err(anyhow!("Unsupported connection type: {desc}")),
    }
}
