# Docker Containerization & Compose Guide
## Leap Cloud Deployment 2025 - Day 2

---

## Prerequisites

- ✅ Completed Day 1 (RDS Oracle Database setup with data)
- ✅ Active RVC (Remote Virtual Computing) environment
- ✅ Docker installed on your RVC
- ✅ JFrog Artifactory access credentials
- ✅ Application source code in `a######-projectName` repository
- ✅ Git configured and authenticated

---

## Part 1: Git Branch Setup

### Step 1: Create Feature Branch

Before starting Docker work, create and checkout to a new branch:

```bash
# Navigate to your project repository
cd /path/to/a######-projectName

# Create and checkout to feature branch
git checkout -b feature/docker

# Verify you're on the correct branch
git branch
```

**Expected Output:**
```
* feature/docker
  main
```

---

## Part 2: Docker Environment Setup

### Step 1: Verify Docker Installation

```bash
# Check Docker version
docker --version

# Check Docker service status
sudo systemctl status docker

# If Docker is not running, start it
sudo systemctl start docker

# Enable Docker to start on boot
sudo systemctl enable docker
```

### Step 2: Authenticate with JFrog Artifactory

```bash
# Docker login to your JFrog Artifactory
docker login leapfse#.jfrog.io

# Enter your credentials when prompted:
# Username: leapfse#
# Password: fse#Deploy@Cloud
```

**Success Message:** `Login Succeeded`

---

## Part 3: Understanding the Application Architecture

You will containerize **4 microservices**:

1. **Frontend** (Angular) - User interface layer
2. **Midtier** (Node.js) - Business logic layer
3. **Backend** (Spring Boot) - Data access layer connecting to RDS Oracle
4. **FMTS-Node** (Node.js) - File Management & Transfer Service

### Application Flow
```
┌─────┐     ┌──────────┐     ┌─────────┐     ┌─────────┐     ┌──────────────┐
│User │ --> │Frontend  │ --> │Midtier  │ --> │Backend  │ --> │RDS Oracle DB │
└─────┘     │(Angular) │     │(Node.js)│     │(Spring) │     │              │
            └──────────┘     └────┬────┘     └─────────┘     └──────────────┘
                                  │
                                  ↓
                            ┌──────────┐
                            │FMTS-Node │
                            │(File Svc)│
                            └──────────┘
```

---

## Part 4: Docker Naming Convention

### Standardized Image Format

```
<corpid>-<component>:<version>
```

### Examples
- `a######-frontend:1.0`
- `a######-midtier:1.0`
- `a######-backend:1.0`
- `a######-fmts:1.0`

### JFrog Artifactory Path
```
leapfse#.jfrog.io/fse#team#/<image-name>:<version>
```

**Complete Example:**
```
leapfse#.jfrog.io/fse#team#/a######-frontend:1.0
```

---

## Part 5: Containerization Process

### Component 1: Frontend (Angular Application)

#### Step 1: Navigate to Frontend Directory
```bash
cd ~/a######-projectName/frontend
pwd  # Verify you're in the correct directory
```

#### Step 2: Create Dockerfile
```bash
touch Dockerfile
```

#### Step 3: Dockerfile Content for Angular

```dockerfile
# Multi-stage build for Angular application
FROM node:18-alpine AS build

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application source
COPY . .

# Build Angular application for production
RUN npm run build --prod

# Stage 2: Serve with Nginx
FROM nginx:alpine

# Copy built application from build stage
COPY --from=build /app/dist/* /usr/share/nginx/html/

# Expose port (change according to your application)
EXPOSE 4200

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
```

**⚠️ Important:** Update `EXPOSE 4200` to match your application's port

#### Step 4: Build Docker Image
```bash
docker build -t a######-frontend:1.0 .
```

#### Step 5: Tag for JFrog Artifactory
```bash
docker tag a######-frontend:1.0 leapfse#.jfrog.io/fse#team#/a######-frontend:1.0
```

#### Step 6: Push to JFrog Artifactory
```bash
docker push leapfse#.jfrog.io/fse#team#/a######-frontend:1.0
```

