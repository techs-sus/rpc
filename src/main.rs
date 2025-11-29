fn main() -> color_eyre::Result<()> {
	smol::block_on(async {
		color_eyre::install()?;

		let mut server = rpc::Server::init_with_fishstrap();

		server.wait_for_init();

		server.send(b"Hello world!".to_vec()).await?;
		server.send(b"Hello world! 2".to_vec()).await?;

		while let Ok((packet_id, data)) = server.recv_async().await {
			println!("{packet_id} -> {:?}", str::from_utf8(&data));
			server.send(data).await?;
		}
		Ok(())
	})
}
