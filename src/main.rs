fn main() -> color_eyre::Result<()> {
	color_eyre::install()?;

	let mut server = rpc::Server::init_with_fishstrap();

	server.wait_for_init();

	server.send(b"Hello world!".to_vec())?;
	server.send(b"Hello world! 2".to_vec())?;

	while let Ok((packet_id, data)) = server.recv() {
		println!("{packet_id} -> {:?}", str::from_utf8(&data));
		server.send(data)?;
	}

	Ok(())
}