---

### Component 2: Midtier (Node.js Application)

#### Step 1: Navigate to Midtier Directory
```bash
cd ~/a######-projectName/midtier
pwd  # Verify you're in the correct directory
```

#### Step 2: Create Dockerfile
```bash
touch Dockerfile
```

#### Step 3: Dockerfile Content for Node.js Midtier

```dockerfile
# Use official Node.js LTS image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application source
COPY . .

# Expose port (change according to your application)
EXPOSE 3000

# Set environment variables
ENV NODE_ENV=production

# Start the application
CMD ["node", "server.js"]
```

**⚠️ Important:** 
- Update `EXPOSE 3000` to your actual port
- Change `server.js` to your main entry file (e.g., `app.js`, `index.js`)

#### Step 4: Build Docker Image
```bash
docker build -t a######-midtier:1.0 .
```

#### Step 5: Tag for JFrog Artifactory
```bash
docker tag a######-midtier:1.0 leapfse#.jfrog.io/fse#team#/a######-midtier:1.0
```

#### Step 6: Push to JFrog Artifactory
```bash
docker push leapfse#.jfrog.io/fse#team#/a######-midtier:1.0
```

---

### Component 3: Backend (Spring Boot Application)

#### Step 1: Navigate to Backend Directory
```bash
cd ~/a######-projectName/backend
pwd  # Verify you're in the correct directory
```

#### Step 2: Create Dockerfile
```bash
touch Dockerfile
```

#### Step 3: Dockerfile Content for Spring Boot

```dockerfile
# Multi-stage build for Spring Boot
FROM maven:3.8-openjdk-17 AS build

# Set working directory
WORKDIR /app

# Copy pom.xml and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# Stage 2: Runtime
FROM openjdk:17-jdk-slim

# Set working directory
WORKDIR /app

# Copy JAR from build stage
COPY --from=build /app/target/*.jar app.jar

# Expose port (change according to your application)
EXPOSE 8080

# Environment variables for RDS connection
ENV SPRING_DATASOURCE_URL=jdbc:oracle:thin:@<your-rds-endpoint>:1521/ORCL
ENV SPRING_DATASOURCE_USERNAME=admin
ENV SPRING_DATASOURCE_PASSWORD=LA2025fmr

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**🔴 Critical Configuration:**
- Replace `<your-rds-endpoint>` with your actual RDS endpoint from Day 1
- Update `EXPOSE 8080` to your application's port
- Verify database credentials match Day 1 setup

#### Step 4: Build Docker Image
```bash
docker build -t a######-backend:1.0 .
```

#### Step 5: Tag for JFrog Artifactory
```bash
docker tag a######-backend:1.0 leapfse#.jfrog.io/fse#team#/a######-backend:1.0
```

#### Step 6: Push to JFrog Artifactory
```bash
docker push leapfse#.jfrog.io/fse#team#/a######-backend:1.0
```

---

### Component 4: FMTS-Node (File Management Service)

#### Step 1: Navigate to FMTS Directory
```bash
cd ~/a######-projectName/fmts
pwd  # Verify you're in the correct directory
```

#### Step 2: Create Dockerfile
```bash
touch Dockerfile
```

#### Step 3: Dockerfile Content for FMTS-Node

```dockerfile
# Use official Node.js LTS image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application source
COPY . .

# Create directory for file uploads
RUN mkdir -p /app/uploads

# Expose port (change according to your application)
EXPOSE 5000

# Set environment variables
ENV NODE_ENV=production

# Start the application
CMD ["node", "index.js"]
```

**⚠️ Important:** 
- Update `EXPOSE 5000` to your actual port
- Change `index.js` to your main entry file

#### Step 4: Build Docker Image
```bash
docker build -t a######-fmts:1.0 .
```

#### Step 5: Tag for JFrog Artifactory
```bash
docker tag a######-fmts:1.0 leapfse#.jfrog.io/fse#team#/a######-fmts:1.0
```

#### Step 6: Push to JFrog Artifactory
```bash
docker push leapfse#.jfrog.io/fse#team#/a######-fmts:1.0
```

---

## Part 6: Docker Compose Deployment

### Overview

Docker Compose allows you to run all microservices together with a single command, managing inter-service communication and networking automatically.

### Step 1: Create Docker Compose File

Navigate to your project root and create the compose file:

```bash
# Navigate to project root
cd ~/a######-projectName

