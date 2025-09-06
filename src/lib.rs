use arc_swap::ArcSwap;
use base64::{Engine, prelude::BASE64_STANDARD};
use chrono::Utc;
use regex::Regex;
use serde_json::json;
use std::{
	ffi::OsStr,
	fs::File,
	io::{BufRead, BufReader},
	path::PathBuf,
	sync::{Arc, Condvar, LazyLock, Mutex, mpsc},
	thread::JoinHandle,
	time::Duration,
};

use thiserror::Error;

#[derive(Error, Debug)]
pub enum RpcError {
	#[error("io error: {0}")]
	Io(#[from] std::io::Error),

	#[error("got mpsc receive error")]
	MpscRecvError(#[from] mpsc::RecvError),

	#[error("got loole receive error")]
	LooleRecvError(#[from] loole::RecvError),

	#[error("got loole send error")]
	LooleSendError(#[from] loole::SendError<ClientboundPacket>),

	#[error("not connected")]
	NotConnected,
}

static LOCAL_APP_DATA: LazyLock<String> = LazyLock::new(|| {
	std::env::var("localappdata").expect("localappdata environment variable should exist")
});

pub struct Server {
	initialized_condvar: Arc<(Mutex<bool>, Condvar)>,

	log_watcher_join_handle: JoinHandle<()>,
	connection_handler_handle: JoinHandle<()>,
	clientbound_packet_handler_handle: JoinHandle<()>,

	incoming_serverbound_packets: loole::Receiver<(u32, Vec<u8>)>,
	serverbound_packet_acknowledgements: Arc<papaya::HashSet<u32>>,

	clientbound_packet_queue: loole::Sender<ClientboundPacket>,

	current_clientbound_packet_id: u32,
}

#[repr(u8)]
enum ServerboundPacketType {
	Init = 0,
	Acknowledge = 1,
	Data = 2,
}

enum ServerboundPacket {
	/// Initializes the JSON communication with a cachebuster.
	Init { starting_cachebuster: String },

	/// Acknowledge a [`ClientboundPacket::Data`].
	Acknowledge(u32),

	/// Acknowledged by a [`ClientboundPacket::Acknowledge`].
	Data(u32, Vec<u8>),
}

impl ServerboundPacket {
	fn deserialize(data: &[u8]) -> Option<Self> {
		const INIT: u8 = ServerboundPacketType::Init as u8;
		const ACK: u8 = ServerboundPacketType::Acknowledge as u8;
		const DATA: u8 = ServerboundPacketType::Data as u8;

		let packet_type = u8::from_le_bytes(data[0..1].try_into().ok()?);

		match packet_type {
			INIT => Some(Self::Init {
				starting_cachebuster: String::from_utf8(data[1..].to_vec()).ok()?,
			}),

			ACK => Some(Self::Acknowledge(u32::from_le_bytes(
				data[1..5].try_into().ok()?,
			))),

			DATA => {
				let id = u32::from_le_bytes(data[1..5].try_into().ok()?);
				Some(Self::Data(id, data[5..].to_vec()))
			}

			_ => None,
		}
	}

	fn parse_from_log_entry(entry: &str) -> Option<Self> {
		if let Some(stripped) = entry.strip_prefix("[github:techs-sus/rpc] ")
			&& let Ok(data) = BASE64_STANDARD.decode(stripped)
		{
			return Self::deserialize(&data);
		}

		None
	}
}

pub enum ClientboundPacket {
	/// Acknowledge a [`ServerboundPacket::Data`].
	Acknowledge(u32),
	/// Acknowledged by a [`ServerboundPacket::Acknowledge`].
	Data(u32, Vec<u8>),
}

impl ClientboundPacket {
	const fn get_packet_type(&self) -> u8 {
		match self {
			ClientboundPacket::Acknowledge(..) => 1,
			ClientboundPacket::Data(..) => 2,
		}
	}

	fn serialize(&self) -> Vec<u8> {
		let mut vector = Vec::with_capacity(5);
		vector.push(self.get_packet_type());

		match self {
			ClientboundPacket::Acknowledge(packet_id) => {
				vector.extend_from_slice(&packet_id.to_le_bytes());
			}

			ClientboundPacket::Data(packet_id, data) => {
				vector.extend_from_slice(&packet_id.to_le_bytes());
				vector.extend_from_slice(data);
			}
		}

		vector
	}
}

fn spawn_log_watcher(log_file: PathBuf, tx: loole::Sender<ServerboundPacket>) -> JoinHandle<()> {
	let regex = Regex::new(r"(?m)(\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[1-2]\d|3[0-1])T(?:[0-1]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+|)(?:Z|(?:\+|\-)(?:\d{2}):?(?:\d{2}))).+(\[FLog::Output\]) (.+)").unwrap();

	std::thread::spawn(move || {
		let file = File::open(log_file).expect("failed opening log file on thread");
		let mut reader = BufReader::new(file);
		let mut buf = String::new();

		loop {
			let log = reader.read_line(&mut buf);

			if log.is_err() {
				std::thread::sleep(Duration::from_millis(500));
				continue;
			}

			if buf.contains("[FLog::Output]") 
						&& let Some(captures) = regex.captures(&buf)
						&& let Some(timestamp) = captures.get(1).map(|m| m.as_str())
						&& let Ok(parsed) = chrono::DateTime::parse_from_rfc3339(timestamp).map(|dt| dt.to_utc())
						&& Utc::now().signed_duration_since(parsed).abs().num_seconds() < 10

						/* trim_end() to prevent \r from showing up on Windows
							-> see https://github.com/SovereignSatellite/Spider/commit/3a14a3b6d6bf97b672a795a8306e57532b0d87b4
						*/
						&& let Some(output_data) = captures.get(3).map(|m| m.as_str().trim_end())
						&& let Some(packet) = ServerboundPacket::parse_from_log_entry(output_data)
			{
				tx.send(packet)
					.expect("watcher thread failed sending packet");
			}

			buf.clear();
		}
	})
}

fn spawn_connection_handler(
	rx: loole::Receiver<ServerboundPacket>,
	received_packet_data: loole::Sender<(u32, Vec<u8>)>,
	serverbound_packet_acknowledgements: Arc<papaya::HashSet<u32>>,
	cachebuster: Arc<ArcSwap<String>>,
	initialized: Arc<(Mutex<bool>, Condvar)>,
	clientbound_packet_sender: loole::Sender<ClientboundPacket>,
) -> JoinHandle<()> {
	std::thread::spawn(move || {
		while let Ok(packet) = rx.recv() {
			match packet {
				ServerboundPacket::Init {
					starting_cachebuster,
				} => {
					cachebuster.swap(Arc::new(starting_cachebuster));

					*initialized.0.lock().unwrap() = true;
					initialized.1.notify_all();
				}

				ServerboundPacket::Acknowledge(id) => {
					serverbound_packet_acknowledgements.pin().insert(id);
				}

				ServerboundPacket::Data(id, data) => {
					received_packet_data.send((id, data)).ok(); // TODO: This should never be an Err; so maybe unreachable!()?
					clientbound_packet_sender
						.send(ClientboundPacket::Acknowledge(id))
						.ok();
				}
			}
		}
	})
}

fn spawn_packet_sender(
	receiver: loole::Receiver<ClientboundPacket>,
	rpc_data_directory: PathBuf,
	cachebuster_arc_swap: Arc<ArcSwap<String>>,
) -> JoinHandle<()> {
	std::thread::spawn(move || {
		while let Ok(packet) = receiver.recv() {
			let cachebuster = cachebuster_arc_swap.load();

			let path = rpc_data_directory.join(format!("{cachebuster}.json"));
			let backup_path =
				rpc_data_directory.join(format!("{}.json", get_backup_cachebuster(&cachebuster)));

			let contents = serialize_data_to_font_json(&BASE64_STANDARD.encode(packet.serialize()));

			std::fs::write(&path, &contents).expect("failed write in packet sender thread");
			std::fs::write(&backup_path, contents).expect("failed backup write in packet sender thread");

			cachebuster_arc_swap.store(Arc::new(get_next_cachebuster(&cachebuster)));
		}
	})
}

fn init_with_version_path(version_path: PathBuf) -> Server {
	let logs_directory = PathBuf::from(LOCAL_APP_DATA.as_str())
		.join("Roblox")
		.join("logs");

	let mut vec = std::fs::read_dir(&logs_directory)
		.expect("failed reading log directory")
		.filter_map(|res| {
			res.ok().and_then(|entry| {
				entry.metadata().ok().and_then(|meta| {
					if meta.is_dir() || entry.path().extension().and_then(OsStr::to_str) != Some("log") {
						None
					} else {
						meta.modified().ok().map(|time| (entry, time))
					}
				})
			})
		})
		.collect::<Vec<_>>();

	// get latest log file
	vec.sort_by(|(_, time), (_, time2)| time2.cmp(time));

	let log_file = vec
		.first()
		.expect("failed finding most recently modified log file")
		.0
		.path();

	let rpc_data_directory = version_path.join("content").join("fonts").join("rpc");

	std::fs::remove_dir_all(&rpc_data_directory).ok();
	std::fs::create_dir(&rpc_data_directory).expect("failed creating directory");

	std::fs::write(
		rpc_data_directory.join("init.json"),
		serialize_data_to_font_json("blah blah"),
	)
	.expect("failed writing rpc/init.json");

	let (tx, rx) = loole::unbounded();
	let log_watcher_join_handle = spawn_log_watcher(log_file, tx);

	let (packet_data_tx, packet_data_rx) = loole::unbounded();
	let serverbound_packet_acknowledgements = Arc::new(papaya::HashSet::new());

	let cachebuster_arc_swap = Arc::new(ArcSwap::new(Arc::new(String::new())));

	let (clientbound_packet_sender, clientbound_packet_receiver) = loole::unbounded();

	let initialized_condvar = Arc::new((Mutex::new(false), Condvar::new()));

	let connection_handler_handle = spawn_connection_handler(
		rx,
		packet_data_tx,
		serverbound_packet_acknowledgements.clone(),
		cachebuster_arc_swap.clone(),
		initialized_condvar.clone(),
		clientbound_packet_sender.clone(),
	);

	let clientbound_packet_handler_handle = spawn_packet_sender(
		clientbound_packet_receiver,
		rpc_data_directory,
		cachebuster_arc_swap,
	);

	Server {
		initialized_condvar,
		log_watcher_join_handle,
		connection_handler_handle,
		clientbound_packet_handler_handle,

		incoming_serverbound_packets: packet_data_rx,
		serverbound_packet_acknowledgements,
		current_clientbound_packet_id: 0,

		clientbound_packet_queue: clientbound_packet_sender,
	}
}

fn serialize_data_to_font_json(data: &str) -> String {
	serde_json::to_string(&json!({
		"name": blake3::hash(data.as_bytes()).to_hex().as_str(),
		"faces": [
			{
				"name": data,
				"weight": 300,
				// "style": "normal",
				// "assetId": "rbxassetid://8075267523"
			},
		]
	}))
	.unwrap()
}

fn get_backup_cachebuster(cachebuster: &str) -> String {
	blake3::hash(format!("{cachebuster}pls give backup").as_bytes())
		.to_hex()
		.as_str()
		.to_string()
}

fn get_next_cachebuster(cachebuster: &str) -> String {
	blake3::hash(format!("{cachebuster}pls give next").as_bytes())
		.to_hex()
		.as_str()
		.to_string()
}

impl Server {
	/// Instantly returns if this [`Server`] is ready, otherwise waits for it to be initialized.
	pub fn wait_for_init(&self) {
		let (lock, condvar) = &*self.initialized_condvar;
		let mut started = lock.lock().unwrap();
		while !*started {
			started = condvar.wait(started).unwrap();
		}
	}

	/// Creates and initializes a RPC server using Roblox version paths deducted from [Fishstrap](https://github.com/fishstrap/fishstrap).
	///
	/// # Panics
	/// This function can panic if [Fishstrap](https://github.com/fishstrap/fishstrap) is not present, or the latest log file cannot be found, etc.
	pub fn init_with_fishstrap() -> Self {
		let directory_path = PathBuf::from(LOCAL_APP_DATA.as_str())
			.join("Fishstrap")
			.join("Versions");

		let entry = std::fs::read_dir(&directory_path)
			.expect("failed reading fishstrap versions directory")
			.next()
			.expect("no version in versions directory")
			.expect("failed reading versions directory entry");

		init_with_version_path(directory_path.join(entry.path()))
	}

	/// Sends a block of data and yields the thread until the data was acknowledged.
	///
	/// # Errors
	/// This function can return an [`Result::Err`] with [`RpcError::NotConnected`] if the startup initialization is not complete.
	pub fn send(&mut self, data: Vec<u8>) -> Result<(), RpcError> {
		if !*self.initialized_condvar.0.lock().unwrap() {
			return Err(RpcError::NotConnected);
		}

		let id = self.current_clientbound_packet_id;

		self
			.clientbound_packet_queue
			.send(ClientboundPacket::Data(id, data))?;

		self.current_clientbound_packet_id += 1;

		loop {
			let pin = self.serverbound_packet_acknowledgements.pin();

			if pin.contains(&id) {
				pin.remove(&id);
				break;
			}

			std::thread::yield_now(); // TODO: use std::sync::Condvar eventually
		}

		Ok(())
	}

	/// Uses [`loole::Receiver::drain`] under the hood.
	///
	/// Drains the remaining packet data sent from the Roblox side.
	pub fn drain(&self) -> loole::Drain<'_, (u32, Vec<u8>)> {
		self.incoming_serverbound_packets.drain()
	}

	/// Uses [`loole::Receiver::iter`] under the hood.
	pub fn iter(&self) -> loole::Iter<'_, (u32, Vec<u8>)> {
		self.incoming_serverbound_packets.iter()
	}

	/// Uses [`loole::Receiver::recv`] under the hood.
	pub fn recv(&self) -> Result<(u32, Vec<u8>), RpcError> {
		Ok(self.incoming_serverbound_packets.recv()?)
	}

	/// Uses [`loole::Receiver::recv_async`] under the hood.
	pub async fn recv_async(&self) -> Result<(u32, Vec<u8>), RpcError> {
		Ok(self.incoming_serverbound_packets.recv_async().await?)
	}
}
