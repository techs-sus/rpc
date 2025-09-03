--!native
--!strict

local TextService = game:GetService("TextService")

local decodeBase64
local encodeBase64
local Blake3 = {}

do
	local PADDING_CHARACTER = 61

	local ALPHABET_LOOKUP = {}
	do
		local Characters = {
			65,
			66,
			67,
			68,
			69,
			70,
			71,
			72,
			73,
			74,
			75,
			76,
			77,
			78,
			79,
			80,
			81,
			82,
			83,
			84,
			85,
			86,
			87,
			88,
			89,
			90,
			97,
			98,
			99,
			100,
			101,
			102,
			103,
			104,
			105,
			106,
			107,
			108,
			109,
			110,
			111,
			112,
			113,
			114,
			115,
			116,
			117,
			118,
			119,
			120,
			121,
			122,
			48,
			49,
			50,
			51,
			52,
			53,
			54,
			55,
			56,
			57,
			43,
			47,
		}

		for Index = 0, 63 do
			ALPHABET_LOOKUP[Index] = Characters[Index + 1]
		end
	end

	local DIRECT_LOOKUP = {}
	do
		for Index = 0, 255 do
			DIRECT_LOOKUP[Index] = ALPHABET_LOOKUP[bit32.band(Index, 63)]
		end
	end

	local DECODE_LOOKUP = {}
	do
		for Index = 0, 255 do
			DECODE_LOOKUP[Index] = 255
		end

		for Index = 65, 90 do
			DECODE_LOOKUP[Index] = Index - 65
		end

		for Index = 97, 122 do
			DECODE_LOOKUP[Index] = Index - 97 + 26
		end

		for Index = 48, 57 do
			DECODE_LOOKUP[Index] = Index - 48 + 52
		end

		DECODE_LOOKUP[43] = 62
		DECODE_LOOKUP[47] = 63
	end

	function encodeBase64(Input: buffer): buffer
		local Padding = PADDING_CHARACTER
		local Lookup = DIRECT_LOOKUP
		local InputLength = buffer.len(Input)
		if InputLength == 0 then
			return buffer.create(0)
		end

		local Chunks = math.ceil(InputLength / 3)
		local OutputLength = Chunks * 4
		local Output = buffer.create(OutputLength)

		local DoubleChunks = math.floor((Chunks - 1) / 2)
		for ChunkIndex = 1, DoubleChunks do
			local InputIndex = (ChunkIndex - 1) * 6
			local OutputIndex = (ChunkIndex - 1) * 8

			local Word1 = bit32.byteswap(buffer.readu32(Input, InputIndex))
			local Octet1_1 = bit32.rshift(Word1, 26)
			local Octet1_2 = bit32.rshift(Word1, 20)
			local Octet1_3 = bit32.rshift(Word1, 14)
			local Octet1_4 = bit32.rshift(Word1, 8)

			local Word2 = bit32.byteswap(buffer.readu32(Input, InputIndex + 3))
			local Octet2_1 = bit32.rshift(Word2, 26)
			local Octet2_2 = bit32.rshift(Word2, 20)
			local Octet2_3 = bit32.rshift(Word2, 14)
			local Octet2_4 = bit32.rshift(Word2, 8)

			buffer.writeu32(
				Output,
				OutputIndex,
				bit32.bor(
					Lookup[bit32.band(Octet1_1, 255)],
					Lookup[bit32.band(Octet1_2, 255)] * 256,
					Lookup[bit32.band(Octet1_3, 255)] * 65536,
					Lookup[bit32.band(Octet1_4, 255)] * 16777216
				)
			)

			buffer.writeu32(
				Output,
				OutputIndex + 4,
				bit32.bor(
					Lookup[bit32.band(Octet2_1, 255)],
					Lookup[bit32.band(Octet2_2, 255)] * 256,
					Lookup[bit32.band(Octet2_3, 255)] * 65536,
					Lookup[bit32.band(Octet2_4, 255)] * 16777216
				)
			)
		end

		local ProcessedChunks = DoubleChunks * 2
		if ProcessedChunks < Chunks - 1 then
			local InputIndex = ProcessedChunks * 3
			local OutputIndex = ProcessedChunks * 4

			local Word = bit32.byteswap(buffer.readu32(Input, InputIndex))
			local Octet1 = bit32.rshift(Word, 26)
			local Octet2 = bit32.rshift(Word, 20)
			local Octet3 = bit32.rshift(Word, 14)
			local Octet4 = bit32.rshift(Word, 8)

			buffer.writeu32(
				Output,
				OutputIndex,
				bit32.bor(
					Lookup[bit32.band(Octet1, 255)],
					Lookup[bit32.band(Octet2, 255)] * 256,
					Lookup[bit32.band(Octet3, 255)] * 65536,
					Lookup[bit32.band(Octet4, 255)] * 16777216
				)
			)
		end

		if InputLength > 0 then
			local TotalProcessedChunks = DoubleChunks * 2 + (ProcessedChunks < Chunks - 1 and 1 or 0)
			local ProcessedBytes = TotalProcessedChunks * 3
			local RemainingBytes = InputLength - ProcessedBytes
			local LastOutputIndex = OutputLength - 4

			if RemainingBytes == 3 then
				if ProcessedBytes + 4 <= InputLength then
					local Word = bit32.byteswap(buffer.readu32(Input, ProcessedBytes))
					local Octet1 = bit32.rshift(Word, 26)
					local Octet2 = bit32.rshift(Word, 20)
					local Octet3 = bit32.rshift(Word, 14)
					local Octet4 = bit32.rshift(Word, 8)

					buffer.writeu32(
						Output,
						LastOutputIndex,
						bit32.bor(
							Lookup[bit32.band(Octet1, 255)],
							Lookup[bit32.band(Octet2, 255)] * 256,
							Lookup[bit32.band(Octet3, 255)] * 65536,
							Lookup[bit32.band(Octet4, 255)] * 16777216
						)
					)
				else
					local Byte1 = buffer.readu8(Input, ProcessedBytes)
					local Byte2 = buffer.readu8(Input, ProcessedBytes + 1)
					local Byte3 = buffer.readu8(Input, ProcessedBytes + 2)
					local Combined = bit32.bor(bit32.lshift(Byte1, 16), bit32.lshift(Byte2, 8), Byte3)

					local Octet1 = bit32.rshift(Combined, 18)
					local Octet2 = bit32.band(bit32.rshift(Combined, 12), 63)
					local Octet3 = bit32.band(bit32.rshift(Combined, 6), 63)
					local Octet4 = bit32.band(Combined, 63)

					buffer.writeu32(
						Output,
						LastOutputIndex,
						bit32.bor(Lookup[Octet1], Lookup[Octet2] * 256, Lookup[Octet3] * 65536, Lookup[Octet4] * 16777216)
					)
				end
			elseif RemainingBytes == 2 then
				local Byte1 = buffer.readu8(Input, ProcessedBytes)
				local Byte2 = buffer.readu8(Input, ProcessedBytes + 1)
				local Combined = bit32.bor(bit32.lshift(Byte1, 16), bit32.lshift(Byte2, 8))

				local Octet1 = bit32.rshift(Combined, 18)
				local Octet2 = bit32.rshift(Combined, 12)
				local Octet3 = bit32.rshift(Combined, 6)

				buffer.writeu32(
					Output,
					LastOutputIndex,
					bit32.bor(
						Lookup[bit32.band(Octet1, 255)],
						Lookup[bit32.band(Octet2, 255)] * 256,
						Lookup[bit32.band(Octet3, 255)] * 65536,
						Padding * 16777216
					)
				)
			elseif RemainingBytes == 1 then
				local Byte1 = buffer.readu8(Input, ProcessedBytes)
				local Combined = bit32.lshift(Byte1, 16)

				local Octet1 = bit32.rshift(Combined, 18)
				local Octet2 = bit32.rshift(Combined, 12)

				buffer.writeu32(
					Output,
					LastOutputIndex,
					bit32.bor(
						Lookup[bit32.band(Octet1, 255)],
						Lookup[bit32.band(Octet2, 255)] * 256,
						Padding * 65536,
						Padding * 16777216
					)
				)
			end
		end

		return Output
	end

	function decodeBase64(Input: buffer): buffer
		local Padding = PADDING_CHARACTER
		local Lookup = DECODE_LOOKUP
		local InputLength = buffer.len(Input)

		if InputLength == 0 then
			return ""
		end

		local PaddingCount = 0
		if InputLength > 0 and buffer.readu8(Input, InputLength - 1) == Padding then
			PaddingCount = 1
			if InputLength > 1 and buffer.readu8(Input, InputLength - 2) == Padding then
				PaddingCount = 2
			end
		end

		local OutputLength = (InputLength / 4) * 3 - PaddingCount
		local Output = buffer.create(OutputLength)
		local InputChunks = InputLength // 4

		local DoubleChunks = (InputChunks - 1) // 2
		for ChunkIndex = 1, DoubleChunks do
			local InputIndex = (ChunkIndex - 1) * 8
			local OutputIndex = (ChunkIndex - 1) * 6

			local Value1_1 = Lookup[buffer.readu8(Input, InputIndex)]
			local Value1_2 = Lookup[buffer.readu8(Input, InputIndex + 1)]
			local Value1_3 = Lookup[buffer.readu8(Input, InputIndex + 2)]
			local Value1_4 = Lookup[buffer.readu8(Input, InputIndex + 3)]

			local Combined1 =
				bit32.bor(bit32.lshift(Value1_1, 18), bit32.lshift(Value1_2, 12), bit32.lshift(Value1_3, 6), Value1_4)

			local Value2_1 = Lookup[buffer.readu8(Input, InputIndex + 4)]
			local Value2_2 = Lookup[buffer.readu8(Input, InputIndex + 5)]
			local Value2_3 = Lookup[buffer.readu8(Input, InputIndex + 6)]
			local Value2_4 = Lookup[buffer.readu8(Input, InputIndex + 7)]

			local Combined2 =
				bit32.bor(bit32.lshift(Value2_1, 18), bit32.lshift(Value2_2, 12), bit32.lshift(Value2_3, 6), Value2_4)

			buffer.writeu32(
				Output,
				OutputIndex,
				bit32.bor(
					bit32.band(bit32.rshift(Combined1, 16), 255),
					bit32.band(bit32.rshift(Combined1, 8), 255) * 256,
					bit32.band(Combined1, 255) * 65536,
					bit32.band(bit32.rshift(Combined2, 16), 255) * 16777216
				)
			)

			buffer.writeu8(Output, OutputIndex + 4, bit32.band(bit32.rshift(Combined2, 8), 255))
			buffer.writeu8(Output, OutputIndex + 5, bit32.band(Combined2, 255))
		end

		local ProcessedChunks = DoubleChunks * 2
		for ChunkIndex = ProcessedChunks + 1, InputChunks do
			local InputIndex = (ChunkIndex - 1) * 4
			local OutputIndex = (ChunkIndex - 1) * 3

			local Char1 = buffer.readu8(Input, InputIndex)
			local Char2 = buffer.readu8(Input, InputIndex + 1)
			local Char3 = buffer.readu8(Input, InputIndex + 2)
			local Char4 = buffer.readu8(Input, InputIndex + 3)

			local Value1 = Lookup[Char1]
			local Value2 = Lookup[Char2]
			local Value3 = Char3 == Padding and 0 or Lookup[Char3]
			local Value4 = Char4 == Padding and 0 or Lookup[Char4]

			local Combined = bit32.bor(bit32.lshift(Value1, 18), bit32.lshift(Value2, 12), bit32.lshift(Value3, 6), Value4)

			local BytesToWrite = math.min(3, OutputLength - OutputIndex)

			if BytesToWrite >= 1 then
				buffer.writeu8(Output, OutputIndex, bit32.band(bit32.rshift(Combined, 16), 255))
			end
			if BytesToWrite >= 2 then
				buffer.writeu8(Output, OutputIndex + 1, bit32.band(bit32.rshift(Combined, 8), 255))
			end
			if BytesToWrite >= 3 then
				buffer.writeu8(Output, OutputIndex + 2, bit32.band(Combined, 255))
			end
		end

		return Output
	end