# Create docker-compose.yml
touch docker-compose.yml
```

### Step 2: Docker Compose Configuration

Create your `docker-compose.yml` with the following structure:

```yaml
version: '3.8'

services:
  # Frontend Service
  frontend:
    image: leapfse#.jfrog.io/fse#team#/a######-frontend:1.0
    container_name: a######-frontend
    ports:
      - "4200:4200"
    networks:
      - app-network
    depends_on:
      - midtier
    restart: unless-stopped

  # Midtier Service
  midtier:
    image: leapfse#.jfrog.io/fse#team#/a######-midtier:1.0
    container_name: a######-midtier
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - BACKEND_URL=http://backend:8080
      - FMTS_URL=http://fmts:5000
    networks:
      - app-network
    depends_on:
      - backend
      - fmts
    restart: unless-stopped

  # Backend Service
  backend:
    image: leapfse#.jfrog.io/fse#team#/a######-backend:1.0
    container_name: a######-backend
    ports:
      - "8080:8080"
    environment:
      - SPRING_DATASOURCE_URL=jdbc:oracle:thin:@a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com:1521/ORCL
      - SPRING_DATASOURCE_USERNAME=admin
      - SPRING_DATASOURCE_PASSWORD=LA2025fmr
      - SPRING_DATASOURCE_DRIVER_CLASS_NAME=oracle.jdbc.OracleDriver
      - SPRING_JPA_DATABASE_PLATFORM=org.hibernate.dialect.Oracle12cDialect
    networks:
      - app-network
    restart: unless-stopped

  # FMTS Service
  fmts:
    image: leapfse#.jfrog.io/fse#team#/a######-fmts:1.0
    container_name: a######-fmts
    ports:
      - "5000:5000"
    environment:
      - NODE_ENV=production
    volumes:
      - fmts-uploads:/app/uploads
    networks:
      - app-network
    restart: unless-stopped

networks:
  app-network:
    driver: bridge

volumes:
  fmts-uploads:
    driver: local
```

### Step 3: Configure Service Communication

**🔑 Key Concept:** In Docker Compose, services communicate using their **service names** as hostnames.

#### Before (Incorrect - using localhost):
```javascript
// ❌ Wrong - won't work in Docker
const BACKEND_URL = "http://localhost:8080";
const FMTS_URL = "http://localhost:5000";
```

#### After (Correct - using service names):
```javascript
// ✅ Correct - uses Docker Compose service names
const BACKEND_URL = "http://backend:8080";
const FMTS_URL = "http://fmts:5000";
```

**Service Name Reference:**
| Service | Docker Hostname | External Access (from host) |
|---------|----------------|----------------------------|
| frontend | `frontend:4200` | `localhost:4200` |
| midtier | `midtier:3000` | `localhost:3000` |
| backend | `backend:8080` | `localhost:8080` |
| fmts | `fmts:5000` | `localhost:5000` |

### Step 4: Update Application Configuration

#### A. Frontend Configuration

Update your Angular environment files:

**`src/environments/environment.prod.ts`:**
```typescript
export const environment = {
  production: true,
  apiUrl: 'http://midtier:3000/api',  // Use service name
  fmtsUrl: 'http://fmts:5000'
};
```

#### B. Midtier Configuration

Update your Node.js configuration:

**`.env` or `config.js`:**
```javascript
BACKEND_HOST=backend
BACKEND_PORT=8080
FMTS_HOST=fmts
FMTS_PORT=5000
```

#### C. Backend Configuration

Update your Spring Boot `application.properties`:

```properties
# Database Configuration
spring.datasource.url=jdbc:oracle:thin:@a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com:1521/ORCL
spring.datasource.username=admin
spring.datasource.password=LA2025fmr
spring.datasource.driver-class-name=oracle.jdbc.OracleDriver
spring.jpa.database-platform=org.hibernate.dialect.Oracle12cDialect

