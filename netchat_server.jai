#import "Basic";
#import "Socket";
#import "Thread";
//#import "POSIX";

Logical :: bool;
server_socket: Socket;

ClientInfo :: struct {
	connected: bool;
	sock: SOCKET;
	address: sockaddr_in;
}

MAX_CLIENTS :: 2;
ConnectedClients: [MAX_CLIENTS]ClientInfo;
ConnectedClientsMutex: Mutex;

IncomingConnectionThread :: (thread: *Thread) -> s64 {
	log("IncomingConnectionThread started");
	
	while true {
		client_socket, client_address := accept(server_socket);

		lock(*ConnectedClientsMutex);
		
		print("% connected!\n", to_string(client_address));
		for ClientIndex: 0..MAX_CLIENTS-1 {
			client_info := ConnectedClients.data + ClientIndex;
			if client_info.connected continue;
			client_info.sock = client_socket;
			client_info.address = client_address;
			client_info.connected = true;
			break;
		}
		
		unlock(*ConnectedClientsMutex);
	}
	
	return 0;
}

PollSocket :: (sock: SOCKET, timeout_millis: s32) -> (alive: Logical, data_ready: Logical) {
	poll_params := pollfd.[
		.{ fd = sock, events = POLLRDNORM }
	];
	WSAPoll(poll_params.data, 1, timeout_millis);
	
	revents := poll_params[0].revents;
	alive := !((revents & POLLERR) || (revents & POLLHUP));
	data_ready := cast(Logical) revents & POLLRDNORM;
	
	return alive, data_ready;
}

main :: () {
	print("NetChat Server!\n");
	
	if !socket_init() {
		log_error("Failed to initialize sockets. Error=%", get_last_socket_error());
		return;
	}
	
	server_socket = socket(AF_INET, .STREAM, 0);
	if server_socket == INVALID_SOCKET {
		log_error("Failed to create server socket. Error=%", get_last_socket_error());
		return;
	}                         
	
	reuse: u8 = 1;
	if setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, *reuse, size_of(type_of(reuse))) != 0 {
		log_error("Setting socket reuse failed... Error=%", get_last_socket_error());
		return;
	}
	
	if bind(server_socket, "127.0.0.1", 42069) != 0 {
		log_error("Failed to bind server socket to 127.0.0.1:42069. Error=%", get_last_socket_error());
		return;
	}
	
	if listen(server_socket, 1) != 0 {
		log_error("listen(server_socket, 1) failed. Error=%", get_last_socket_error());
		return;
	}
	
	init(*ConnectedClientsMutex);
	
	// accept clients on another thread
	
	IncomingConnectionThreadHandle: Thread;
	if !thread_init(*IncomingConnectionThreadHandle, IncomingConnectionThread) {
		log_error("Failed to starting incoming connection handler thread");
		close_and_reset(*server_socket);
		return;
	}
	thread_start(*IncomingConnectionThreadHandle);
	
	// update the connected clients once a second on the main thread
	//  - lock
	//  - check if still connected
	//  - check if there is any data they sent, if so place into buffer
	//  - distribute to other clients.
	//  - unlock
	
	client_input_builder: String_Builder;
	init_string_builder(*client_input_builder);
	
	while true {
		lock(*ConnectedClientsMutex);
		
		for ClientIndex: 0..MAX_CLIENTS-1 {
			client_info := ConnectedClients.data + ClientIndex;
			if !client_info.connected continue;

			log("Checking client at %", ClientIndex);
			alive, data_is_ready_to_read := PollSocket(client_info.sock, 10);
			
			if !alive {
				log("Client % disconnected", ClientIndex);
				client_info.connected = false;
				continue;
			}
			
			if data_is_ready_to_read {
				data: [4096]u8;
				some_data: string;
				some_data.count = recv(client_info.sock, cast(*u8) *data, 4096, 0);
				some_data.data = data.data;
				
				append(*client_input_builder, some_data);
				append(*client_input_builder, "\n");
				
				log("Received: %", some_data);			
			}
		}
		
		if builder_string_length(*client_input_builder) > 0 {
			client_input_buffer := builder_to_string(*client_input_builder);
			for ClientIndex: 0..MAX_CLIENTS-1 {
				client_info := ConnectedClients.data + ClientIndex;
				if !client_info.connected continue;
				if send(client_info.sock, client_input_buffer.data, cast(s32) client_input_buffer.count, 0) < 0 {
					log_error("Failed to update client % with new input data", ClientIndex);
				}
			}
		}
		
		unlock(*ConnectedClientsMutex);
		
		sleep_milliseconds(1 * 1000);
	}
	
	thread_deinit(*IncomingConnectionThreadHandle);
	
	close_and_reset(*server_socket);
}