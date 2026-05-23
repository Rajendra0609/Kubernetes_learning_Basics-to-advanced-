# Ansible: Comprehensive Guide for Learning & Production

> **Approach**: Practical first, theory second — every section leads with hands-on examples and real-world scenarios, then explains the *why* behind them. Error handling is woven into each topic.

---

## Table of Contents

1. [Introduction to Ansible](#1-introduction-to-ansible)
2. [Installation and Setup](#2-installation-and-setup)
3. [Ansible Playbooks](#3-ansible-playbooks)
4. [Tasks and Modules](#4-tasks-and-modules)
5. [Variables and Facts](#5-variables-and-facts)
6. [Control Flow](#6-control-flow)
7. [Handlers and Notifications](#7-handlers-and-notifications)
8. [Roles](#8-roles)
9. [Templates](#9-templates)
10. [Vault](#10-vault)
11. [Error Handling and Debugging](#11-error-handling-and-debugging)
12. [Advanced Topics](#12-advanced-topics)

---

## 1. Introduction to Ansible

### 1.1 What is Ansible?

Ansible is an open-source **IT automation platform** that lets you describe infrastructure state in simple YAML files called *Playbooks* and enforce that state across hundreds of servers — without installing anything on those servers.

**When would you reach for Ansible over a shell script?**

| Situation | Shell Script | Ansible |
|---|---|---|
| Run once, throw away | ✅ | Overkill |
| Idempotent config management | ❌ | ✅ |
| Multi-server orchestration | Painful | ✅ |
| Audit trail / change review | Hard | ✅ (YAML in Git) |
| Secrets management | Manual | ✅ (Vault) |

### 1.2 Key Concepts

#### Idempotence

An operation is **idempotent** if running it multiple times produces the same result as running it once. This is the cornerstone of Ansible's reliability.

```yaml
# This task is idempotent — running it 10 times has the same effect as running it once.
- name: Ensure nginx is installed
  ansible.builtin.package:
    name: nginx
    state: present   # "present" = install if missing, do nothing if already there
```

If `nginx` is already installed, Ansible reports `ok` (no change). If not, it installs it and reports `changed`. **Never** `changed` when nothing actually changed — this is what makes Ansible safe to run in cron or CI/CD.

#### Agentless Architecture

Ansible connects to managed nodes over **SSH** (Linux/macOS) or **WinRM** (Windows). There is no daemon, no agent binary, no perpetual network listener on the managed node. This means:

- No agent lifecycle to manage.
- No firewall rules for agent ports.
- Works on fresh OS installs immediately.

Internally, Ansible copies a small Python script to the remote host, executes it, then removes it. The managed node only needs Python ≥ 2.7 (Python 3 preferred).

#### Push vs. Pull

| Model | How it works | Examples |
|---|---|---|
| **Push** (Ansible default) | Control node pushes config to managed nodes on demand | `ansible-playbook site.yml` |
| **Pull** | Managed nodes pull config from a central server on a schedule | Puppet, Chef, `ansible-pull` |

Ansible supports both: the standard push model is most common; `ansible-pull` exists for edge/satellite nodes that can't be reached inbound.

### 1.3 Use Cases and Benefits

**Configuration Management** — Ensure every web server has the same `nginx.conf`, OS packages, and user accounts.

**Application Deployment** — Zero-downtime rolling deploys across a fleet.

**Infrastructure Provisioning** — Spin up EC2 instances, VPCs, and RDS clusters via cloud modules.

**Security Hardening** — Apply CIS benchmarks, manage firewall rules, rotate credentials.

**Orchestration** — Coordinate multi-tier deployments: DB migrations → app deploy → cache flush → smoke test.

---

## 2. Installation and Setup

### 2.1 Prerequisites

- **Control node**: Linux or macOS, Python ≥ 3.9 recommended.
- **Managed nodes**: SSH access, Python ≥ 2.7 (Python 3 preferred). No Ansible installation needed.

```bash
# Check Python version on control node
python3 --version

# Check pip
pip3 --version
```

### 2.2 Installation

#### Linux (Ubuntu/Debian)

```bash
# Option 1: pip (recommended for latest version)
pip3 install --user ansible

# Option 2: apt (stable, slightly older)
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y

# Verify
ansible --version
```

#### Linux (RHEL/CentOS/Amazon Linux)

```bash
# RHEL 8/9, Amazon Linux 2023
sudo dnf install ansible-core -y

# Or via pip for latest
pip3 install ansible --user
```

#### macOS

```bash
brew install ansible
# or
pip3 install ansible
```

#### Docker (useful for CI/CD pipelines)

```dockerfile
FROM python:3.11-slim
RUN pip install ansible==9.x.x
WORKDIR /ansible
```

### 2.3 Configuring Ansible (`ansible.cfg`)

Ansible reads configuration from these locations in order (first match wins):

1. `ANSIBLE_CONFIG` environment variable
2. `./ansible.cfg` (current directory — recommended for projects)
3. `~/.ansible.cfg`
4. `/etc/ansible/ansible.cfg`

**Production-ready `ansible.cfg`:**

```ini
[defaults]
# Inventory file location
inventory          = ./inventory

# SSH settings
remote_user        = ansible_svc           # dedicated service account
private_key_file   = ~/.ssh/ansible_id_ed25519
host_key_checking  = True                  # NEVER disable in production

# Performance
forks              = 20                    # parallel connections (default: 5)
pipelining         = True                  # reduces SSH connections, big speed boost
gather_timeout     = 30

# Output
stdout_callback    = yaml                  # cleaner output
callback_whitelist = timer, profile_tasks  # show execution times

# Retry files
retry_files_enabled = False               # suppress .retry files in CI

# Roles path
roles_path         = ./roles:~/.ansible/roles

[ssh_connection]
ssh_args           = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes
transfer_method    = smart
```

> **Security note**: Always set `host_key_checking = True` in production. Setting it to `False` opens you to man-in-the-middle attacks.

### 2.4 Inventory Management

The inventory tells Ansible *which* hosts to manage and how to group them.

#### Static Inventory (INI format)

```ini
# inventory/hosts.ini

[webservers]
web01.prod.example.com
web02.prod.example.com ansible_port=2222     # override port per host

[dbservers]
db01.prod.example.com ansible_user=postgres

[loadbalancers]
lb01.prod.example.com

# Group of groups
[production:children]
webservers
dbservers
loadbalancers

# Group variables
[webservers:vars]
http_port=80
nginx_version=1.24.0

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

#### Static Inventory (YAML format — recommended)

```yaml
# inventory/hosts.yml
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
  children:
    production:
      children:
        webservers:
          vars:
            http_port: 80
            nginx_version: "1.24.0"
          hosts:
            web01.prod.example.com:
            web02.prod.example.com:
              ansible_port: 2222
        dbservers:
          hosts:
            db01.prod.example.com:
              ansible_user: postgres
```

#### Host and Group Variable Files

For complex inventories, move variables out of the inventory file:

```
inventory/
├── hosts.yml
├── group_vars/
│   ├── all.yml           # applies to all hosts
│   ├── webservers.yml    # applies to [webservers]
│   └── production.yml    # applies to [production]
└── host_vars/
    ├── web01.prod.example.com.yml
    └── db01.prod.example.com.yml
```

```yaml
# inventory/group_vars/webservers.yml
nginx_worker_processes: auto
nginx_worker_connections: 1024
ssl_certificate: /etc/ssl/certs/prod.crt
```

#### Dynamic Inventory

For cloud environments where hosts come and go, use a dynamic inventory plugin:

```yaml
# inventory/aws_ec2.yml  (AWS EC2 plugin)
plugin: amazon.aws.aws_ec2
regions:
  - ap-south-1
filters:
  instance-state-name: running
  tag:Environment: production
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: placement.region
    prefix: region
hostnames:
  - private-ip-address    # use private IPs for SSH

compose:
  ansible_host: private_ip_address
  ansible_user: "'ec2-user'"
```

```bash
# Test dynamic inventory
ansible-inventory -i inventory/aws_ec2.yml --list
ansible-inventory -i inventory/aws_ec2.yml --graph
```

#### Verifying Inventory

```bash
# List all hosts
ansible all -i inventory/ --list-hosts

# Ping all hosts
ansible all -i inventory/ -m ping

# Target specific group
ansible webservers -i inventory/ -m ping
```

---

## 3. Ansible Playbooks

### 3.1 YAML Syntax Basics

Ansible Playbooks are YAML documents. Key YAML rules that trip people up:

```yaml
# Strings — quotes optional unless special chars present
name: deploy nginx
name: "deploy: nginx"        # colon forces quotes
name: 'deploy {{ app }}'     # braces force quotes

# Booleans — Ansible accepts several forms; prefer explicit
become: true                 # recommended
become: yes                  # also valid
become: True                 # also valid

# Lists — two equivalent forms
packages:
  - nginx
  - curl
  - git

packages: [nginx, curl, git]  # inline form

# Dicts — two equivalent forms
user:
  name: deploy
  shell: /bin/bash

user: {name: deploy, shell: /bin/bash}   # inline form

# Multiline strings
motd: |
  Welcome to production.
  Unauthorized access is prohibited.

command: >
  /usr/bin/long-command
  --option1 value1
  --option2 value2
```

### 3.2 Structure of a Playbook

```yaml
---
# site.yml — complete annotated playbook structure

- name: Configure web servers          # Play name (shown in output)
  hosts: webservers                    # Target group from inventory
  become: true                         # Escalate to root (sudo)
  become_user: root                    # Who to become (default: root)
  gather_facts: true                   # Collect system info (default: true)
  any_errors_fatal: false              # Stop ALL hosts if one fails (default: false)
  max_fail_percentage: 20              # Allow up to 20% failures before aborting
  serial: 2                            # Process 2 hosts at a time (rolling deploy)

  vars:                                # Play-level variables
    app_name: myapp
    app_version: "2.1.0"
    app_port: 8080

  vars_files:                          # Load variables from external files
    - vars/common.yml
    - vars/{{ env }}.yml               # Dynamic file based on variable

  pre_tasks:                           # Run before roles and tasks
    - name: Check OS compatibility
      ansible.builtin.fail:
        msg: "This playbook requires Ubuntu 22.04 or later"
      when: ansible_distribution != "Ubuntu" or ansible_distribution_major_version | int < 22

  roles:                               # Apply roles (see Section 8)
    - common
    - nginx

  tasks:                               # Main task list
    - name: Deploy application config
      ansible.builtin.template:
        src: app.conf.j2
        dest: /etc/myapp/app.conf
        owner: www-data
        group: www-data
        mode: '0640'
      notify: Restart application       # Trigger handler

    - name: Ensure application is running
      ansible.builtin.service:
        name: myapp
        state: started
        enabled: true

  post_tasks:                          # Run after roles and tasks
    - name: Verify application is responding
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      retries: 5
      delay: 10

  handlers:                            # Run when notified, once per play
    - name: Restart application
      ansible.builtin.service:
        name: myapp
        state: restarted
```

### 3.3 Writing Your First Playbook

**Goal**: Install and configure Nginx on web servers, deploy a custom index page.

```yaml
---
# playbooks/setup_nginx.yml

- name: Install and configure Nginx
  hosts: webservers
  become: true
  gather_facts: true

  vars:
    nginx_port: 80
    site_name: "My Production Site"
    document_root: /var/www/html

  tasks:
    - name: Install Nginx
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Create document root
      ansible.builtin.file:
        path: "{{ document_root }}"
        state: directory
        owner: www-data
        group: www-data
        mode: '0755'

    - name: Deploy index page
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: "{{ document_root }}/index.html"
        owner: www-data
        group: www-data
        mode: '0644'
      notify: Reload Nginx

    - name: Ensure Nginx is enabled and started
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true

    - name: Verify Nginx responds
      ansible.builtin.uri:
        url: "http://localhost:{{ nginx_port }}/"
        status_code: 200
      register: nginx_check
      failed_when: nginx_check.status != 200

  handlers:
    - name: Reload Nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

```html
<!-- templates/index.html.j2 -->
<!DOCTYPE html>
<html>
<head><title>{{ site_name }}</title></head>
<body>
  <h1>{{ site_name }}</h1>
  <p>Served by {{ inventory_hostname }} ({{ ansible_default_ipv4.address }})</p>
  <p>Deployed: {{ ansible_date_time.iso8601 }}</p>
</body>
</html>
```

**Running the playbook:**

```bash
# Syntax check first
ansible-playbook playbooks/setup_nginx.yml --syntax-check

# Dry run (no changes made)
ansible-playbook playbooks/setup_nginx.yml --check --diff

# Run for real
ansible-playbook playbooks/setup_nginx.yml

# Run with verbose output
ansible-playbook playbooks/setup_nginx.yml -v    # task output
ansible-playbook playbooks/setup_nginx.yml -vv   # more detail
ansible-playbook playbooks/setup_nginx.yml -vvv  # SSH debug level
```

---

## 4. Tasks and Modules

### 4.1 Understanding Ansible Modules

A **module** is the unit of work in Ansible — a small program that implements a specific action (install a package, copy a file, create a user). Ansible ships with 3,000+ built-in modules.

**Full module name format**: `namespace.collection.module_name`
- `ansible.builtin.copy` — core module
- `amazon.aws.ec2_instance` — AWS collection
- `community.mysql.mysql_db` — community collection

> **Best practice**: Always use **FQCN** (Fully Qualified Collection Name) in production playbooks. Short names like `copy` are deprecated aliases.

### 4.2 Commonly Used Modules

#### `ansible.builtin.copy` — Copy files to managed nodes

```yaml
# Basic copy
- name: Copy application config
  ansible.builtin.copy:
    src: files/app.conf          # path on control node
    dest: /etc/myapp/app.conf    # path on managed node
    owner: myapp
    group: myapp
    mode: '0640'
    backup: true                 # create .backup before overwriting

# Copy content directly (no src file needed)
- name: Create motd
  ansible.builtin.copy:
    content: |
      ============================================================
      Production Server — Authorized Access Only
      ============================================================
    dest: /etc/motd
    mode: '0644'

# Error Handling: destination directory might not exist
- name: Ensure config directory exists
  ansible.builtin.file:
    path: /etc/myapp
    state: directory
    owner: myapp
    mode: '0750'

- name: Copy application config
  ansible.builtin.copy:
    src: files/app.conf
    dest: /etc/myapp/app.conf
    owner: myapp
    mode: '0640'
  register: config_copy_result
  failed_when: config_copy_result is failed and not config_copy_result.msg | default('') | regex_search('Permission denied')
```

**Theory**: `copy` is idempotent — it compares the source checksum to the destination checksum. If they match, it reports `ok` and makes no change. If they differ, it copies and reports `changed`.

---

#### `ansible.builtin.template` — Render Jinja2 templates

```yaml
- name: Deploy nginx virtual host config
  ansible.builtin.template:
    src: templates/vhost.conf.j2
    dest: /etc/nginx/sites-available/{{ site_name }}.conf
    owner: root
    group: root
    mode: '0644'
    validate: /usr/sbin/nginx -t -c %s    # validate before placing the file
  notify: Reload Nginx
```

**Error handling**: The `validate` parameter runs a command against the temp file before placing it in the final destination. If nginx config validation fails, the file is NOT deployed and the task fails — preventing broken configs from hitting production.

---

#### `ansible.builtin.service` — Manage system services

```yaml
- name: Start and enable nginx
  ansible.builtin.service:
    name: nginx
    state: started       # started | stopped | restarted | reloaded
    enabled: true        # start on boot

# Error handling: service may not exist yet
- name: Check if custom service exists
  ansible.builtin.stat:
    path: /etc/systemd/system/myapp.service
  register: service_file

- name: Start custom service (only if unit file exists)
  ansible.builtin.service:
    name: myapp
    state: started
    enabled: true
  when: service_file.stat.exists
```

---

#### `ansible.builtin.package` — Install/remove packages (distro-agnostic)

```yaml
# Install multiple packages
- name: Install base packages
  ansible.builtin.package:
    name:
      - curl
      - git
      - htop
      - unzip
    state: present

# Remove a package
- name: Remove telnet (security hardening)
  ansible.builtin.package:
    name: telnet
    state: absent

# Latest version
- name: Ensure security patches applied
  ansible.builtin.package:
    name: openssl
    state: latest
  notify: Restart affected services

# Error handling: package not found in repo
- name: Install optional monitoring agent
  ansible.builtin.package:
    name: datadog-agent
    state: present
  ignore_errors: true       # Don't fail play if repo not configured
  register: dd_install
  
- name: Warn if monitoring agent install failed
  ansible.builtin.debug:
    msg: "WARNING: Datadog agent not installed — {{ dd_install.msg | default('unknown error') }}"
  when: dd_install is failed
```

---

#### `ansible.builtin.user` — Manage user accounts

```yaml
- name: Create application service account
  ansible.builtin.user:
    name: myapp
    comment: "MyApp Service Account"
    system: true              # system account (no home dir by default, UID < 1000)
    shell: /sbin/nologin      # no interactive login
    create_home: false
    state: present

- name: Create deploy user with SSH key
  ansible.builtin.user:
    name: deploy
    groups:
      - sudo
      - docker
    append: true              # append to groups, don't replace
    shell: /bin/bash
    password: "{{ deploy_password_hash }}"   # must be hashed!
    update_password: on_create               # only set password at creation

- name: Remove retired employee account
  ansible.builtin.user:
    name: jdoe
    state: absent
    remove: true              # also remove home directory and mail spool
```

---

#### `ansible.builtin.file` — Manage files, directories, symlinks

```yaml
# Create directory tree
- name: Create application directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: myapp
    group: myapp
    mode: '0750'
  loop:
    - /opt/myapp
    - /opt/myapp/config
    - /opt/myapp/logs
    - /opt/myapp/data

# Create symlink
- name: Link current release
  ansible.builtin.file:
    src: /opt/myapp/releases/{{ app_version }}
    dest: /opt/myapp/current
    state: link
    force: true               # overwrite existing symlink

# Delete file
- name: Remove old pid file
  ansible.builtin.file:
    path: /var/run/myapp.pid
    state: absent

# Touch file (create if not exists, update mtime if exists)
- name: Ensure log file exists
  ansible.builtin.file:
    path: /var/log/myapp/app.log
    state: touch
    owner: myapp
    mode: '0640'
    modification_time: preserve   # don't change mtime if file exists
    access_time: preserve
```

---

#### `ansible.builtin.command` and `ansible.builtin.shell`

```yaml
# command: runs a command, no shell interpretation
- name: Run database migration
  ansible.builtin.command:
    cmd: /opt/myapp/bin/migrate --env production
    chdir: /opt/myapp/current     # working directory
    creates: /opt/myapp/.migrated # skip if this file exists (idempotence hack)

# shell: full shell interpretation (pipes, redirects, etc.)
- name: Compress old logs
  ansible.builtin.shell:
    cmd: find /var/log/myapp -name "*.log" -mtime +7 | xargs gzip -9
  changed_when: false             # logs compressing is not a config change

# Capturing output
- name: Get application version
  ansible.builtin.command: /opt/myapp/bin/myapp --version
  register: app_version_output
  changed_when: false             # reading version doesn't change state

- name: Display version
  ansible.builtin.debug:
    msg: "Running version: {{ app_version_output.stdout }}"
```

> **Best practice**: Prefer specific modules (`package`, `service`, `file`) over `command`/`shell`. Use `command` when no module exists. Use `shell` only when you need pipes/redirects. `shell` is a security risk with untrusted input.

---

#### `ansible.builtin.debug` — Print information during runs

```yaml
- name: Show gathered facts
  ansible.builtin.debug:
    var: ansible_distribution       # print a variable

- name: Show custom message
  ansible.builtin.debug:
    msg: "Deploying {{ app_name }} version {{ app_version }} to {{ inventory_hostname }}"

- name: Show full register output
  ansible.builtin.debug:
    var: migration_result
    verbosity: 2                    # only show with -vv or more
```

---

#### `ansible.builtin.fail` — Explicitly fail with a message

```yaml
- name: Check disk space before deploy
  ansible.builtin.command: df -BG /opt --output=avail
  register: disk_space
  changed_when: false

- name: Abort if less than 5GB free
  ansible.builtin.fail:
    msg: "Insufficient disk space: {{ disk_space.stdout_lines[1] | trim }}GB available, need at least 5GB"
  when: disk_space.stdout_lines[1] | trim | regex_replace('G','') | int < 5
```

---

### 4.3 Registering Module Output

The `register` keyword captures a task's return value into a variable.

```yaml
- name: Check if deployment lock exists
  ansible.builtin.stat:
    path: /var/lock/myapp-deploy.lock
  register: deploy_lock

# Common registered variable attributes:
# result.changed      — was the state changed?
# result.failed       — did the task fail?
# result.stdout       — stdout for command/shell
# result.stderr       — stderr for command/shell
# result.stdout_lines — stdout as list of lines
# result.rc           — return code for command/shell
# result.stat         — file info (for stat module)
# result.stat.exists  — does file/dir exist?

- name: Abort if another deployment is running
  ansible.builtin.fail:
    msg: "Deployment lock exists — another deploy may be in progress"
  when: deploy_lock.stat.exists

- name: Create deployment lock
  ansible.builtin.file:
    path: /var/lock/myapp-deploy.lock
    state: touch
  register: lock_created

- name: Do deployment work here
  ansible.builtin.debug:
    msg: "Deploying..."

- name: Remove deployment lock
  ansible.builtin.file:
    path: /var/lock/myapp-deploy.lock
    state: absent
  when: lock_created is changed
```

---

## 5. Variables and Facts

### 5.1 Defining and Using Variables

#### Variable Precedence (low → high, higher wins)

```
Role defaults
Inventory group_vars/all
Inventory group_vars/*
Inventory host_vars/*
Playbook group_vars/all
Playbook group_vars/*
Playbook host_vars/*
Host facts
Play vars
Play vars_prompt
Play vars_files
Role vars
Block vars
Task vars
Set_fact / registered vars
Extra vars (-e flag)              ← HIGHEST
```

> **Rule of thumb**: Use `defaults/main.yml` in roles for values that should be easily overridden. Use `vars/main.yml` for internal role values that shouldn't be changed.

#### Playbook Variables

```yaml
- name: Deploy application
  hosts: webservers
  vars:
    app_name: myapp
    app_version: "2.1.0"
    app_port: 8080
    app_config:              # dict variable
      log_level: info
      max_connections: 100
    supported_envs:          # list variable
      - staging
      - production
  tasks:
    - name: Show config
      ansible.builtin.debug:
        msg: |
          App: {{ app_name }} v{{ app_version }}
          Port: {{ app_port }}
          Log level: {{ app_config.log_level }}
          Envs: {{ supported_envs | join(', ') }}
```

#### Group Variables

```yaml
# inventory/group_vars/webservers.yml
nginx_worker_processes: auto
nginx_worker_connections: 2048
app_port: 80

# inventory/group_vars/staging.yml
app_version: "2.2.0-rc1"
log_level: debug
enable_debug_endpoint: true

# inventory/group_vars/production.yml
app_version: "2.1.0"
log_level: warning
enable_debug_endpoint: false
```

#### Host Variables

```yaml
# inventory/host_vars/web01.prod.example.com.yml
nginx_worker_processes: 4    # Override for this specific host (8-core machine)
primary_host: true           # Host-specific flag
```

#### `vars_prompt` — Interactive variable input

```yaml
- name: Deploy with confirmation
  hosts: production
  vars_prompt:
    - name: deploy_version
      prompt: "Version to deploy (e.g. 2.1.0)"
      private: false          # show input

    - name: confirm_deploy
      prompt: "Type 'yes' to confirm production deployment"
      private: false

  tasks:
    - name: Abort if not confirmed
      ansible.builtin.fail:
        msg: "Deployment cancelled"
      when: confirm_deploy != "yes"
```

#### `vars_files` — Load variables from files

```yaml
- name: Configure app
  hosts: webservers
  vars_files:
    - vars/common.yml
    - "vars/{{ ansible_distribution | lower }}.yml"   # OS-specific vars
    - "vars/{{ env }}.yml"                             # environment-specific
  tasks: ...
```

#### `set_fact` — Create variables dynamically

```yaml
- name: Determine deployment slot
  ansible.builtin.set_fact:
    deployment_slot: "{{ 'blue' if current_slot == 'green' else 'green' }}"
    deploy_timestamp: "{{ ansible_date_time.epoch }}"

- name: Use computed variable
  ansible.builtin.debug:
    msg: "Deploying to {{ deployment_slot }} slot"
```

### 5.2 Ansible Facts

Facts are variables automatically gathered from managed nodes. They describe the system's current state.

```bash
# See all facts for a host
ansible web01.prod.example.com -m setup

# Filter facts
ansible web01.prod.example.com -m setup -a 'filter=ansible_default_ipv4'
ansible web01.prod.example.com -m setup -a 'filter=ansible_memory_mb'
```

**Commonly used facts:**

```yaml
ansible_hostname                    # "web01"
ansible_fqdn                        # "web01.prod.example.com"
ansible_distribution                # "Ubuntu"
ansible_distribution_version        # "22.04"
ansible_distribution_major_version  # "22"
ansible_os_family                   # "Debian"
ansible_architecture                # "x86_64"
ansible_default_ipv4.address        # "10.0.1.15"
ansible_default_ipv4.interface      # "eth0"
ansible_memtotal_mb                 # 7982
ansible_processor_vcpus             # 4
ansible_kernel                      # "5.15.0-1034-aws"
ansible_mounts                      # list of mount points
ansible_date_time.iso8601           # "2024-03-15T10:30:00Z"
ansible_env.HOME                    # "/root"
```

**Using facts in playbooks:**

```yaml
- name: Set swappiness based on available RAM
  ansible.builtin.sysctl:
    name: vm.swappiness
    value: "{{ '10' if ansible_memtotal_mb > 8192 else '60' }}"
    state: present
    reload: true

- name: Install OS-specific packages
  ansible.builtin.package:
    name: "{{ 'libssl-dev' if ansible_os_family == 'Debian' else 'openssl-devel' }}"
    state: present
```

#### Custom Facts

Deploy custom fact scripts to managed nodes for application-specific data:

```bash
#!/bin/bash
# /etc/ansible/facts.d/myapp.fact  (must be executable, output JSON)
APP_VERSION=$(cat /opt/myapp/VERSION 2>/dev/null || echo "unknown")
APP_STATUS=$(systemctl is-active myapp 2>/dev/null || echo "inactive")

cat <<EOF
{
  "version": "${APP_VERSION}",
  "status": "${APP_STATUS}",
  "config_dir": "/etc/myapp"
}
EOF
```

```yaml
- name: Deploy custom fact script
  ansible.builtin.copy:
    src: files/myapp.fact
    dest: /etc/ansible/facts.d/myapp.fact
    mode: '0755'

- name: Reload facts
  ansible.builtin.setup:
    filter: ansible_local

- name: Use custom fact
  ansible.builtin.debug:
    msg: "App version: {{ ansible_local.myapp.version }}"
```

#### Disabling Fact Gathering (Performance)

```yaml
- name: Quick task — no facts needed
  hosts: all
  gather_facts: false          # Skip fact gathering (saves ~2-5 seconds per host)
  tasks:
    - name: Check uptime
      ansible.builtin.command: uptime
      changed_when: false
```

### 5.3 Variable Scope

| Scope | How defined | Accessible from |
|---|---|---|
| Global | `-e` flag, `ansible.cfg` | Everywhere |
| Play | `vars:`, `vars_files:` in a play | That play only |
| Host | `set_fact`, `register`, host_vars | That host in that play |
| Block/Task | `vars:` on a block or task | That block/task only |

```yaml
- name: Demonstrate scope
  hosts: webservers
  vars:
    play_var: "I exist in this play"

  tasks:
    - name: Task with local scope
      ansible.builtin.debug:
        msg: "{{ local_var }}"
      vars:
        local_var: "I only exist in this task"

    - name: This fails — local_var not in scope here
      ansible.builtin.debug:
        msg: "{{ local_var }}"    # ERROR: undefined variable
```

---

## 6. Control Flow

### 6.1 `when` Conditions

```yaml
# Simple condition
- name: Install apache on Debian systems
  ansible.builtin.package:
    name: apache2
    state: present
  when: ansible_os_family == "Debian"

# Multiple conditions (AND)
- name: Configure production database
  ansible.builtin.template:
    src: db.conf.j2
    dest: /etc/myapp/db.conf
  when:
    - env == "production"
    - ansible_memtotal_mb >= 4096

# OR condition
- name: Run on Ubuntu or Debian
  ansible.builtin.package:
    name: ufw
    state: present
  when: ansible_distribution == "Ubuntu" or ansible_distribution == "Debian"

# Check registered result
- name: Check if config file exists
  ansible.builtin.stat:
    path: /etc/myapp/app.conf
  register: config_file

- name: Initialize config (only if missing)
  ansible.builtin.copy:
    src: files/app.conf.default
    dest: /etc/myapp/app.conf
  when: not config_file.stat.exists

# Check if variable is defined
- name: Use optional variable
  ansible.builtin.debug:
    msg: "Custom port: {{ custom_port }}"
  when: custom_port is defined

# Check list membership
- name: Open firewall for web role
  ansible.builtin.ufw:
    rule: allow
    port: "{{ http_port | string }}"
  when: "'webserver' in group_names"
```

### 6.2 Loops

#### Basic Loop

```yaml
- name: Create application users
  ansible.builtin.user:
    name: "{{ item }}"
    system: true
    shell: /sbin/nologin
    state: present
  loop:
    - myapp
    - myapp-worker
    - myapp-scheduler

# Loop with dict items
- name: Create directories with specific permissions
  ansible.builtin.file:
    path: "{{ item.path }}"
    owner: "{{ item.owner }}"
    mode: "{{ item.mode }}"
    state: directory
  loop:
    - { path: /opt/myapp/config, owner: myapp, mode: '0750' }
    - { path: /opt/myapp/logs,   owner: myapp, mode: '0755' }
    - { path: /opt/myapp/tmp,    owner: myapp, mode: '0700' }
```

#### Loop with Index

```yaml
- name: Configure multiple virtual hosts
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: "/etc/nginx/sites-available/{{ item.name }}.conf"
  loop: "{{ virtual_hosts }}"
  loop_control:
    index_var: idx            # zero-based index
    label: "{{ item.name }}" # cleaner output (hide sensitive data)
    pause: 1                  # seconds to pause between iterations
```

#### Nested Loops

```yaml
- name: Grant users access to multiple services
  ansible.builtin.debug:
    msg: "Grant {{ item[0] }} access to {{ item[1] }}"
  loop: "{{ ['alice', 'bob'] | product(['nginx', 'mysql']) | list }}"
```

#### Loop with `subelements`

```yaml
vars:
  users:
    - name: alice
      authorized_keys:
        - "ssh-ed25519 AAAA... alice@laptop"
        - "ssh-ed25519 BBBB... alice@desktop"
    - name: bob
      authorized_keys:
        - "ssh-ed25519 CCCC... bob@workstation"

tasks:
  - name: Deploy SSH authorized keys
    ansible.posix.authorized_key:
      user: "{{ item.0.name }}"
      key: "{{ item.1 }}"
      state: present
    loop: "{{ users | subelements('authorized_keys') }}"
```

#### `until` — Retry until condition met

```yaml
- name: Wait for application to be ready
  ansible.builtin.uri:
    url: "http://localhost:{{ app_port }}/health"
    status_code: 200
  register: health_check
  until: health_check.status == 200
  retries: 12           # try up to 12 times
  delay: 10             # wait 10 seconds between tries
  failed_when: health_check.status != 200
```

### 6.3 `block`, `rescue`, `always`

This is Ansible's try/catch/finally. Essential for error handling in production.

```yaml
- name: Deploy application with rollback on failure
  hosts: webservers
  become: true
  tasks:
    - name: Deployment block
      block:
        - name: Create backup of current deployment
          ansible.builtin.command:
            cmd: "cp -r /opt/myapp/current /opt/myapp/backup-{{ ansible_date_time.epoch }}"
          changed_when: true

        - name: Stop current application
          ansible.builtin.service:
            name: myapp
            state: stopped

        - name: Deploy new version
          ansible.builtin.unarchive:
            src: "{{ artifact_url }}"
            dest: /opt/myapp/releases/
            remote_src: true

        - name: Update symlink
          ansible.builtin.file:
            src: "/opt/myapp/releases/{{ app_version }}"
            dest: /opt/myapp/current
            state: link
            force: true

        - name: Start application
          ansible.builtin.service:
            name: myapp
            state: started

        - name: Health check
          ansible.builtin.uri:
            url: "http://localhost:{{ app_port }}/health"
            status_code: 200
          retries: 6
          delay: 10

      rescue:
        # Runs if ANY task in block fails
        - name: ROLLBACK — revert symlink to backup
          ansible.builtin.file:
            src: "/opt/myapp/backup-{{ ansible_date_time.epoch }}"
            dest: /opt/myapp/current
            state: link
            force: true

        - name: ROLLBACK — restart with old version
          ansible.builtin.service:
            name: myapp
            state: restarted

        - name: Alert on rollback
          ansible.builtin.debug:
            msg: "DEPLOYMENT FAILED — rolled back to previous version on {{ inventory_hostname }}"

        - name: Fail the play after rollback
          ansible.builtin.fail:
            msg: "Deployment failed and rollback completed on {{ inventory_hostname }}"

      always:
        # Runs regardless of success or failure
        - name: Remove deployment lock
          ansible.builtin.file:
            path: /var/lock/myapp-deploy.lock
            state: absent

        - name: Record deployment attempt
          ansible.builtin.lineinfile:
            path: /var/log/myapp/deployments.log
            line: "{{ ansible_date_time.iso8601 }} — {{ app_version }} — {{ 'SUCCESS' if not ansible_failed_task is defined else 'FAILED' }}"
            create: true
```

### 6.4 `include_tasks` and `import_tasks`

| Feature | `import_tasks` | `include_tasks` |
|---|---|---|
| When processed | At parse time (static) | At runtime (dynamic) |
| Support `when` on include | Applied to each task | Applied to the include itself |
| Support loops | ❌ | ✅ |
| Tags | Apply to all child tasks | Only apply to the include |
| Use for | Static, always-included tasks | Conditional or looped task files |

```yaml
# tasks/main.yml
- name: Import common setup (always runs)
  ansible.builtin.import_tasks: common_setup.yml

- name: Include OS-specific tasks (dynamic, based on fact)
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}_tasks.yml"

- name: Include tasks for each service
  ansible.builtin.include_tasks: configure_service.yml
  loop: "{{ services_to_configure }}"
  loop_control:
    loop_var: service_name   # use 'service_name' instead of 'item' in included file
```

```yaml
# tasks/configure_service.yml
- name: Create service directory
  ansible.builtin.file:
    path: "/etc/{{ service_name }}"
    state: directory

- name: Deploy service config
  ansible.builtin.template:
    src: "templates/{{ service_name }}.conf.j2"
    dest: "/etc/{{ service_name }}/config.conf"
```

### 6.5 Tags

Tags let you run or skip specific parts of a playbook.

```yaml
- name: Full system configuration
  hosts: all
  tasks:
    - name: Update package cache
      ansible.builtin.apt:
        update_cache: true
      tags:
        - packages
        - always     # 'always' tag runs even with --tags other_tag

    - name: Install base packages
      ansible.builtin.package:
        name: "{{ base_packages }}"
        state: present
      tags: packages

    - name: Configure firewall
      ansible.builtin.include_tasks: firewall.yml
      tags: security

    - name: Deploy application
      ansible.builtin.include_tasks: deploy.yml
      tags:
        - deploy
        - app
```

```bash
# Run only tagged tasks
ansible-playbook site.yml --tags packages
ansible-playbook site.yml --tags "packages,security"

# Skip tagged tasks
ansible-playbook site.yml --skip-tags deploy

# List all tags in a playbook
ansible-playbook site.yml --list-tags
```

---

## 7. Handlers and Notifications

### 7.1 What are Handlers?

Handlers are tasks that run **only when notified** and **only once per play**, regardless of how many tasks notify them. They always run **at the end of the play** (after all tasks).

**Use case**: Restart a service when its config changes, but restart it only once even if three config files change.

```yaml
- name: Configure web server
  hosts: webservers
  become: true

  tasks:
    - name: Update nginx.conf
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify: Restart nginx

    - name: Update SSL certificate
      ansible.builtin.copy:
        src: files/ssl.crt
        dest: /etc/ssl/certs/mysite.crt
      notify: Restart nginx    # nginx will still only restart once

    - name: Update virtual host
      ansible.builtin.template:
        src: vhost.conf.j2
        dest: /etc/nginx/sites-available/mysite.conf
      notify:
        - Validate nginx config   # notify multiple handlers
        - Restart nginx

  handlers:
    - name: Validate nginx config
      ansible.builtin.command: /usr/sbin/nginx -t
      changed_when: false

    - name: Restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted
      listen: "web server restart"   # alternative notification mechanism
```

### 7.2 Forcing Handlers to Run

```bash
# Run handlers even if a task fails (useful in --check mode)
ansible-playbook site.yml --force-handlers
```

```yaml
# Flush handlers mid-play (run now instead of end of play)
- name: Restart nginx before health check
  ansible.builtin.meta: flush_handlers
```

### 7.3 Handler Error Handling

```yaml
handlers:
  - name: Restart application
    ansible.builtin.service:
      name: myapp
      state: restarted
    register: restart_result
    failed_when: restart_result is failed

  - name: Verify after restart
    ansible.builtin.uri:
      url: "http://localhost:{{ app_port }}/health"
      status_code: 200
    retries: 5
    delay: 5
    listen: "verify app"       # triggered separately
```

---

## 8. Roles

### 8.1 Structure of an Ansible Role

```
roles/
└── nginx/
    ├── defaults/
    │   └── main.yml          # Default variables (easily overridden)
    ├── vars/
    │   └── main.yml          # Internal variables (not meant to be overridden)
    ├── tasks/
    │   ├── main.yml          # Entry point for tasks
    │   ├── install.yml
    │   └── configure.yml
    ├── handlers/
    │   └── main.yml          # Handlers
    ├── templates/
    │   └── nginx.conf.j2     # Jinja2 templates
    ├── files/
    │   └── dhparams.pem      # Static files
    ├── meta/
    │   └── main.yml          # Role metadata and dependencies
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    └── README.md
```

### 8.2 Creating a Role

```bash
# Create role skeleton
ansible-galaxy role init roles/nginx
```

```yaml
# roles/nginx/defaults/main.yml
nginx_port: 80
nginx_ssl_port: 443
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_server_name: "_"
nginx_document_root: /var/www/html
nginx_log_dir: /var/log/nginx
nginx_ssl_enabled: false
nginx_gzip_enabled: true
```

```yaml
# roles/nginx/vars/main.yml
# These override defaults and should not be changed by users
_nginx_package_name:
  Debian: nginx
  RedHat: nginx
nginx_package_name: "{{ _nginx_package_name[ansible_os_family] }}"

_nginx_service_name: nginx
_nginx_config_dir: /etc/nginx
```

```yaml
# roles/nginx/tasks/main.yml
---
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_os_family | lower }}.yml"
  failed_when: false           # Don't fail if OS-specific file doesn't exist

- name: Include install tasks
  ansible.builtin.import_tasks: install.yml
  tags: install

- name: Include configure tasks
  ansible.builtin.import_tasks: configure.yml
  tags: configure

- name: Include SSL tasks
  ansible.builtin.import_tasks: ssl.yml
  tags: ssl
  when: nginx_ssl_enabled | bool
```

```yaml
# roles/nginx/tasks/install.yml
---
- name: Install Nginx
  ansible.builtin.package:
    name: "{{ nginx_package_name }}"
    state: present

- name: Ensure Nginx log directory exists
  ansible.builtin.file:
    path: "{{ nginx_log_dir }}"
    state: directory
    owner: root
    group: adm
    mode: '0755'
```

```yaml
# roles/nginx/tasks/configure.yml
---
- name: Deploy nginx main config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: "{{ _nginx_config_dir }}/nginx.conf"
    owner: root
    group: root
    mode: '0644'
    validate: "/usr/sbin/nginx -t -c %s"
  notify: Reload nginx

- name: Enable nginx
  ansible.builtin.service:
    name: "{{ _nginx_service_name }}"
    state: started
    enabled: true
```

```yaml
# roles/nginx/handlers/main.yml
---
- name: Reload nginx
  ansible.builtin.service:
    name: "{{ _nginx_service_name }}"
    state: reloaded

- name: Restart nginx
  ansible.builtin.service:
    name: "{{ _nginx_service_name }}"
    state: restarted
```

### 8.3 Using Roles in a Playbook

```yaml
# site.yml

- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - role: common              # simple role reference
    - role: nginx               # simple role reference
      vars:                     # override defaults for this play
        nginx_port: 8080
        nginx_ssl_enabled: true
    - role: myapp
      when: env == "production" # conditional role application

  tasks:
    # Tasks in the play run AFTER roles
    - name: Verify everything is working
      ansible.builtin.uri:
        url: "http://localhost/"
        status_code: 200
```

### 8.4 Role Dependencies

```yaml
# roles/myapp/meta/main.yml
---
galaxy_info:
  author: platform-team
  description: MyApp application role
  min_ansible_version: "2.14"
  platforms:
    - name: Ubuntu
      versions: ["22.04", "20.04"]
  galaxy_tags:
    - web
    - application

dependencies:
  - role: common
  - role: nginx
    vars:
      nginx_port: "{{ app_port }}"
  - role: postgresql
    when: app_db_type == "postgresql"
```

### 8.5 Ansible Galaxy

```bash
# Install a role from Galaxy
ansible-galaxy role install geerlingguy.nginx

# Install a collection
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install community.mysql

# Install from requirements file
ansible-galaxy install -r requirements.yml

# requirements.yml
# ---
# roles:
#   - name: geerlingguy.nginx
#     version: "3.2.0"
#   - src: https://github.com/myorg/myrole
#     scm: git
#     version: main
# collections:
#   - name: amazon.aws
#     version: ">=6.0.0"
#   - name: community.general

# List installed roles
ansible-galaxy role list

# Remove a role
ansible-galaxy role remove geerlingguy.nginx
```

---

## 9. Templates

### 9.1 Jinja2 Templating

Ansible uses Jinja2 for all templating (in both `.j2` template files and directly in playbook values).

**Core Jinja2 syntax:**

```jinja2
{# This is a comment #}

{# Variable substitution #}
{{ variable_name }}
{{ dict_var.key }}
{{ list_var[0] }}

{# Filters — transform values #}
{{ app_name | upper }}                          {# MYAPP #}
{{ server_list | length }}                      {# 3 #}
{{ description | default('No description') }}   {# fallback value #}
{{ hostname | regex_replace('\..*$', '') }}     {# strip domain #}
{{ port | string }}                             {# convert to string #}
{{ items | join(', ') }}                        {# list to string #}
{{ secret | b64encode }}                        {# base64 encode #}
{{ json_data | to_json }}
{{ json_string | from_json }}
{{ path_parts | combine }}                      {# merge dicts #}

{# Control structures #}
{% if nginx_ssl_enabled %}
listen 443 ssl;
{% else %}
listen 80;
{% endif %}

{% for server in upstream_servers %}
server {{ server.ip }}:{{ server.port }} weight={{ server.weight | default(1) }};
{% endfor %}

{# Loop controls #}
{% for item in items %}
  {{ item }}{% if not loop.last %},{% endif %}
{% endfor %}
```

### 9.2 Creating Configuration Files with Templates

**Example: Nginx virtual host configuration**

```jinja2
{# templates/vhost.conf.j2 #}

upstream {{ app_name }}_backend {
    {% if lb_method is defined %}
    {{ lb_method }};
    {% endif %}
    {% for server in backend_servers %}
    server {{ server.host }}:{{ server.port | default(app_port) }}
           weight={{ server.weight | default(1) }}
           max_fails={{ server.max_fails | default(3) }}
           fail_timeout={{ server.fail_timeout | default('30s') }};
    {% endfor %}
    keepalive 32;
}

server {
    listen {{ nginx_port | default(80) }};
    server_name {{ nginx_server_names | default([inventory_hostname]) | join(' ') }};

    {% if nginx_ssl_enabled | default(false) %}
    listen {{ nginx_ssl_port | default(443) }} ssl;
    ssl_certificate     {{ ssl_certificate }};
    ssl_certificate_key {{ ssl_certificate_key }};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    {% endif %}

    access_log /var/log/nginx/{{ app_name }}_access.log;
    error_log  /var/log/nginx/{{ app_name }}_error.log {{ nginx_log_level | default('warn') }};

    location / {
        proxy_pass         http://{{ app_name }}_backend;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_connect_timeout {{ proxy_connect_timeout | default('5s') }};
        proxy_read_timeout    {{ proxy_read_timeout | default('60s') }};

        {% if enable_rate_limiting | default(false) %}
        limit_req zone=api burst={{ rate_limit_burst | default(20) }} nodelay;
        {% endif %}
    }

    location /health {
        access_log off;
        proxy_pass http://{{ app_name }}_backend/health;
    }
}
```

```yaml
# Playbook using the template
- name: Deploy nginx virtual host
  ansible.builtin.template:
    src: templates/vhost.conf.j2
    dest: "/etc/nginx/sites-available/{{ app_name }}.conf"
    owner: root
    mode: '0644'
    validate: "/usr/sbin/nginx -t -c /dev/stdin < %s"  # validate config
  vars:
    backend_servers:
      - { host: "10.0.1.10", port: 8080, weight: 2 }
      - { host: "10.0.1.11", port: 8080, weight: 1 }
    nginx_ssl_enabled: true
    enable_rate_limiting: true
  notify: Reload nginx
```

### 9.3 Template Error Handling

**Missing variable protection with `default` filter:**

```jinja2
{# Bad — fails if db_port undefined #}
port = {{ db_port }}

{# Good — provides fallback #}
port = {{ db_port | default(5432) }}

{# Mandatory — fails with clear message if undefined #}
database_url = {{ database_url | mandatory("database_url must be defined in group_vars") }}

{# Conditional block based on variable existence #}
{% if metrics_endpoint is defined %}
metrics_path = {{ metrics_endpoint }}
{% endif %}

{# Safe dict access #}
timeout = {{ app_config.get('timeout', 30) }}
```

**Validating template output before deployment:**

```yaml
- name: Deploy app configuration
  ansible.builtin.template:
    src: app.conf.j2
    dest: /etc/myapp/app.conf
    validate: "/opt/myapp/bin/validate-config %s"  # app-specific validator
  register: config_result
  failed_when: config_result is failed

- name: Test config loads correctly
  ansible.builtin.command:
    cmd: "/opt/myapp/bin/myapp --config /etc/myapp/app.conf --test"
  changed_when: false
  register: config_test
  failed_when: config_test.rc != 0

- name: Report config validation result
  ansible.builtin.debug:
    msg: "Config validation: {{ 'PASSED' if config_test.rc == 0 else 'FAILED' }}"
```

---

## 10. Vault

### 10.1 Encrypting Sensitive Data

Ansible Vault encrypts variables and files so secrets can be safely stored in version control.

```bash
# Encrypt a string (inline secret)
ansible-vault encrypt_string 'MySuperSecretPassword!' --name 'db_password'
# Output (paste this into your vars file):
# db_password: !vault |
#   $ANSIBLE_VAULT;1.1;AES256
#   6238323865373839343832303966...

# Encrypt an entire file
ansible-vault encrypt vars/secrets.yml
ansible-vault encrypt inventory/group_vars/production/secrets.yml

# View encrypted file
ansible-vault view vars/secrets.yml

# Edit encrypted file
ansible-vault edit vars/secrets.yml

# Decrypt file (creates plaintext — be careful!)
ansible-vault decrypt vars/secrets.yml

# Re-key (change vault password)
ansible-vault rekey vars/secrets.yml

# Encrypt with specific vault ID (multiple passwords)
ansible-vault encrypt_string 'secret' --vault-id prod@prompt --name 'api_key'
```

### 10.2 Using Vault in Playbooks

```yaml
# vars/secrets.yml (encrypted with vault)
# Run: ansible-vault edit vars/secrets.yml
# Contents when decrypted:
db_password: "MySuperSecretDBPassword"
api_key: "sk_prod_abc123xyz"
ssl_private_key: |
  -----BEGIN PRIVATE KEY-----
  MIIEvQIBADANBgkqhkiG9w...
  -----END PRIVATE KEY-----
```

```yaml
# playbook.yml
- name: Configure database
  hosts: dbservers
  become: true
  vars_files:
    - vars/common.yml
    - vars/secrets.yml     # vault-encrypted file

  tasks:
    - name: Create database user
      community.mysql.mysql_user:
        name: myapp
        password: "{{ db_password }}"   # from vault
        priv: "myapp_db.*:ALL"
        state: present
```

```bash
# Run playbook with vault password
ansible-playbook site.yml --ask-vault-pass

# Use a vault password file (for CI/CD)
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# Environment variable (for CI/CD)
export ANSIBLE_VAULT_PASSWORD_FILE=/run/secrets/vault_pass
ansible-playbook site.yml
```

### 10.3 Multiple Vault Passwords (Vault IDs)

```bash
# Encrypt with named vault IDs
ansible-vault encrypt_string 'prod_secret' --vault-id prod@~/.vault_pass_prod --name 'prod_api_key'
ansible-vault encrypt_string 'dev_secret' --vault-id dev@~/.vault_pass_dev --name 'dev_api_key'

# Run with multiple vault passwords
ansible-playbook site.yml \
  --vault-id prod@~/.vault_pass_prod \
  --vault-id dev@~/.vault_pass_dev
```

### 10.4 Vault Best Practices

```yaml
# GOOD: Encrypt only the secret value, keep variable name visible
# group_vars/production/secrets.yml
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  6238...

# BAD: Encrypting the whole file makes reviewing diffs hard
# (use only for truly sensitive files like private keys)
```

```
# .gitignore — never commit vault passwords!
.vault_pass
*.vault_pass
~/.vault_pass*

# CI/CD pipeline (GitHub Actions example)
# Store vault password in GitHub Secrets, write to temp file
echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > /tmp/vault_pass
ansible-playbook site.yml --vault-password-file /tmp/vault_pass
rm /tmp/vault_pass
```

---

## 11. Error Handling and Debugging

### 11.1 Error Handling Strategies

#### `ignore_errors` — Continue despite failure

```yaml
- name: Check for optional component
  ansible.builtin.command: /opt/optional-tool/status
  register: optional_status
  ignore_errors: true    # Play continues even if this fails

- name: Warn if optional tool not present
  ansible.builtin.debug:
    msg: "Optional tool not installed — some features will be unavailable"
  when: optional_status is failed
```

> **Warning**: `ignore_errors` hides real problems. Prefer `failed_when` for precise control.

#### `failed_when` — Custom failure conditions

```yaml
# Fail only if return code is NOT 0 or 3 (custom exit codes)
- name: Run maintenance script
  ansible.builtin.command: /opt/scripts/maintenance.sh
  register: maint_result
  failed_when:
    - maint_result.rc != 0
    - maint_result.rc != 3     # rc 3 means "nothing to do" — that's OK

# Fail based on output content
- name: Check certificate expiry
  ansible.builtin.command: openssl x509 -in /etc/ssl/certs/mysite.crt -noout -enddate
  register: cert_info
  changed_when: false
  failed_when: "'expired' in cert_info.stdout | lower"

# Complex condition
- name: Run database backup
  ansible.builtin.command: /opt/scripts/backup.sh
  register: backup_result
  failed_when: >
    backup_result.rc != 0 or
    'Error' in backup_result.stderr or
    backup_result.stdout | length == 0
```

#### `changed_when` — Control when a task reports "changed"

```yaml
# Command/shell tasks always report changed — fix that
- name: Get application status
  ansible.builtin.command: /opt/myapp/bin/status
  register: app_status
  changed_when: false           # This is a read-only operation

# Report changed only when output indicates a change
- name: Run idempotent migration
  ansible.builtin.command: /opt/scripts/migrate.sh
  register: migrate_result
  changed_when: "'applied' in migrate_result.stdout"
  failed_when: migrate_result.rc != 0
```

#### `any_errors_fatal` — Stop all hosts on first failure

```yaml
- name: Critical deployment
  hosts: webservers
  any_errors_fatal: true    # If ANY host fails, stop the ENTIRE play
  tasks:
    - name: Run pre-deployment checks
      ansible.builtin.command: /opt/scripts/pre-deploy-check.sh
```

#### `max_fail_percentage` — Allow some failures in large fleets

```yaml
- name: Rolling update — tolerate up to 10% failure rate
  hosts: webservers
  serial: 5
  max_fail_percentage: 10   # Continue as long as >90% of hosts succeed
  tasks:
    - name: Update application
      ansible.builtin.package:
        name: myapp
        state: latest
```

### 11.2 Using `debug` and `fail`

```yaml
# debug: inspect registered variables
- name: Run application health check
  ansible.builtin.uri:
    url: "http://localhost:{{ app_port }}/api/status"
    return_content: true
  register: api_response
  failed_when: api_response.status != 200

- name: Show API response (debug)
  ansible.builtin.debug:
    var: api_response.json
    verbosity: 1      # only show with -v

- name: Show specific value
  ansible.builtin.debug:
    msg: "API status: {{ api_response.json.status }}, version: {{ api_response.json.version }}"

# fail: explicit failure with context
- name: Validate required variables
  ansible.builtin.fail:
    msg: |
      Missing required variable: {{ item }}
      Please define it in group_vars/{{ group_names | first }}/vars.yml
  when: vars[item] is not defined
  loop:
    - db_host
    - db_name
    - app_secret_key

# assert: multiple assertions with clear messages
- name: Assert environment is valid
  ansible.builtin.assert:
    that:
      - env in ['staging', 'production']
      - app_port | int > 1024
      - app_port | int < 65535
      - db_host is defined and db_host | length > 0
    fail_msg: "Environment validation failed — check variable values"
    success_msg: "Environment validation passed for {{ env }}"
```

### 11.3 Troubleshooting Playbook Execution

```bash
# Syntax check — catches YAML/Jinja2 errors before running
ansible-playbook site.yml --syntax-check

# Dry run — shows what WOULD change, no actual changes
ansible-playbook site.yml --check

# Dry run with diff — shows exactly what text would change in files
ansible-playbook site.yml --check --diff

# Limit to specific hosts or groups
ansible-playbook site.yml --limit web01.prod.example.com
ansible-playbook site.yml --limit webservers
ansible-playbook site.yml --limit "webservers:!web01"    # exclude web01

# Run specific tags only
ansible-playbook site.yml --tags deploy
ansible-playbook site.yml --start-at-task "Deploy application config"

# Step through tasks one by one
ansible-playbook site.yml --step

# Verbose output levels
ansible-playbook site.yml -v       # task output, return values
ansible-playbook site.yml -vv      # module arguments
ansible-playbook site.yml -vvv     # SSH connection details
ansible-playbook site.yml -vvvv    # SSH debug level

# Test connectivity and module availability
ansible all -m ping
ansible webservers -m setup -a 'filter=ansible_distribution'

# Ad-hoc commands for quick checks
ansible web01 -m command -a "df -h"
ansible webservers -m service -a "name=nginx state=started" --check
```

### 11.4 Interpreting Error Messages

**Common errors and solutions:**

```
# Error: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh..."}
# Fix: Check SSH key, security groups, host is reachable
ansible web01 -m ping -vvv    # debug SSH connection

# Error: "sudo: a password is required"
# Fix: Configure passwordless sudo OR use --ask-become-pass
ansible-playbook site.yml --ask-become-pass

# Error: "The task includes an option with an undefined variable..."
# Fix: Check variable name, scope, and that vars_files are loaded
# Add to playbook temporarily:
- ansible.builtin.debug: var=hostvars[inventory_hostname]

# Error: "MODULE FAILURE: ... non-JSON response"
# Fix: Python issue on managed node, check:
ansible web01 -m setup         # tests Python connectivity
ansible web01 -m raw -a "python3 --version"   # check Python

# Error: Template rendering fails with 'undefined'
# Fix: Add 'default' filter or pre-check variable
{{ possibly_undefined_var | default('fallback_value') }}

# Error: "Timeout waiting for privilege escalation prompt"
# Fix: sudo not configured, or requiretty is set
# In /etc/sudoers on managed node:
# Defaults:ansible_svc !requiretty
```

---

## 12. Advanced Topics

### 12.1 Ansible Tower / AWX

**AWX** is the open-source version; **Ansible Automation Platform (AAP)** / **Tower** is the commercial, supported product from Red Hat.

**Key features:**
- **Web UI** for running playbooks without CLI access
- **Role-Based Access Control (RBAC)** — who can run what against which hosts
- **Credential management** — encrypted storage, no plaintext secrets in pipelines
- **Scheduling** — run playbooks on a cron schedule
- **Notifications** — Slack, email, PagerDuty on job completion/failure
- **Audit logging** — complete record of who ran what
- **Workflow templates** — chain playbooks together with conditional branching

```bash
# Install AWX via Docker Compose (development)
git clone https://github.com/ansible/awx.git
cd awx
docker compose up -d

# Or via Kubernetes operator (production)
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/main/deploy/awx-operator.yaml
```

### 12.2 Custom Modules and Plugins

#### Custom Module (Python)

```python
#!/usr/bin/python3
# library/my_custom_module.py

from ansible.module_utils.basic import AnsibleModule

def main():
    module_args = dict(
        name=dict(type='str', required=True),
        state=dict(type='str', default='present', choices=['present', 'absent']),
        config=dict(type='dict', required=False, default={})
    )

    result = dict(
        changed=False,
        message=''
    )

    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True   # support --check
    )

    name = module.params['name']
    state = module.params['state']

    # Check current state
    current_state = get_current_state(name)   # your implementation

    if current_state == state:
        result['changed'] = False
        result['message'] = f'{name} is already {state}'
    else:
        if module.check_mode:
            result['changed'] = True
            result['message'] = f'Would change {name} to {state}'
        else:
            # Apply change
            apply_change(name, state)
            result['changed'] = True
            result['message'] = f'Changed {name} to {state}'

    module.exit_json(**result)

if __name__ == '__main__':
    main()
```

```yaml
# Use in playbook (module must be in ./library/ directory or ANSIBLE_LIBRARY path)
- name: Use custom module
  my_custom_module:
    name: myresource
    state: present
    config:
      timeout: 30
```

#### Custom Filter Plugin

```python
# filter_plugins/custom_filters.py

def to_connection_string(db_config):
    """Convert dict to database connection string."""
    return (
        f"{db_config['driver']}://{db_config['user']}:{db_config['password']}"
        f"@{db_config['host']}:{db_config.get('port', 5432)}/{db_config['name']}"
    )

def mask_secret(value, visible_chars=4):
    """Mask a secret value for display."""
    s = str(value)
    return s[:visible_chars] + '*' * (len(s) - visible_chars)

class FilterModule(object):
    def filters(self):
        return {
            'to_connection_string': to_connection_string,
            'mask_secret': mask_secret,
        }
```

```jinja2
{# Use in template #}
database_url = {{ db_config | to_connection_string }}
{# Logging: api_key = abcd******** #}
api_key_display = {{ api_key | mask_secret(4) }}
```

### 12.3 Best Practices for Production

#### Project Structure

```
ansible-project/
├── ansible.cfg
├── requirements.yml           # Galaxy dependencies
├── site.yml                   # Master playbook
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   └── host_vars/
│   └── staging/
│       ├── hosts.yml
│       ├── group_vars/
│       └── host_vars/
├── playbooks/
│   ├── deploy.yml
│   ├── rollback.yml
│   └── maintenance.yml
├── roles/
│   ├── common/
│   ├── nginx/
│   └── myapp/
├── filter_plugins/
├── library/                   # custom modules
├── files/                     # global static files
├── templates/                 # global templates
└── vars/
    ├── common.yml
    └── secrets.yml            # vault-encrypted
```

#### Key Production Best Practices

```yaml
# 1. Always use FQCN for modules
ansible.builtin.copy:          # ✅
copy:                          # ❌ deprecated

# 2. Pin collection versions in requirements.yml
collections:
  - name: amazon.aws
    version: "6.5.0"           # ✅ pinned
  - name: community.general
    version: ">=7.0.0,<8.0.0"  # ✅ range

# 3. Use 'changed_when: false' for read-only commands
- ansible.builtin.command: systemctl status nginx
  changed_when: false          # ✅

# 4. Use 'no_log: true' for tasks handling secrets
- name: Set database password
  community.mysql.mysql_user:
    password: "{{ db_password }}"
  no_log: true                 # ✅ suppresses task output in logs

# 5. Set timeouts for long-running tasks
- name: Run long database migration
  ansible.builtin.command: /opt/scripts/migrate.sh
  async: 3600        # allow up to 1 hour
  poll: 30           # check every 30 seconds
  register: migration_job

- name: Wait for migration to complete
  ansible.builtin.async_status:
    jid: "{{ migration_job.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 120
  delay: 30

# 6. Rolling updates — never take down all hosts at once
- name: Rolling deploy
  hosts: webservers
  serial: "25%"         # update 25% of hosts at a time
  max_fail_percentage: 0  # stop if any host fails
```

### 12.4 Security Considerations

```yaml
# 1. Least-privilege service account
# Managed nodes: create a dedicated ansible service account
- name: Create ansible service account
  ansible.builtin.user:
    name: ansible_svc
    system: true
    shell: /bin/bash
    comment: "Ansible Automation Account"

# 2. SSH hardening in ansible.cfg
[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes -o BatchMode=yes

# 3. Avoid shell injection — use command over shell
# Bad:
- ansible.builtin.shell: "rm -rf {{ user_input }}"      # ❌ injection risk

# Good:
- ansible.builtin.file:
    path: "{{ user_input }}"
    state: absent                                          # ✅ safe

# 4. Secrets — never in plaintext
# Bad: password: MyPlaintextPassword                      # ❌
# Good: password: "{{ db_password }}"  # from vault      # ✅

# 5. Audit mode — run with --check first in CI
ansible-playbook site.yml --check --diff     # review before applying

# 6. Restrict inventory access
# inventory/production — protect with directory permissions and repo branch protection

# 7. no_log for sensitive tasks
- name: Configure API credentials
  ansible.builtin.template:
    src: api_creds.conf.j2
    dest: /etc/myapp/api_creds.conf
  no_log: true

# 8. File permissions — always specify mode explicitly
- ansible.builtin.copy:
    dest: /etc/myapp/secrets.conf
    mode: '0600'   # ✅ explicit
    # mode omitted → inherits umask → potentially world-readable ❌
```

### 12.5 Testing Ansible Code

#### Molecule — Role testing framework

```bash
pip install molecule molecule-docker
cd roles/nginx
molecule init scenario

# molecule/default/molecule.yml
# ---
# driver:
#   name: docker
# platforms:
#   - name: ubuntu22
#     image: geerlingguy/docker-ubuntu2204-ansible
#     command: /lib/systemd/systemd
#     privileged: true
#   - name: centos9
#     image: geerlingguy/docker-centos9-ansible
#     command: /lib/systemd/systemd
#     privileged: true
# provisioner:
#   name: ansible
# verifier:
#   name: ansible

# Run full test sequence
molecule test

# Individual stages
molecule create      # spin up containers
molecule converge    # run the role
molecule verify      # run tests
molecule destroy     # tear down
```

```yaml
# molecule/default/verify.yml
---
- name: Verify nginx role
  hosts: all
  gather_facts: false
  tasks:
    - name: Verify nginx is installed
      ansible.builtin.command: nginx -v
      changed_when: false
      register: nginx_version
      failed_when: nginx_version.rc != 0

    - name: Verify nginx is running
      ansible.builtin.service_facts:

    - name: Assert nginx service is active
      ansible.builtin.assert:
        that:
          - "'nginx' in services"
          - "services['nginx'].state == 'running'"
        fail_msg: "Nginx is not running!"

    - name: Verify nginx responds on port 80
      ansible.builtin.uri:
        url: http://localhost:80/
        status_code: 200
```

#### Linting with `ansible-lint`

```bash
pip install ansible-lint

# Lint all playbooks
ansible-lint site.yml

# Lint all files in project
ansible-lint

# .ansible-lint config
# ---
# warn_list:
#   - yaml[line-length]
# skip_list:
#   - fqcn-builtins   # if using older Ansible
# exclude_paths:
#   - .git/
#   - molecule/
```

#### CI/CD Pipeline Example (GitHub Actions)

```yaml
# .github/workflows/ansible-ci.yml
---
name: Ansible CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install ansible ansible-lint
      - name: Run ansible-lint
        run: ansible-lint

  molecule:
    name: Molecule Tests
    runs-on: ubuntu-latest
    strategy:
      matrix:
        role: [common, nginx, myapp]
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install ansible molecule molecule-docker docker
      - name: Run Molecule tests
        run: |
          cd roles/${{ matrix.role }}
          molecule test
        env:
          PY_COLORS: '1'
          ANSIBLE_FORCE_COLOR: '1'

  syntax-check:
    name: Syntax Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Ansible
        run: pip install ansible
      - name: Syntax check
        run: ansible-playbook site.yml --syntax-check -i inventory/staging/hosts.yml
```

---

## Quick Reference

### Useful Ad-hoc Commands

```bash
# Ping all hosts
ansible all -m ping

# Run command on specific group
ansible webservers -m command -a "uptime"

# Gather facts
ansible web01 -m setup

# Copy file ad-hoc
ansible webservers -m copy -a "src=/tmp/test.txt dest=/tmp/test.txt"

# Restart service across group
ansible webservers -m service -a "name=nginx state=restarted" --become

# Check disk space
ansible all -m command -a "df -h" | grep -v "ok\|CHANGED"
```

### Jinja2 Filters Cheat Sheet

```jinja2
{{ var | default('fallback') }}        # default value
{{ var | mandatory }}                   # fail if undefined
{{ list | join(', ') }}                 # list to string
{{ string | split(',') }}               # string to list
{{ dict | combine(other_dict) }}        # merge dicts
{{ number | int }}                      # to integer
{{ number | string }}                   # to string
{{ string | upper / lower / title }}    # case
{{ string | trim }}                     # strip whitespace
{{ string | replace('old', 'new') }}    # replace
{{ string | regex_replace('^foo', '') }}# regex replace
{{ list | length }}                     # length
{{ list | first / last }}               # first/last element
{{ list | unique }}                     # deduplicate
{{ list | sort }}                       # sort
{{ list | select('match', 'regex') }}   # filter by regex
{{ dict | dict2items }}                 # dict to list of k/v pairs
{{ items | items2dict }}                # list of k/v to dict
{{ value | b64encode / b64decode }}     # base64
{{ value | hash('sha256') }}            # hash
{{ value | to_json / from_json }}       # JSON
{{ value | to_yaml / from_yaml }}       # YAML
```

### Module Quick Reference

| Task | Module |
|---|---|
| Install package | `ansible.builtin.package` |
| Copy file | `ansible.builtin.copy` |
| Render template | `ansible.builtin.template` |
| Manage service | `ansible.builtin.service` |
| Create user | `ansible.builtin.user` |
| Manage file/dir | `ansible.builtin.file` |
| Run command | `ansible.builtin.command` |
| Run shell command | `ansible.builtin.shell` |
| Check file exists | `ansible.builtin.stat` |
| Edit file lines | `ansible.builtin.lineinfile` |
| Add/remove block | `ansible.builtin.blockinfile` |
| HTTP request | `ansible.builtin.uri` |
| Download file | `ansible.builtin.get_url` |
| Extract archive | `ansible.builtin.unarchive` |
| Set sysctl | `ansible.builtin.sysctl` |
| Manage cron | `ansible.builtin.cron` |
| Set authorized key | `ansible.posix.authorized_key` |
| Manage firewall | `ansible.posix.firewalld` |
| Print message | `ansible.builtin.debug` |
| Explicit fail | `ansible.builtin.fail` |
| Assert conditions | `ansible.builtin.assert` |
| Set variable | `ansible.builtin.set_fact` |

---

*Generated for production and learning use. Tested patterns reflect Ansible ≥ 2.14 / ansible-core ≥ 2.14. Always test in staging before applying to production.*