# Connection Pool Settings
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5
```

### Step 5: Update Database Credentials

**🔴 Critical:** Database credentials must match in **TWO** locations:

#### Location 1: docker-compose.yml
```yaml
backend:
  environment:
    - SPRING_DATASOURCE_URL=jdbc:oracle:thin:@a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com:1521/ORCL
    - SPRING_DATASOURCE_USERNAME=admin
    - SPRING_DATASOURCE_PASSWORD=LA2025fmr
```

#### Location 2: Backend Application Properties
```properties
spring.datasource.username=admin
spring.datasource.password=LA2025fmr
```

### Step 6: Pre-Deployment Validation

**Validation Checklist:**

```bash
# 1. Verify all images exist locally
docker images | grep a######

# 2. Check Docker Compose syntax
docker-compose config

# 3. Verify no port conflicts
netstat -tulpn | grep -E '4200|3000|8080|5000'

# 4. Confirm RDS endpoint is correct
nslookup a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com

# 5. Test RDS connectivity
nc -zv a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com 1521
```

**Manual Checklist:**
- ✅ Database credentials match in docker-compose.yml and application config
- ✅ RDS endpoint is correct (from Day 1)
- ✅ Service names are used in application URLs (not localhost)
- ✅ Port configurations don't conflict with existing services
- ✅ All Docker images are built and available
- ✅ Git branch is set to `feature/docker`

### Step 7: Launch Application

#### Start All Services

```bash
# Start in detached mode (background)
docker-compose up -d

# Or start with logs visible (foreground)
docker-compose up

# Start and rebuild if needed
docker-compose up --build -d
```

**Expected Output:**
```
Creating network "a######-projectname_app-network" with driver "bridge"
Creating volume "a######-projectname_fmts-uploads" with local driver
Creating a######-backend ... done
Creating a######-fmts    ... done
Creating a######-midtier ... done
Creating a######-frontend ... done
```

#### Monitor Container Status

```bash
# Check all containers are running
docker-compose ps

# Watch logs in real-time
docker-compose logs -f

# Check specific service logs
docker-compose logs -f backend
```

### Step 8: Verify Deployment

#### A. Check Container Status

```bash
docker-compose ps
```

**Expected Output:**
```
        Name                      Command               State           Ports
----------------------------------------------------------------------------------------
a######-backend    java -jar app.jar                Up      0.0.0.0:8080->8080/tcp
a######-fmts       node index.js                    Up      0.0.0.0:5000->5000/tcp
a######-frontend   nginx -g daemon off;             Up      0.0.0.0:4200->4200/tcp
a######-midtier    node server.js                   Up      0.0.0.0:3000->3000/tcp
```

#### B. Test Application Endpoints

```bash
# Test Frontend
curl http://localhost:4200

# Test Midtier
curl http://localhost:3000/health

# Test Backend
curl http://localhost:8080/actuator/health

# Test FMTS
curl http://localhost:5000/health
```

#### C. Verify Database Connection

```bash
# Check backend logs for database connection
docker-compose logs backend | grep -i "database\|oracle\|connection"
```

**Success Indicators:**
- ✅ All containers show "Up" status
- ✅ No error messages in logs
- ✅ Application responds to HTTP requests
- ✅ Backend successfully connects to RDS Oracle database

---

## Part 7: Troubleshooting

### Common Issues and Solutions

#### Issue 1: Port Already in Use

**Error:**
```
ERROR: for frontend  Cannot start service frontend: driver failed programming external connectivity on endpoint a######-frontend: Bind for 0.0.0.0:4200 failed: port is already allocated
```

**Solution:**
```bash
# Find process using the port
sudo lsof -i :4200
# or
sudo netstat -tulpn | grep 4200

# Kill the process
sudo kill -9 <PID>

# Or change port in docker-compose.yml
ports:
  - "4201:4200"  # Use different host port
