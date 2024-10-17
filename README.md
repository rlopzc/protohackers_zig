# Protohackers in Zig

I'm solving the [protohackers](https://protohackers.com/) in Zig to learn more about networking and continue learning
Zig.

Each problem has it's corresponding file in `src`, e.g. `src/01_smoke_test.zig`. The common logic is extracted in
different files, e.g. `src/tcp_server.zig`.

I used CLI arguments to run a specific problem. To run the smoke test, run:

```sh
# Smoke test
zig build run -- 00

# Prime time
zig build run -- 01
```

## Docker

I dockerized this project to be run in any server. The images are exposed in Github Container Registry
[here](https://github.com/rlopzc/protohackers_zig/pkgs/container/protohackers_zig).

Building the images:

```sh
docker buildx build --platform linux/arm64,linux/amd64 -t ghcr.io/rlopzc/protohackers_zig:latest --push .
```

## Running the image in any cloud provider

1. Create a server in a cloud provider (I used Hetzner)
1. Pull the image. You can either pull the latest, which should contain most solutions, or a specific tag with a
   solution.
   ```sh
   docker pull ghcr.io/rlopzc/protohackers_zig:0_smoke
   # or
   docker pull ghcr.io/rlopzc/protohackers_zig:latest
   ```

1. Run the image. Remember to pass the problem number as an argument.
   ```sh
   docker run --rm --name protohackers_zig -p 3000:3000 --init ghcr.io/rlopzc/protohackers_zig:latest 00
   ```
1. Run the protohacker test using their website!
