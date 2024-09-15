#import "Basic";
#import "Socket";
#import "Window_Creation";
#import "Input";
#import "Simp";
#import "GetRect";
#import "Math";
#import "String";

#load "netchat_common.jai";

MySocket: SOCKET = INVALID_SOCKET;

ConnectNetchatServer :: (address: string, port: u16) -> Logical {
	log("Connecting to server %:%...", address, port);
	
	if !socket_init() {
		log_error("Failed to initialize sockets. Error=%", get_last_socket_error());
		return false;
	}
	
	MySocket = socket(AF_INET, .STREAM, 0);
	if MySocket == INVALID_SOCKET {
		log_error("Failed to create client socket. Error=%", get_last_socket_error());
		return false;
	}
	
	internet_socket_address_struct: sockaddr_in;
	internet_socket_address_struct.sin_family = AF_INET;
	
	c_address := to_c_string(address);
   defer free(c_address);
	addr := inet_addr(c_address);
	#if OS == .WINDOWS {
		internet_socket_address_struct.sin_addr.S_un.S_addr = addr;
	} else {
		internet_socket_address_struct.sin_addr.s_addr = addr;
	}
	
	internet_socket_address_struct.sin_port = htons(port);
	
	server_address := internet_socket_address_struct;
	if connect(MySocket, cast(*sockaddr) *server_address, size_of(type_of(server_address))) != 0 {
		print("Failed to connect to server. OS_Error=%\n", get_last_socket_error());
		close_and_reset(*MySocket);
		return false;
	}
	
	return true;
}

DisconnectNetchatServer :: () {
	if MySocket != INVALID_SOCKET {
		close_and_reset(*MySocket);
	}
}

MAX_BUFFER_SIZE :: 1_000_000;
CHAT_BUFFER_DATA: [MAX_BUFFER_SIZE]u8;
CHAT_BUFFER := string.{ data = CHAT_BUFFER_DATA.data, count = 0 };

main :: () {
	args := get_command_line_arguments();
	
	if args.count != 3 {
		print("netchat_client <IP_ADDRESS> <PORT>");
		return;
	}
	
	SERVER_IP = args[1];
	
	port_value, success := string_to_int(args[2]);
	if !success {
		log_error("Unable to parse port argument \"%\" as an integer", args[2]);
		return;
	}
	SERVER_PORT = cast(u16) port_value;
	
	if !ConnectNetchatServer(SERVER_IP, SERVER_PORT) {
		return;
	}
	
	window := create_window(800, 600, "NetChadt!");
	
	set_render_target(window);
	
	proggy_clean := get_font_at_size("data", "ProggyClean.ttf", 24);
	assert(proggy_clean != null);
	
	ui_init();
	
	current_time: float64;
	last_time: float64;
	
	ChatBufferBuilder: String_Builder;
	init_string_builder(*ChatBufferBuilder);
	
	running := true;
	while running {
		current_time = seconds_since_init();
		dt := cast(float)(current_time - last_time);
		Clamp(*dt, 0, 0.1);
		last_time = current_time;
		
		update_window_events();
		
		for get_window_resizes() {
			update_window(it.window);
		}
		
		for events_this_frame {
			if it.type == .QUIT {
				running = false;
			}
			getrect_handle_event(it);
		}
		
		alive, data_ready := PollSocket(MySocket, 10);
		if data_ready {
			response_buffer: [4096] u8;
			response: string;
			response.count = recv(MySocket, cast(*u8) *response_buffer, 4096, 0);
			response.data = response_buffer.data;
			log("Received: %", response);
			append(*ChatBufferBuilder, response);
		}
		
		clear_render_target(0.25, 0.25, 0.25, 1.0);
		x, y, width, height := get_dimensions(window, true);
		ui_per_frame_update(window, width, height, current_time);
		
		theme := default_theme_procs[0]();
		set_default_theme(theme);
		
		text_input_theme := theme.text_input_theme;
		text_input_theme.font = proggy_clean;
		
		rect := get_rect(0, 0, width * 1.0, proggy_clean.character_height * 1.5);
		action, new_input := text_input(rect, "", *text_input_theme);
		if action & .ENTERED {
			log("Sending message: %\n", new_input);
			if send(MySocket, new_input.data, cast(s32) new_input.count, 0) < 0 {
				log("Message sent!\n");
			}
			new_input.count = 0;
		}
		
		chat_x := 0;
		chat_y := height - proggy_clean.character_height;
		
		chat_buffer_copy := builder_to_string(*ChatBufferBuilder, do_reset = false); // TODO: remove _copy
		
		while chat_buffer_copy.count {
			text := chat_buffer_copy;
			text.count = find_index_from_left(chat_buffer_copy, "\n");
			if text.count == 0 break;
			draw_text(proggy_clean, chat_x, chat_y, text, color = Vector4.{ 1, 1, 1, 1 });
			advance(*chat_buffer_copy, text.count + 1);
			chat_y -= proggy_clean.character_height;
		}
		
		
		swap_buffers(window);
		
		reset_temporary_storage();
		sleep_milliseconds(10);
	}
	
	DisconnectNetchatServer();		
}