```

#### Issue 2: Database Connection Refused

**Error:**
```
java.net.ConnectException: Connection refused: connect
```

**Solutions:**
1. Verify RDS endpoint is correct
2. Check security group allows your IP
3. Confirm database credentials
4. Test connectivity:
   ```bash
   nc -zv a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com 1521
   ```

#### Issue 3: Image Not Found

**Error:**
```
Error response from daemon: pull access denied for leapfse#.jfrog.io/fse#team#/a######-frontend
```

**Solution:**
```bash
# Re-authenticate with JFrog
docker login leapfse#.jfrog.io

# Verify image exists locally
docker images | grep a######-frontend

# If not found, rebuild and push
cd ~/a######-projectName/frontend
docker build -t a######-frontend:1.0 .
docker tag a######-frontend:1.0 leapfse#.jfrog.io/fse#team#/a######-frontend:1.0
docker push leapfse#.jfrog.io/fse#team#/a######-frontend:1.0
```

#### Issue 4: Container Exits Immediately

**Error:**
```
a######-backend exited with code 1
```

**Solution:**
```bash
# Check container logs for detailed error
docker-compose logs backend

# Common causes and fixes:
# - Missing environment variables → Add to docker-compose.yml
# - Application crash → Check application logs
# - Incorrect CMD/ENTRYPOINT → Review Dockerfile
```

#### Issue 5: Service Cannot Communicate

**Error:**
```
ECONNREFUSED backend:8080
```

**Solution:**
1. Verify all services are on the same network:
   ```bash
   docker network inspect a######-projectname_app-network
   ```
2. Check service names match in configuration
3. Ensure `depends_on` is configured correctly
4. Verify services are running:
   ```bash
   docker-compose ps
   ```

### Debugging Commands

```bash
# View detailed logs for all services
docker-compose logs -f --tail=100

# Execute command inside running container
docker-compose exec backend bash
docker-compose exec midtier sh

# Inspect container details
docker inspect a######-backend

# Check network connectivity between containers
docker-compose exec midtier ping backend
docker-compose exec midtier curl http://backend:8080/actuator/health

# Restart specific service
docker-compose restart backend

# Stop all services
docker-compose down

# Stop and remove volumes (⚠️ deletes data)
docker-compose down -v

# View resource usage
docker stats
```

---

## Part 8: Best Practices & Optimization

### 1. .dockerignore File

Create `.dockerignore` in each component directory:

```
# Dependencies
node_modules/
npm-debug.log*

# Build outputs
dist/
build/
target/
*.jar
*.war

# IDE files
.idea/
.vscode/
*.iml

# Git
.git/
.gitignore

# Environment
.env
.env.local

# Logs
*.log
logs/

# OS files
.DS_Store
Thumbs.db

# Testing
coverage/
.nyc_output/
```

### 2. Environment Variables

**Create `.env` file for sensitive data:**

```bash
# .env (add to .gitignore!)
JFROG_URL=leapfse#.jfrog.io
JFROG_REPO=fse#team#
CORP_ID=a######
VERSION=1.0

# Database
DB_ENDPOINT=a######-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com
DB_USERNAME=admin
DB_PASSWORD=LA2025fmr
DB_NAME=ORCL
```

**Reference in docker-compose.yml:**

```yaml
backend:
  environment:
    - SPRING_DATASOURCE_URL=jdbc:oracle:thin:@${DB_ENDPOINT}:1521/${DB_NAME}
    - SPRING_DATASOURCE_USERNAME=${DB_USERNAME}
    - SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}
```

### 3. Resource Limits

Add resource constraints to prevent container overconsumption:

```yaml
services:
  backend:
    image: leapfse#.jfrog.io/fse#team#/a######-backend:1.0
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M
```

### 4. Health Checks

Add health checks for automatic container recovery:

```yaml
services:
  backend:
    image: leapfse#.jfrog.io/fse#team#/a######-backend:1.0
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### 5. Logging Configuration

Configure logging drivers:

```yaml
services:
  backend:
    image: leapfse#.jfrog.io/fse#team#/a######-backend:1.0
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

---

## Part 9: Cleanup and Maintenance

### Stop and Remove Services

```bash
# Stop all services (containers remain)
docker-compose stop

