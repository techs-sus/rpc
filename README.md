# rpc

originally discovered by [bainchild](https://github.com/bainchild) in <https://github.com/bainchild/rpc2-rs>

## Usage

```luau
local RPC = require("@pkg/rpc")

Module.init(function(packetId: number, data: buffer)
	print(`{packetId} -> {buffer.tostring(data)}`)
end)

-- This yields until the Rust side sends an Acknowledgement automatically
Module.send(buffer.fromstring("Hello rpc!"))

while task.wait(1) do
	-- This yields until the Rust side sends an Acknowledgement automatically
	Module.send(buffer.fromstring("Hello rpc! @ " .. os.clock()))
end
```

### Drawbacks

- cannot read faster than 1.25-1.5 seconds in loop
- rust side is heavily overengineered
- probably uses too much memory
