# AWS RDS Oracle Database Deployment Guide
## Leap Cloud Deployment 2025

---

## Prerequisites

- AWS Account Access (Account Alias: **fse1team1**)
- Administrative credentials
- Region: **ap-south-1 (Mumbai)**

---

## Part 1: AWS RDS Database Setup

### Step 1: Console Authentication

1. Navigate to the [AWS Console](https://ap-south-1.console.aws.amazon.com/)
2. Enter your credentials:
   - **Account Alias:** fse1team1
   - **Username:** cropId
   - **Password:** [Your secure password]

### Step 2: Access RDS Service

1. Verify you're in the **ap-south-1 (Mumbai)** region
2. Search for and select **RDS** from the services menu

```
[IMAGE PLACEHOLDER: Screenshot showing AWS Console with region selector 
displaying "ap-south-1 (Mumbai)" and RDS service search]
```

### Step 3: Initialize Database Creation

1. Navigate to: **AWS Console → RDS → Databases → Create Database**
2. Select **Standard create** option
3. Choose **Oracle** as the database engine

```
[IMAGE PLACEHOLDER: Screenshot of "Create Database" page showing 
"Standard create" option selected and Oracle database engine highlighted]
```

### Step 4: Configure Database Engine

Select the following specifications:
- **RDS Type:** Amazon RDS
- **Edition:** Oracle Enterprise Edition
- **Engine Version:** Oracle 19
- **Template:** Dev/Test

```
[IMAGE PLACEHOLDER: Screenshot showing Oracle Enterprise Edition selection 
and Engine Version dropdown with Oracle 19 selected]
```

```
[IMAGE PLACEHOLDER: Screenshot showing Dev/Test template option selected]
```

### Step 5: Database Instance Settings

Configure your database instance:

**Instance Identifier:**
- Format: `aXXXXXX-rds` (replace X with your identifier)

**Credentials:**
- **Master username:** admin
- **Master password:** LA2025fmr
- **Password Management:** Self Managed

```
[IMAGE PLACEHOLDER: Screenshot showing Settings section with DB instance 
identifier field, Master username set to "admin", and password configuration 
with "Self Managed" option selected]
```

### Step 6: Instance Configuration

Select compute resources:
- **Instance Class:** Burstable classes
- **Instance Type:** db.t3.small

```
[IMAGE PLACEHOLDER: Screenshot of Instance Configuration section showing 
Burstable classes dropdown with db.t3.small selected]
```

### Step 7: Storage Configuration

Configure storage settings:
- **Storage Type:** General Purpose SSD (gp3)
- **Allocated Storage:** 20 GB
- **Provisioned IOPS:** Not required

```
[IMAGE PLACEHOLDER: Screenshot showing Storage section with General Purpose 
SSD (gp3) selected and Allocated storage set to 20 GB]
```

```
[IMAGE PLACEHOLDER: Screenshot showing storage autoscaling and IOPS 
configuration options]
```

### Step 8: Connectivity Settings

Configure network access:
- **Public Access:** YES (Enable public accessibility)

```
[IMAGE PLACEHOLDER: Screenshot of Connectivity section showing Public 
access set to "Yes"]
```

```
[IMAGE PLACEHOLDER: Screenshot showing additional connectivity and 
database authentication options]
```

### Step 9: Review and Create

1. Review all configurations carefully
2. Check estimated billing costs
3. Click **Create Database**
4. Wait approximately **15 minutes** for database creation to complete
5. **Copy the Endpoint** once the database is available

```
[IMAGE PLACEHOLDER: Screenshot showing estimated monthly costs summary 
and "Create Database" button]
```

---

## Part 2: SQL*Plus Client Installation

### Installing Required Packages

Execute the following commands on your Linux system:

```bash
# Install wget utility
sudo yum install wget

# Download Oracle Instant Client packages
wget https://download.oracle.com/otn_software/linux/instantclient/214000/instantclient-basic-linux.x64-21.4.0.0.0dbru.zip

wget https://download.oracle.com/otn_software/linux/instantclient/214000/instantclient-sqlplus-linux.x64-21.4.0.0.0dbru.zip
```

### Extract and Configure

```bash
# Create installation directory
sudo mkdir -p /opt/oracle

# Install unzip utility
sudo yum install unzip

# Extract both packages
sudo unzip -d /opt/oracle instantclient-basic-linux.x64-21.4.0.0.0dbru.zip
sudo unzip -d /opt/oracle instantclient-sqlplus-linux.x64-21.4.0.0.0dbru.zip

# Verify installation files
cd /opt/oracle/instantclient_21_4 && find . -type f | sort
```

### Set Environment Variables

```bash
# Configure library path
export LD_LIBRARY_PATH=/opt/oracle/instantclient_21_4:$LD_LIBRARY_PATH
export PATH=$LD_LIBRARY_PATH:$PATH

# Apply changes
source ~/.bashrc
```

### Install Dependencies

```bash
# Install required libraries
sudo yum install libaio

# Verify SQL*Plus installation
sqlplus -V
```

---

## Part 3: Database Connection and Schema Setup

### Establishing Connection

Connect to your RDS instance using SQL*Plus:

```sql
sqlplus admin/LA2025fmr@a900003-rds.cj6ui28e0bu9.ap-south-1.rds.amazonaws.com:1521/ORCL
```

**Note:** Replace the endpoint with your actual RDS endpoint copied in Step 9.

### Creating Database Schema

Execute your schema creation script:

```sql
@/path/to/schema.sql
```

### Verify Table Creation

List all created tables:

```sql
SELECT table_name FROM user_tables;
```

### Exit SQL*Plus

```sql
QUIT
```

---

## Important Notes

- **Security:** Ensure your RDS security group allows inbound connections on port 1521
- **Cost Management:** Monitor your AWS billing dashboard regularly
- **Backup:** Consider enabling automated backups for production databases
- **Performance:** The db.t3.small instance is suitable for development/testing workloads

---

## Troubleshooting

**Connection Issues:**
- Verify security group rules allow your IP address
- Confirm the database status is "Available"
- Check that public accessibility is enabled

**SQL*Plus Installation Issues:**
- Ensure all dependencies (libaio) are installed
- Verify environment variables are set correctly
- Restart your terminal session after configuration

---

## Support Resources

For additional assistance, consult:
- AWS RDS Documentation
- Oracle Database 19c Documentation
- Your organization's cloud operations team