end

do
	local BLOCK_SIZE = 64
	local CV_SIZE = 32
	local EXTENDED_CV_SIZE = 64
	local MAX_STACK_DEPTH = 64
	local STACK_BUFFER_SIZE = MAX_STACK_DEPTH * CV_SIZE

	local BLAKE3_KEY_SIZE = 32
	local BLAKE3_MIN_OUTPUT_BYTES = 1
	local BLAKE3_MAX_OUTPUT_BYTES = 2 ^ 32 - 1

	local CHUNK_START = 0x01
	local CHUNK_END = 0x02
	local PARENT_FLAG = 0x04
	local ROOT_FLAG = 0x08
	local HASH_FLAG = 0x10
	local DERIVE_CONTEXT_FLAG = 0x20
	local DERIVE_MATERIAL_FLAG = 0x40

	local INITIAL_VECTORS = buffer.create(CV_SIZE)
	do
		local IV = {
			0x6a09e667,
			0xbb67ae85,
			0x3c6ef372,
			0xa54ff53a,
			0x510e527f,
			0x9b05688c,
			0x1f83d9ab,
			0x5be0cd19,
		}
		for Index, Value in ipairs(IV) do
			buffer.writeu32(INITIAL_VECTORS, (Index - 1) * 4, Value)
		end
	end

	local function Compress(
		Hash: buffer,
		MessageBlock: buffer,
		Counter: number,
		V14: number,
		V15: number,
		IsFull: boolean?
	): buffer
		local Hash00 = buffer.readu32(Hash, 0)
		local Hash01 = buffer.readu32(Hash, 4)
		local Hash02 = buffer.readu32(Hash, 8)
		local Hash03 = buffer.readu32(Hash, 12)
		local Hash04 = buffer.readu32(Hash, 16)
		local Hash05 = buffer.readu32(Hash, 20)
		local Hash06 = buffer.readu32(Hash, 24)
		local Hash07 = buffer.readu32(Hash, 28)

		local V00, V01, V02, V03 = Hash00, Hash01, Hash02, Hash03
		local V04, V05, V06, V07 = Hash04, Hash05, Hash06, Hash07
		local V08, V09, V10, V11 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a

		local V12 = Counter % (2 ^ 32)
		local V13 = (Counter - V12) * (2 ^ -32)

		local M00 = buffer.readu32(MessageBlock, 0)
		local M01 = buffer.readu32(MessageBlock, 4)
		local M02 = buffer.readu32(MessageBlock, 8)
		local M03 = buffer.readu32(MessageBlock, 12)
		local M04 = buffer.readu32(MessageBlock, 16)
		local M05 = buffer.readu32(MessageBlock, 20)
		local M06 = buffer.readu32(MessageBlock, 24)
		local M07 = buffer.readu32(MessageBlock, 28)
		local M08 = buffer.readu32(MessageBlock, 32)
		local M09 = buffer.readu32(MessageBlock, 36)
		local M10 = buffer.readu32(MessageBlock, 40)
		local M11 = buffer.readu32(MessageBlock, 44)
		local M12 = buffer.readu32(MessageBlock, 48)
		local M13 = buffer.readu32(MessageBlock, 52)
		local M14 = buffer.readu32(MessageBlock, 56)
		local M15 = buffer.readu32(MessageBlock, 60)

		local XOR = bit32.bxor
		local LEFTROTATE = bit32.lrotate

		local Temp
		for Index = 1, 7 do
			V00 += V04 + M00
			V12 = LEFTROTATE(XOR(V12, V00), 16)
			V08 += V12
			V04 = LEFTROTATE(XOR(V04, V08), 20)
			V00 += V04 + M01
			V12 = LEFTROTATE(XOR(V12, V00), 24)
			V08 += V12
			V04 = LEFTROTATE(XOR(V04, V08), 25)

			V01 += V05 + M02
			V13 = LEFTROTATE(XOR(V13, V01), 16)
			V09 += V13
			V05 = LEFTROTATE(XOR(V05, V09), 20)
			V01 += V05 + M03
			V13 = LEFTROTATE(XOR(V13, V01), 24)
			V09 += V13
			V05 = LEFTROTATE(XOR(V05, V09), 25)

			V02 += V06 + M04
			V14 = LEFTROTATE(XOR(V14, V02), 16)
			V10 += V14
			V06 = LEFTROTATE(XOR(V06, V10), 20)
			V02 += V06 + M05
			V14 = LEFTROTATE(XOR(V14, V02), 24)
			V10 += V14
			V06 = LEFTROTATE(XOR(V06, V10), 25)

			V03 += V07 + M06
			V15 = LEFTROTATE(XOR(V15, V03), 16)
			V11 += V15
			V07 = LEFTROTATE(XOR(V07, V11), 20)
			V03 += V07 + M07
			V15 = LEFTROTATE(XOR(V15, V03), 24)
			V11 += V15
			V07 = LEFTROTATE(XOR(V07, V11), 25)

			V00 += V05 + M08
			V15 = LEFTROTATE(XOR(V15, V00), 16)
			V10 += V15
			V05 = LEFTROTATE(XOR(V05, V10), 20)
			V00 += V05 + M09
			V15 = LEFTROTATE(XOR(V15, V00), 24)
			V10 += V15
			V05 = LEFTROTATE(XOR(V05, V10), 25)

			V01 += V06 + M10
			V12 = LEFTROTATE(XOR(V12, V01), 16)
			V11 += V12
			V06 = LEFTROTATE(XOR(V06, V11), 20)
			V01 += V06 + M11
			V12 = LEFTROTATE(XOR(V12, V01), 24)
			V11 += V12
			V06 = LEFTROTATE(XOR(V06, V11), 25)

			V02 += V07 + M12
			V13 = LEFTROTATE(XOR(V13, V02), 16)
			V08 += V13
			V07 = LEFTROTATE(XOR(V07, V08), 20)
			V02 += V07 + M13
			V13 = LEFTROTATE(XOR(V13, V02), 24)
			V08 += V13
			V07 = LEFTROTATE(XOR(V07, V08), 25)

			V03 += V04 + M14
			V14 = LEFTROTATE(XOR(V14, V03), 16)
			V09 += V14
			V04 = LEFTROTATE(XOR(V04, V09), 20)
			V03 += V04 + M15
			V14 = LEFTROTATE(XOR(V14, V03), 24)
			V09 += V14
			V04 = LEFTROTATE(XOR(V04, V09), 25)

			if Index ~= 7 then
				Temp = M02
				M02 = M03
				M03 = M10
				M10 = M12
				M12 = M09
				M09 = M11
				M11 = M05
				M05 = M00
				M00 = Temp

				Temp = M06
				M06 = M04
				M04 = M07
				M07 = M13
				M13 = M14
				M14 = M15
				M15 = M08
				M08 = M01
				M01 = Temp
			end
		end

		if IsFull then
			local Result = buffer.create(EXTENDED_CV_SIZE)
			buffer.writeu32(Result, 0, XOR(V00, V08))
			buffer.writeu32(Result, 4, XOR(V01, V09))
			buffer.writeu32(Result, 8, XOR(V02, V10))
			buffer.writeu32(Result, 12, XOR(V03, V11))
			buffer.writeu32(Result, 16, XOR(V04, V12))
			buffer.writeu32(Result, 20, XOR(V05, V13))
			buffer.writeu32(Result, 24, XOR(V06, V14))
			buffer.writeu32(Result, 28, XOR(V07, V15))

			buffer.writeu32(Result, 32, XOR(V08, Hash00))
			buffer.writeu32(Result, 36, XOR(V09, Hash01))
			buffer.writeu32(Result, 40, XOR(V10, Hash02))
			buffer.writeu32(Result, 44, XOR(V11, Hash03))
			buffer.writeu32(Result, 48, XOR(V12, Hash04))
			buffer.writeu32(Result, 52, XOR(V13, Hash05))
			buffer.writeu32(Result, 56, XOR(V14, Hash06))
			buffer.writeu32(Result, 60, XOR(V15, Hash07))

			return Result
		else
			local Result = buffer.create(CV_SIZE)
			buffer.writeu32(Result, 0, XOR(V00, V08))
			buffer.writeu32(Result, 4, XOR(V01, V09))
			buffer.writeu32(Result, 8, XOR(V02, V10))
			buffer.writeu32(Result, 12, XOR(V03, V11))
			buffer.writeu32(Result, 16, XOR(V04, V12))
			buffer.writeu32(Result, 20, XOR(V05, V13))
			buffer.writeu32(Result, 24, XOR(V06, V14))
			buffer.writeu32(Result, 28, XOR(V07, V15))

			return Result
		end
	end

	local function ProcessMessage(InitialHashVector: buffer, Flags: number, Message: buffer, Length: number): buffer
		local MessageLength = buffer.len(Message)
		local StateCvs = buffer.create(STACK_BUFFER_SIZE)
		local StackSize = 0
		local StateCv = buffer.create(CV_SIZE)
		buffer.copy(StateCv, 0, InitialHashVector, 0, CV_SIZE)

		local StateCounter = 0
		local StateChunkNumber = 0
		local StateEndFlag = 0
		local StateStartFlag = CHUNK_START

		local BlockBuffer = buffer.create(BLOCK_SIZE)

		for BlockOffset = 0, MessageLength - BLOCK_SIZE - 1, BLOCK_SIZE do
			buffer.copy(BlockBuffer, 0, Message, BlockOffset, BLOCK_SIZE)
			local StateFlags = Flags + StateStartFlag + StateEndFlag

			StateCv = Compress(StateCv, BlockBuffer, StateCounter, BLOCK_SIZE, StateFlags)
			StateStartFlag = 0
			StateChunkNumber += 1

			if StateChunkNumber == 15 then
				StateEndFlag = CHUNK_END
			elseif StateChunkNumber == 16 then
				local MergeCv = StateCv
				local MergeAmount = StateCounter + 1

				while MergeAmount % 2 == 0 do
					StackSize = StackSize - 1
					local PopCv = buffer.create(CV_SIZE)
					buffer.copy(PopCv, 0, StateCvs, StackSize * CV_SIZE, CV_SIZE)

					local Block = buffer.create(EXTENDED_CV_SIZE)
					buffer.copy(Block, 0, PopCv, 0, CV_SIZE)
					buffer.copy(Block, CV_SIZE, MergeCv, 0, CV_SIZE)

					MergeCv = Compress(InitialHashVector, Block, 0, BLOCK_SIZE, Flags + PARENT_FLAG)
					MergeAmount = MergeAmount / 2
				end

				buffer.copy(StateCvs, StackSize * CV_SIZE, MergeCv, 0, CV_SIZE)
				StackSize = StackSize + 1
				buffer.copy(StateCv, 0, InitialHashVector, 0, CV_SIZE)
				StateStartFlag = CHUNK_START

				StateCounter += 1
				StateChunkNumber = 0
				StateEndFlag = 0
			end
		end

		local LastLength = MessageLength == 0 and 0 or ((MessageLength - 1) % BLOCK_SIZE + 1)
		local PaddedMessage = buffer.create(BLOCK_SIZE)

		if LastLength > 0 then
			buffer.copy(PaddedMessage, 0, Message, MessageLength - LastLength, LastLength)
		end

		local OutputCv: buffer
		local OutputBlock: buffer
		local OutputLength: number
		local OutputFlags: number

		if StateCounter > 0 then
			local StateFlags = Flags + StateStartFlag + CHUNK_END
			local MergeCv = Compress(StateCv, PaddedMessage, StateCounter, LastLength, StateFlags)

			for Index = StackSize, 2, -1 do
				local StackCv = buffer.create(CV_SIZE)
				buffer.copy(StackCv, 0, StateCvs, (Index - 1) * CV_SIZE, CV_SIZE)

				local Block = buffer.create(EXTENDED_CV_SIZE)
				buffer.copy(Block, 0, StackCv, 0, CV_SIZE)
				buffer.copy(Block, CV_SIZE, MergeCv, 0, CV_SIZE)

				MergeCv = Compress(InitialHashVector, Block, 0, BLOCK_SIZE, Flags + PARENT_FLAG)
			end

			OutputCv = InitialHashVector
			local FirstStackCv = buffer.create(CV_SIZE)
			buffer.copy(FirstStackCv, 0, StateCvs, 0, CV_SIZE)

			OutputBlock = buffer.create(EXTENDED_CV_SIZE)
			buffer.copy(OutputBlock, 0, FirstStackCv, 0, CV_SIZE)
			buffer.copy(OutputBlock, CV_SIZE, MergeCv, 0, CV_SIZE)

			OutputLength = BLOCK_SIZE
			OutputFlags = Flags + ROOT_FLAG + PARENT_FLAG
		else
			OutputCv = StateCv
			OutputBlock = PaddedMessage
			OutputLength = LastLength
			OutputFlags = Flags + StateStartFlag + CHUNK_END + ROOT_FLAG
		end

		local Output = buffer.create(Length)
		local OutputOffset = 0

		for Index = 0, Length // BLOCK_SIZE do
			local MessageDigest = Compress(OutputCv, OutputBlock, Index, OutputLength, OutputFlags, true)

			local BytesToCopy = math.min(BLOCK_SIZE, Length - OutputOffset)
			buffer.copy(Output, OutputOffset, MessageDigest, 0, BytesToCopy)
			OutputOffset += BytesToCopy

			if OutputOffset >= Length then
				break
			end
		end

		return Output
	end

	function Blake3.Digest(Message: buffer, Length: number?): (string, buffer)
		if Message == nil then
			error("Message cannot be nil", 2)
		end

		if typeof(Message) ~= "buffer" then
			error(`Message must be a buffer, got {typeof(Message)}`, 2)
		end

		if Length then
			if typeof(Length) ~= "number" then
				error(`Length must be a number, got {typeof(Length)}`, 2)
			end

			if Length ~= math.floor(Length) then
				error(`Length must be an integer, got {Length}`, 2)
			end

			if Length < BLAKE3_MIN_OUTPUT_BYTES then
				error(`Length must be at least {BLAKE3_MIN_OUTPUT_BYTES} byte, got {Length} bytes`, 2)
			end

			if Length > BLAKE3_MAX_OUTPUT_BYTES then
				error(`Length must be at most {BLAKE3_MAX_OUTPUT_BYTES} bytes, got {Length} bytes`, 2)
			end
		end

		local Result = ProcessMessage(INITIAL_VECTORS, 0, Message, Length or 32)

		local ResultLength = buffer.len(Result)
		local Hex = buffer.create(ResultLength * 2)
		local Leftover = ResultLength % 4

		for Index = 0, ResultLength - Leftover - 1, 4 do
			buffer.writestring(Hex, Index * 2, string.format("%08x", bit32.byteswap(buffer.readu32(Result, Index))))
		end

		for Index = ResultLength - Leftover, ResultLength - 1 do
			buffer.writestring(Hex, Index * 2, string.format("%02x", buffer.readu8(Result, Index)))
		end

		return buffer.tostring(Hex)
	end

	function Blake3.DigestKeyed(Key: buffer, Message: buffer, Length: number?): (string, buffer)
		if Key == nil then
			error("Key cannot be nil", 2)
		end

		if typeof(Key) ~= "buffer" then
			error(`Key must be a buffer, got {typeof(Key)}`, 2)
		end

		local KeyLength = buffer.len(Key)
		if KeyLength ~= BLAKE3_KEY_SIZE then
			error(`Key must be exactly {BLAKE3_KEY_SIZE} bytes long, got {KeyLength} bytes`, 2)
		end

		if Message == nil then
			error("Message cannot be nil", 2)
		end
		if typeof(Message) ~= "buffer" then
			error(`Message must be a buffer, got {typeof(Message)}`, 2)
		end

		if Length then
			if typeof(Length) ~= "number" then
				error(`Length must be a number, got {typeof(Length)}`, 2)
			end
			if Length ~= math.floor(Length) then
				error(`Length must be an integer, got {Length}`, 2)
			end
			if Length < BLAKE3_MIN_OUTPUT_BYTES then
				error(`Length must be at least {BLAKE3_MIN_OUTPUT_BYTES} byte, got {Length} bytes`, 2)
			end
			if Length > BLAKE3_MAX_OUTPUT_BYTES then
				error(`Length must be at most {BLAKE3_MAX_OUTPUT_BYTES} bytes, got {Length} bytes`, 2)
			end
		end

		local Result = ProcessMessage(Key, HASH_FLAG, Message, Length or 32)

		local ResultLength = buffer.len(Result)
		local Hex = buffer.create(ResultLength * 2)
		local Leftover = ResultLength % 4

		for Index = 0, ResultLength - Leftover - 1, 4 do
			buffer.writestring(Hex, Index * 2, string.format("%08x", bit32.byteswap(buffer.readu32(Result, Index))))
		end

		for Index = ResultLength - Leftover, ResultLength - 1 do
			buffer.writestring(Hex, Index * 2, string.format("%02x", buffer.readu8(Result, Index)))
		end

		return buffer.tostring(Hex), Result
	end

	function Blake3.DeriveKey(Context: buffer): (buffer, number?) -> (string, buffer)
		if Context == nil then
			error("Context cannot be nil", 2)
		end

		if typeof(Context) ~= "buffer" then
			error(`Context must be a buffer, got {typeof(Context)}`, 2)
		end

		local ContextHash = ProcessMessage(INITIAL_VECTORS, DERIVE_CONTEXT_FLAG, Context, 32)

		return function(Material: buffer, Length: number?): (string, buffer)
			if Material == nil then
				error("Material cannot be nil", 2)
			end

			if typeof(Material) ~= "buffer" then
				error(`Material must be a buffer, got {typeof(Material)}`, 2)
			end

			if Length then
				if typeof(Length) ~= "number" then
					error(`Length must be a number, got {typeof(Length)}`, 2)
				end

				if Length ~= math.floor(Length) then
					error(`Length must be an integer, got {Length}`, 2)
				end

				if Length < BLAKE3_MIN_OUTPUT_BYTES then
					error(`Length must be at least {BLAKE3_MIN_OUTPUT_BYTES} byte, got {Length} bytes`, 2)
				end

				if Length > BLAKE3_MAX_OUTPUT_BYTES then
					error(`Length must be at most {BLAKE3_MAX_OUTPUT_BYTES} bytes, got {Length} bytes`, 2)
				end
			end

			local Result = ProcessMessage(ContextHash, DERIVE_MATERIAL_FLAG, Material, Length or 32)

			local ResultLength = buffer.len(Result)
			local Hex = buffer.create(ResultLength * 2)
			local Leftover = ResultLength % 4

			for Index = 0, ResultLength - Leftover - 1, 4 do
				buffer.writestring(Hex, Index * 2, string.format("%08x", bit32.byteswap(buffer.readu32(Result, Index))))
			end

			for Index = ResultLength - Leftover, ResultLength - 1 do
				buffer.writestring(Hex, Index * 2, string.format("%02x", buffer.readu8(Result, Index)))
			end

			return buffer.tostring(Hex), Result
		end
	end
