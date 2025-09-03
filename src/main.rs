fn main() -> color_eyre::Result<()> {
	color_eyre::install()?;

	let mut server = rpc::Server::init_with_fishstrap();

	while !server.is_initialized() {
		std::thread::yield_now(); // TODO: use a condvar and make create methods also yield with it 
	}

	server.send(b"Hello world!".to_vec())?;
	server.send(b"Hello world! 2".to_vec())?;

	while let Ok((packet_id, data)) = server.recv() {
		println!("{packet_id} -> {:?}", str::from_utf8(&data));
		server.send(data)?;
	}

	Ok(())
}
