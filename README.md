# Docker Homelab

A collection of Docker Compose configurations for managing a homelab environment with Traefik and Portainer.

## Overview

This repository contains Docker Compose files to set up and manage a homelab environment. The setup includes:

- **Traefik**: A modern reverse proxy and load balancer.
- **Portainer**: A lightweight management UI which allows you to easily manage your Docker environments.

## Prerequisites

- Docker
- Docker Compose

## Setup

1. Clone the Repository

```sh
git clone https://github.com/saiteja-madha/docker-homelab.git
cd docker-homelab
```

2. Rename `.env.example` to `.env` File and update the variables.

3. Create a docker network called `proxy`

```sh
docker network create proxy
```

4. Run Docker Compose

```sh
docker-compose up -d
```

## Usage
- Access Traefik Dashboard
Navigate to https://traefik.yourdomain.com to access the Traefik dashboard.

- Access Portainer
Navigate to https://portainer.yourdomain.com to access the Portainer UI.

## Contributing

Feel free to submit issues and pull requests to improve this setup.

## License

This project is licensed under the MIT License.