end

--[[ end of libs ]]

local function read(file: string): buffer?
	local success, data: {
		Faces: {
			Name: string,
		},
	} =
		pcall(TextService.GetFamilyInfoAsync, TextService, "rbxasset://fonts/rpc/" .. file .. "")
	-- print(file, success, data)
	return if success then decodeBase64(buffer.fromstring(data.Faces[1].Name)) else nil
end

local function rawWrite(data: buffer)
	print("[github:techs-sus/rpc] " .. buffer.tostring(encodeBase64(data)))
end

local robloxSidePacketId = 0
local acknowledged: { [number]: boolean } = {}

local function writeData(data: buffer)
	local thisPacketId = robloxSidePacketId

	robloxSidePacketId += 1

	-- ServerboundPacket::Data
	local packet = buffer.create(5 + buffer.len(data))
	buffer.writeu8(packet, 0, 2)
	buffer.writeu32(packet, 1, thisPacketId)
	buffer.copy(packet, 5, data, 0)
	rawWrite(packet)

	-- loop, this is ment to be used outside of watch thread
	while task.wait() do
		if acknowledged[thisPacketId] then
			acknowledged[thisPacketId] = nil
			break
		end
	end

	return
end

warn("please ensure repr is disabled in lsb")

local didInit = false
local currentCachebuster = Blake3.Digest(buffer.fromstring(game.PlaceId .. game.JobId .. math.random()), 32)

