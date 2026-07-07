# Docker Homelab

My personal Docker Compose-based homelab environment with reverse proxy, dashboard, monitoring, media services, analytics, and more.

## 🚀 Overview

This repository contains a modular Docker Compose setup to create a complete homelab environment. The architecture uses Traefik as the backbone for routing traffic to various services, all manageable through Portainer's intuitive UI.

### 🛠️ Core Components

- **Reverse Proxy**
  - **Traefik**: Modern HTTP reverse proxy and load balancer with automatic SSL
- **Dashboard**

  - **Portainer**: Web-based Docker management UI

- **Monitoring Stack**

  - **Prometheus**: Metrics collection and storage
  - **Grafana**: Metrics visualization and dashboarding
  - **Node Exporter**: System metrics collection
  - **cAdvisor**: Container resource usage metrics

- **Media Services**

  - **Lavalink**: Audio player API for Discord bots

- **Analytics**

  - **Umami**: Privacy-focused website analytics

- **Development Tools**

  - **Code Server**: VS Code in the browser

- **Project Environments**
  - **Discord JS Bot**: Discord bot environment
  - **Strange API**: API service
  - **Flowbite Admin Dashboard**: Web dashboard

## 📋 Prerequisites

- Docker (recent version)
- Docker Compose v2
- A domain name (for SSL and service access)

## ⚙️ Setup

1. **Clone the Repository**

```sh
git clone https://github.com/saiteja-madha/docker-homelab.git
cd docker-homelab
```

2. **Set Up Environment Variables**

```sh
cp .env.example .env
```

Edit the `.env` file with your configuration:

- Set your domain name (`DOMAIN`)
- Configure email for Let's Encrypt (`EMAIL`)
- Set up authentication credentials (`BASIC_AUTH_USERS`)
- Configure service-specific variables

3. **Create a Docker Network**

```sh
docker network create proxy
```

4. **Deploy the Stack**

Deploy all services:

```sh
docker compose up -d
```

Or deploy specific services:

```sh
docker compose up -d traefik portainer
```

## 🔧 Maintenance

### Updating Services

To update a specific service:

```sh
docker compose pull [service]
docker compose up -d [service]
```

To update all services:

```sh
docker compose pull
docker compose up -d
```

### Viewing Logs

```sh
docker compose logs -f [service]
```

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues and pull requests to improve this setup.

## 📄 License

This project is licensed under the MIT License.
