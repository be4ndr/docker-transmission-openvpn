# OpenVPN and Transmission with WebUI

This container contains OpenVPN and Transmission with a configuration
where Transmission is running only when OpenVPN has an active tunnel.
It has built-in support for many popular VPN providers to make the setup easier.

This is a downstream fork of [haugene/docker-transmission-openvpn](https://github.com/haugene/docker-transmission-openvpn). The examples below pull the upstream `haugene/transmission-openvpn` image; build and tag this repository locally to run fork changes. This fork does not publish images or release tags through GitHub Actions. See [downstream development](docs/downstream-development.md) for its branch policy.

## Read this first

The upstream documentation is hosted on GitHub Pages:

https://haugene.github.io/docker-transmission-openvpn/

For upstream behavior and general questions, see the upstream [discussions](https://github.com/haugene/docker-transmission-openvpn/discussions).

For a fork-specific bug, open an issue in this fork with enough detail to reproduce it. Remove credentials and tokens from logs and configuration before sharing them.

## Quick Start

These examples show valid setups using PIA as the provider for both
docker run and docker-compose. Note that you should read some documentation
at some point, but this is a good place to start.

### Docker run

```
$ docker run --cap-add=NET_ADMIN -d \
              -v /your/storage/path/:/data \
              -v /your/config/path/:/config \
              -e OPENVPN_PROVIDER=PIA \
              -e OPENVPN_CONFIG=france \
              -e OPENVPN_USERNAME=user \
              -e OPENVPN_PASSWORD=pass \
              -e LOCAL_NETWORK=192.168.0.0/16 \
              --log-driver json-file \
              --log-opt max-size=10m \
              -p 9091:9091 \
              haugene/transmission-openvpn
```

### Podman run

Beware: container is run as privileged, meaning it has full access to host OS.

```
$ podman run --privileged -d \
              -v /your/storage/path/:/data \
              -v /your/config/path/:/config \
              -e OPENVPN_PROVIDER=PIA \
              -e OPENVPN_CONFIG=france \
              -e OPENVPN_USERNAME=user \
              -e OPENVPN_PASSWORD=pass \
              -e LOCAL_NETWORK=192.168.0.0/16 \
              --log-driver k8s-file \
              --log-opt max-size=10m \
              -p 9091:9091 \
              haugene/transmission-openvpn
```

### Docker version 3.x Compose
```
version: '3.3'
services:
    transmission-openvpn:
        cap_add:
            - NET_ADMIN
        volumes:
            - '/your/storage/path/:/data'
            - '/your/config/path/:/config'
        environment:
            - OPENVPN_PROVIDER=PIA
            - OPENVPN_CONFIG=france
            - OPENVPN_USERNAME=user
            - OPENVPN_PASSWORD=pass
            - LOCAL_NETWORK=192.168.0.0/16
        logging:
            driver: json-file
            options:
                max-size: 10m
        ports:
            - '9091:9091'
        image: haugene/transmission-openvpn
```

### Docker version 2.x Compose
```
version: "2.0"
services:
    transmission-openvpn:
        container_name: transmission
        cap_add:
            - NET_ADMIN
        volumes:
            - '/your/storage/path/:/data'
            - '/your/config/path/:/config'
        environment:
            - OPENVPN_PROVIDER=PIA
            - OPENVPN_CONFIG=france
            - OPENVPN_USERNAME=user
            - OPENVPN_PASSWORD=pass
            - LOCAL_NETWORK=192.168.0.0/16
        logging:
            driver: "json-file"
            options:
                max-size: 10m
        ports:
            - 9091:9091
        image: haugene/transmission-openvpn
```

## Known issues

If you've been running a stable setup that has recently started to fail, please check your logs.
Are you seeing `curl: (6) getaddrinfo() thread failed to start` or `WARNING: initial DNS resolution test failed`?
Then have a look at [#2410](https://github.com/haugene/docker-transmission-openvpn/issues/2410)
and [this comment](https://github.com/haugene/docker-transmission-openvpn/issues/2410#issuecomment-1319299598)
in particular. There is a fix and a workaround available.

## Upstream image tags

The `latest`, versioned, `edge`, and `dev` tags for `haugene/transmission-openvpn` are maintained by upstream. They do not identify builds from this fork.
