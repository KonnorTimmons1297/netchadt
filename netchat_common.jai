Logical :: bool;

SERVER_IP := "127.0.0.1";
SERVER_PORT: u16 = 42069;

// NOTE: has not been tested on Unix based systems
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