# Stop and remove containers
docker-compose down

# Stop and remove everything including volumes
docker-compose down -v

# Stop and remove everything including images
docker-compose down --rmi all
```

### System Cleanup

```bash
# Remove unused images
docker image prune -a

# Remove unused containers
docker container prune

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune

# Clean everything (careful!)
docker system prune -a --volumes
```

### Monitor Resources

```bash
# View resource usage
docker stats

# Check disk usage
docker system df

# Detailed breakdown
docker system df -v
```

---

## Part 10: Day 2 Deliverables

By the end of Day 2, you should have:

- ✅ Feature branch `feature/docker` created and active
- ✅ 4 Docker images built successfully
- ✅ All images tagged with proper naming convention: `a######-<component>:1.0`
- ✅ All images pushed to JFrog Artifactory
- ✅ `docker-compose.yml` file configured and tested
- ✅ All services running and communicating correctly
- ✅ Backend successfully connecting to RDS Oracle database
- ✅ Application accessible via `localhost` ports
- ✅ All changes committed to Git

### Final Verification Command

```bash
# Run this comprehensive check
docker-compose ps && \
curl -s http://localhost:4200 > /dev/null && echo "✅ Frontend OK" || echo "❌ Frontend FAIL" && \
curl -s http://localhost:3000/health > /dev/null && echo "✅ Midtier OK" || echo "❌ Midtier FAIL" && \
curl -s http://localhost:8080/actuator/health > /dev/null && echo "✅ Backend OK" || echo "❌ Backend FAIL" && \
curl -s http://localhost:5000/health > /dev/null && echo "✅ FMTS OK" || echo "❌ FMTS FAIL"
```

---

## Part 11: Quick Reference

### Essential Docker Commands

| Command | Description |
|---------|-------------|
| `docker build -t <name>:<tag> .` | Build image from Dockerfile |
| `docker tag <source> <target>` | Tag an image |
| `docker push <image>:<tag>` | Push image to registry |
| `docker images` | List all images |
| `docker ps` | List running containers |
| `docker ps -a` | List all containers |
| `docker logs <container>` | View container logs |
| `docker exec -it <container> bash` | Access container shell |
| `docker stop <container>` | Stop container |
| `docker rm <container>` | Remove container |
| `docker rmi <image>` | Remove image |
| `docker system prune -a` | Clean up everything |

### Essential Docker Compose Commands

| Command | Description |
|---------|-------------|
| `docker-compose up -d` | Start all services in background |
| `docker-compose up --build` | Rebuild and start services |
| `docker-compose down` | Stop and remove containers |
| `docker-compose ps` | List services status |
| `docker-compose logs -f` | Stream logs from all services |
| `docker-compose logs <service>` | View specific service logs |
| `docker-compose restart <service>` | Restart specific service |
| `docker-compose exec <service> bash` | Access service shell |
| `docker-compose config` | Validate compose file |
| `docker-compose pull` | Pull latest images |

---

## Support and Resources

**Need Help?**
1. Check container logs: `docker-compose logs -f`
2. Verify configuration: `docker-compose config`
3. Test connectivity: `docker-compose exec midtier curl http://backend:8080`
4. Contact instructors or teaching assistants
5. Review Docker documentation: https://docs.docker.com

**Remember:** Most issues stem from:
- Incorrect service names in application configuration
- Mismatched database credentials
- Port conflicts
- Missing environment variables

---

## Next Steps (Day 3 Preview)

Tomorrow, you will:
- Deploy containers to Kubernetes cluster
- Create Kubernetes Deployments and Services
- Configure Ingress for external access
- Set up ConfigMaps and Secrets
- Implement auto-scaling and load balancing

**Prepare for Day 3:**
- Ensure all Docker images are in JFrog Artifactory
- Document your service ports and configurations
- Keep your RDS endpoint information handy
- Commit and push all changes to `feature/docker` branch

---

**Remember:** Docker containerization ensures consistency across environments. Your application should behave identically whether running on your local machine, RVC, or production Kubernetes cluster!