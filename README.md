# NetChadt

A simple local area network chat program. Consists of a server to which many clients can connect.

## Build & Run Server

Build Command: `jai netchat_server.jai`

Run Command: `netchat_server` -- server address defaults to `127.0.0.1:42069`
* Optionally specify address: `-address=0.0.0.0`
* Optionally specify port: `80085`

## Build & Run Client

Build Command: `jai netchat_client.jai`

Run Command: `netchat_client 127.0.0.1 42069`
* The server address and port are required.

## Notes

* Has not been tested on MacOS/Linux
