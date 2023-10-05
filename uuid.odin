package uuid

import "core:fmt"
import "core:io"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:strings"
import "core:testing"

Uuid :: [16]byte

SectionName :: enum {
	TimeLow,
	TimeMid,
	VersionAndTimeHigh,
	ClockSeqHiAndReserved,
	ClockSeqLow,
	Node,
}

FromStringError :: union {
	InvalidLength,
	InvalidFormat,
	InvalidVersion,
	io.Error,
}

InvalidLength :: struct {
	expected: int,
	length:   int,
}

InvalidFormat :: struct {
	section:  SectionName,
	expected: int,
	actual:   int,
}

InvalidVersion :: struct {
	expected: int,
	actual:   int,
}

// Creates a random UUID (v4). The `Rand` instance used can be overriden by passing a non-nil `r`
// value.
new_v4 :: proc(r: ^rand.Rand = nil) -> (uuid: Uuid) {
	random_byte_count := rand.read(uuid[:], r)
	assert(
		random_byte_count == len(uuid),
		fmt.tprintf("Expected to generate %d bytes for UUID", len(uuid)),
	)
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80

	return uuid
}

@(test, private = "package")
test_new_v4 :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	buffer: [36]byte
	for i := 0; i < 10; i += 1 {
		uuid := new_v4()
		version := version(uuid)
		testing.expect(t, version == 4, fmt.tprintf("Expected version to be 4, got: %v", version))
		log.debugf("Generated UUID: %s", to_string(uuid, buffer[:]))
	}
}

version :: proc(u: Uuid) -> int {
	return int(u[6]) >> 4
}

// Reads a UUID from a standard formatted UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) string.
from_string :: proc(s: string) -> (uuid: Uuid, error: FromStringError) {
	if len(s) != 36 {
		return Uuid{}, InvalidLength{expected = 36, length = len(s)}
	}

	buffer: [32]byte

	reader: strings.Reader
	strings.reader_init(&reader, s)

	read_fill_buffer(&reader, .TimeLow, buffer[0:8]) or_return
	skip_hyphen(&reader) or_return

	read_fill_buffer(&reader, .TimeMid, buffer[8:12]) or_return
	skip_hyphen(&reader) or_return

	read_fill_buffer(&reader, .VersionAndTimeHigh, buffer[12:16]) or_return
	skip_hyphen(&reader) or_return

	read_fill_buffer(&reader, .ClockSeqHiAndReserved, buffer[16:18]) or_return
	read_fill_buffer(&reader, .ClockSeqLow, buffer[18:20]) or_return
	skip_hyphen(&reader) or_return

	read_fill_buffer(&reader, .Node, buffer[20:32]) or_return

	for i := 0; i < 16; i += 1 {
		uuid[i] =
			hex_digit_to_numeric_value(buffer[i * 2]) << 4 |
			hex_digit_to_numeric_value(buffer[(i * 2) + 1])
	}

	return uuid, nil
}

@(test, private = "package")
test_from_string :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	examples := []string{
		"d20a21dc-d2bc-4219-ae33-7d8b90e76920",
		"8df9c196-993b-4742-9995-11200de411cd",
		"16dcb917-4707-4a94-a2d6-ad94327759db",
		"2e651dfd-c7f8-478b-bb13-2b0869462bda",
		"6363ff70-0690-4029-b8b7-5d06cd5685a1",
		"80839427-d7da-402f-b495-220f23e5f26e",
		"2c381b6f-12b7-4574-bcf6-438697aa0b22",
		"67934998-264a-48dd-ac29-4692870577c0",
		"cf00ed4e-9fcc-4aee-9f92-cc72edd039f2",
		"2b3597c7-35a3-4d65-8a65-523133c4ffa8",
	}

	for example in examples {
		uuid, error := from_string(example)
		testing.expect(t, error == nil, fmt.tprintf("Expected error to be nil, got: %v", error))
		version := version(uuid)
		testing.expect(t, version == 4, fmt.tprintf("Expected version to be 4, got: %v", version))
	}
}