local function getNextCachebuster(cachebuster: string)
	return Blake3.Digest(buffer.fromstring(cachebuster .. "pls give next"), 32)
end

local function getBackupCachebuster(cachebuster: string)
	return Blake3.Digest(buffer.fromstring(cachebuster .. "pls give backup"), 32)
end

local function watcherThread(receiveCallback: (packetId: number, data: buffer) -> ())
	while task.wait(1.5) do
		if didInit then
			local data = read(currentCachebuster .. ".json") or read(getBackupCachebuster(currentCachebuster) .. ".json")
			if not data then
				continue
			end

			-- All ClientboundPacket's have a 5 byte overhead
			local packetType = buffer.readu8(data, 0)
			local packetId = buffer.readu32(data, 1)

			if packetType == 1 then
				-- ClientboundPacket::Acknowledge ! packetId is a client packet id
				acknowledged[packetId] = true
			elseif packetType == 2 then
				-- ClientboundPacket::Data ! packetId is a server packet id
				local dataBuffer = buffer.create(buffer.len(data) - 5)
				buffer.copy(dataBuffer, 0, data, 5)

				do
					-- ServerboundPacket::Acknowledge
					local acknowledgePacket = buffer.create(5)
					buffer.writeu8(acknowledgePacket, 0, 1)
					buffer.writeu32(acknowledgePacket, 1, packetId)
					rawWrite(acknowledgePacket)
				end

				receiveCallback(packetId, dataBuffer)
			end

			currentCachebuster = getNextCachebuster(currentCachebuster)
		else
			local rpcIsAlive = read("init.json")

			if rpcIsAlive then
				-- ServerboundPacket::Init
				local initPacket = buffer.create(#currentCachebuster + 1)
				buffer.writeu8(initPacket, 0, 0)
				buffer.writestring(initPacket, 1, currentCachebuster)
				rawWrite(initPacket)

				didInit = true
			end
		end
	end
end

local Module = {}

@checked
function Module.init(receiveCallback: (packetId: number, data: buffer) -> ())
	assert(type(receiveCallback) == "function", "receiveCallback must be a function")

	local thread = task.spawn(watcherThread, receiveCallback)

	Module.thread = thread

	repeat
		task.wait()
	until didInit
end

@checked
function Module.stop()
	coroutine.close(Module.thread)
end

@checked
function Module.send(data: buffer)
	assert(Module.thread and didInit, "init was not called")
	assert(type(data) == "buffer", "data is not a buffer")

	writeData(data)
end

Module.init(function(packetId, data)
	print(`{packetId} -> {buffer.tostring(data)}`)
end)

Module.send(buffer.fromstring("Hello rpc!"))

while task.wait(1) do
	Module.send(buffer.fromstring("Hello rpc! @ " .. os.clock()))
end

return Module
