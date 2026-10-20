// A trampoline the web terminal's wasm calls to send terminal replies back to the PTY
// (from T3 Code, MIT).
extern "env" fn devys_write_pty(terminal: u32, userdata: u32, data: u32, len: u32) void;

export fn ghostty_write_pty(terminal: u32, userdata: u32, data: u32, len: u32) void {
    devys_write_pty(terminal, userdata, data, len);
}