// Converts a UUID to a standard formatted UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) string.
// Note that a backing buffer is expected to be passed in and that it has to be 36 bytes in size.
// This is done to avoid heap allocations.
to_string :: proc(uuid: Uuid, buffer: []byte) -> string {
	assert(len(buffer) == 36, "Expected `to_string` buffer to be 36 bytes long")
	uuid: [16]byte = uuid

	return fmt.bprintf(
		buffer,
		"%8x-%4x-%4x-%2x%2x-%08x%04x",
		mem.reinterpret_copy(u32be, &uuid[0]),
		mem.reinterpret_copy(u16be, &uuid[4]),
		mem.reinterpret_copy(u16be, &uuid[6]),
		uuid[8],
		uuid[9],
		mem.reinterpret_copy(u32be, &uuid[10]),
		mem.reinterpret_copy(u16be, &uuid[14]),
	)
}

@(test, private = "package")
test_to_string :: proc(t: ^testing.T) {
	examples := []string{
		"d20a21dc-d2bc-4219-ae33-7d8b90e76920",
		"8df9c196-993b-4742-9995-11200de411cd",
		"16dcb917-4707-4a94-a2d6-ad94327759db",
		"2e651dfd-c7f8-478b-bb13-2b0869462bda",
		"6363ff70-0690-4029-b8b7-5d06cd5685a1",
		"80839427-d7da-402f-b495-220f23e5f26e",
		"2c381b6f-12b7-4574-bcf6-438697aa0b22",
		"67934998-264a-48dd-ac29-4692870577c0",
		"cf00ed4e-9fcc-4aee-9f92-cc72edd039f2",
		"2b3597c7-35a3-4d65-8a65-523133c4ffa8",
	}

	buffer: [36]byte
	for example in examples {
		uuid, error := from_string(example)
		testing.expect(t, error == nil, fmt.tprintf("Expected error to be nil, got: %v", error))
		testing.expect(
			t,
			to_string(uuid, buffer[:]) == example,
			fmt.tprintf("Expected '%s', got '%s'", example, to_string(uuid, buffer[:])),
		)
	}
}

@(private = "file")
skip_hyphen :: proc(r: ^strings.Reader) -> io.Error {
	strings.reader_read_byte(r) or_return

	return nil
}

@(private = "file")
read_fill_buffer :: proc(
	r: ^strings.Reader,
	section: SectionName,
	buffer: []byte,
) -> FromStringError {
	bytes_read := strings.reader_read(r, buffer[:]) or_return
	if bytes_read != len(buffer) {
		return InvalidFormat{section = section, expected = len(buffer), actual = bytes_read}
	}

	return nil
}

@(private = "file")
hex_digit_to_numeric_value :: proc(d: byte) -> byte {
	switch d {
	case '0' ..= '9':
		return d - '0'
	case 'a' ..= 'f':
		return d - 'a' + 10
	case 'A' ..= 'F':
		return d - 'A' + 10
	}

	return 0
}

@(test, private = "package")
test_hex_digit_to_numeric_value :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	expected1 := byte(0)
	result1 := hex_digit_to_numeric_value('0')
	testing.expect(t, result1 == expected1, fmt.tprintf("Expected %v, got %v", expected1, result1))

	expected2 := byte(9)
	result2 := hex_digit_to_numeric_value('9')
	testing.expect(t, result2 == expected2, fmt.tprintf("Expected %v, got %v", expected2, result2))

	expected3 := byte(10)
	result3 := hex_digit_to_numeric_value('a')
	testing.expect(t, result3 == expected3, fmt.tprintf("Expected %v, got %v", expected3, result3))

	expected4 := byte(4)
	result4 := hex_digit_to_numeric_value('4')
	testing.expect(t, result4 == expected4, fmt.tprintf("Expected %v, got %v", expected4, result4))
}
