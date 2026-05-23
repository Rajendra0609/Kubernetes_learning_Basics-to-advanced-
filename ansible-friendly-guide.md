# Ansible: A Beginner-Friendly Complete Guide

> **How to use this guide:** Read it top to bottom the first time. Every section builds on the previous one.
> Code blocks are real, working examples — not abstract theory.
> Whenever you see a 💡 tip, that's something beginners often miss.

---

## Table of Contents

1. [What is Ansible? (And why should you care?)](#1-what-is-ansible)
2. [Installing Ansible](#2-installing-ansible)
3. [Your First Playbook](#3-your-first-playbook)
4. [Tasks and Modules — The Building Blocks](#4-tasks-and-modules)
5. [Variables and Facts — Making Things Flexible](#5-variables-and-facts)
6. [Control Flow — Loops, Conditions, and Decisions](#6-control-flow)
7. [Handlers — Smart Restarts](#7-handlers)
8. [Roles — Organizing Your Work](#8-roles)
9. [Templates — Dynamic Config Files](#9-templates)
10. [Vault — Keeping Secrets Safe](#10-vault)
11. [Error Handling — What to Do When Things Go Wrong](#11-error-handling)
12. [Advanced Topics — Production Best Practices](#12-advanced-topics)
13. [Ad-hoc Commands — Quick One-Liners](#13-ad-hoc-commands)
14. [CLI Tools — Your Ansible Toolkit](#14-cli-tools)
15. [Collections — Extending Ansible](#15-collections)
16. [Magic Variables — What Ansible Knows Automatically](#16-magic-variables)
17. [Lookup Plugins — Reading Data from Outside](#17-lookup-plugins)
18. [Delegation — Running Tasks on a Different Host](#18-delegation)
19. [Async Tasks — Fire and Forget](#19-async-tasks)
20. [Strategy and Parallelism — How Fast to Go](#20-strategy-and-parallelism)
21. [Privilege Escalation — Using sudo](#21-privilege-escalation)
22. [Connection Plugins — How Ansible Connects](#22-connection-plugins)
23. [More Useful Modules — A Practical Reference](#23-more-useful-modules)
24. [Advanced Jinja2 Filters — Transforming Data](#24-advanced-jinja2-filters)
25. [Dynamic Inventory — When Servers Come and Go](#25-dynamic-inventory)
26. [Fact Caching — Speeding Things Up](#26-fact-caching)
27. [Execution Environments — Portable Ansible](#27-execution-environments)
28. [Multi-Play Playbooks — Orchestrating Everything](#28-multi-play-playbooks)
29. [Windows Management](#29-windows-management)
30. [Network Automation](#30-network-automation)
31. [Quick Reference Cheat Sheet](#31-quick-reference)

---

## 1. What is Ansible?

### Think of Ansible as a remote control for your servers

Imagine you have 50 web servers and you need to install the same software on all of them. Without Ansible, you'd have to log into each one manually and type the same commands 50 times. That's slow, error-prone, and miserable.

With Ansible, you write one script (called a **playbook**) describing what you want, run it once from your own computer, and Ansible goes and does it on all 50 servers simultaneously.

**You are the control node.** Your computer is the "control node" — the one running Ansible. The servers you manage are "managed nodes." Ansible connects to them over SSH (the same secure connection you use when you `ssh user@server`).

### Three things that make Ansible special

**1. Agentless — nothing to install on servers**

Most automation tools require you to install a special program (called an "agent") on every server you want to manage. Ansible doesn't. It connects over SSH, does its work, and leaves. The only requirement on the server is Python (which almost every Linux server already has).

**2. Idempotent — safe to run multiple times**

"Idempotent" is a fancy word for "running it twice has the same result as running it once." If you tell Ansible to install nginx and nginx is already installed, Ansible says "already done" and moves on. It doesn't break things by installing it twice. This makes it safe to run your playbooks on a schedule (like a nightly job) without worrying about them causing problems.

```yaml
# This is idempotent. Run it 100 times — result is always the same.
- name: Make sure nginx is installed
  ansible.builtin.package:
    name: nginx
    state: present   # "present" means: install it if missing, do nothing if already there
```

**3. Human-readable — YAML, not code**

Ansible playbooks are written in YAML — a format that reads almost like plain English. You don't need to be a programmer to understand them.

```yaml
- name: Install nginx and make sure it's running
  hosts: webservers        # run this on all my web servers
  become: true             # use sudo

  tasks:
    - name: Install nginx
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Start nginx
      ansible.builtin.service:
        name: nginx
        state: started
```

Even without knowing Ansible, you can probably guess what this does.

### When to use Ansible vs a shell script

| Situation | Shell script | Ansible |
|---|---|---|
| One quick command, one server | ✅ Use it | Overkill |
| Install software on 50 servers | Painful | ✅ Use it |
| Make sure a config stays the same | Hard | ✅ Use it |
| Store in Git, review before running | Awkward | ✅ Use it |
| Handle secrets safely | Manual | ✅ Use it (Vault) |

### What Ansible is commonly used for

- **Configuration management** — ensure every server has the same packages, configs, and user accounts
- **Application deployment** — push your new app version to all servers at once
- **Infrastructure provisioning** — spin up cloud servers (AWS, Azure, GCP) automatically
- **Security hardening** — apply firewall rules, rotate passwords, enforce policies
- **Orchestration** — do things in order: stop the old app, migrate the database, start the new app

---

## 2. Installing Ansible

### What you need

- **Your computer (control node):** Linux or macOS with Python 3.9+
- **Servers you want to manage:** Just SSH access and Python. No Ansible installation needed on them.

### Check if Python is ready

```bash
python3 --version   # Should say 3.9 or higher
pip3 --version      # Should show a version number
```

### Install Ansible

**On Ubuntu/Debian (Option 1 — latest version via pip, recommended):**

```bash
pip3 install --user ansible
ansible --version   # verify it worked
```

**On Ubuntu/Debian (Option 2 — via apt package manager):**

```bash
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```

**On RHEL/CentOS/Amazon Linux:**

```bash
sudo dnf install ansible-core -y
# or for the latest version:
pip3 install ansible --user
```

**On macOS:**

```bash
brew install ansible
# or
pip3 install ansible
```

### Setting up the config file

Ansible reads its settings from a file called `ansible.cfg`. Put this file in your project folder and Ansible will use it automatically.

Here is a good starting config:

```ini
[defaults]
inventory          = ./inventory        # where your list of servers lives
remote_user        = ubuntu             # which user to SSH in as
host_key_checking  = True               # KEEP THIS TRUE — protects against attackers
forks              = 10                 # connect to 10 servers at once

[ssh_connection]
pipelining         = True               # faster connections
```

💡 **Never set `host_key_checking = False`.** It looks convenient but it lets attackers impersonate your servers.

### The inventory file — your list of servers

The inventory file is just a list of server names or IP addresses, organized into groups.

**Simple INI format (`inventory/hosts.ini`):**

```ini
[webservers]
web01.example.com
web02.example.com

[databases]
db01.example.com ansible_user=postgres

[loadbalancers]
lb01.example.com
```

**YAML format (recommended for complex setups):**

```yaml
# inventory/hosts.yml
all:
  children:
    webservers:
      hosts:
        web01.example.com:
        web02.example.com:
    databases:
      hosts:
        db01.example.com:
          ansible_user: postgres
```

**Test that Ansible can reach your servers:**

```bash
# List all hosts Ansible knows about
ansible all --list-hosts

# Test SSH connectivity to all hosts
ansible all -m ping
```

If you see `"ping": "pong"` for each server, you're ready to go.

---

## 3. Your First Playbook

### What is a playbook?

A playbook is a YAML file that describes what you want Ansible to do. Think of it as a recipe:
- **hosts** — which servers to run on
- **tasks** — what to do (in order)
- **handlers** — things to do when something changes (like restarting a service)

### YAML basics — the format Ansible uses

YAML uses indentation (spaces, never tabs) to show structure. Here are the things that trip people up:

```yaml
# A simple key-value pair
app_name: myapp

# A list (note the dash)
packages:
  - nginx
  - curl
  - git

# A dictionary (nested key-value pairs)
database:
  host: localhost
  port: 5432
  name: myapp_db

# Booleans — use true/false (lowercase preferred)
become: true
debug_mode: false

# Strings with special characters need quotes
message: "Hello: World"         # colon forces quotes
template: 'deploy {{ app }}'   # curly braces force quotes

# Multi-line text (the | keeps line breaks)
config_text: |
  server {
      listen 80;
      server_name example.com;
  }
```

### The anatomy of a playbook

```yaml
---
# The three dashes at the top are optional but conventional in YAML files

- name: Set up web server               # A description of what this "play" does
  hosts: webservers                     # Which servers to run on (matches inventory group)
  become: true                          # Use sudo (needed for installing software)
  gather_facts: true                    # Collect info about each server before starting

  vars:                                 # Variables you can reuse in tasks
    app_name: myapp
    app_port: 8080

  tasks:                                # The list of things to do
    - name: Install nginx               # Description of this task
      ansible.builtin.package:         # The module to use
        name: nginx                    # Parameters for the module
        state: present

    - name: Start nginx
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true                  # Also enable it to start on boot

  handlers:                            # Special tasks that only run when "notified"
    - name: Reload nginx               # This only runs if a task says "notify: Reload nginx"
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

### A complete working example

This playbook installs nginx, creates a simple webpage, and makes sure it's running.

```yaml
---
# playbooks/setup_nginx.yml

- name: Install and configure Nginx
  hosts: webservers
  become: true

  vars:
    nginx_port: 80
    site_name: "My Website"
    document_root: /var/www/html

  tasks:
    - name: Install Nginx
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Create web directory
      ansible.builtin.file:
        path: "{{ document_root }}"
        state: directory
        owner: www-data
        group: www-data
        mode: '0755'

    - name: Create a simple homepage
      ansible.builtin.copy:
        content: "<h1>{{ site_name }} — Running on {{ inventory_hostname }}</h1>"
        dest: "{{ document_root }}/index.html"
        owner: www-data
        mode: '0644'
      notify: Reload Nginx                # Tell Nginx to reload if this changes

    - name: Make sure Nginx is running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Reload Nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

### Running your playbook

```bash
# Step 1: Check for syntax errors first
ansible-playbook playbooks/setup_nginx.yml --syntax-check

# Step 2: Dry run — see what WOULD happen without making any changes
ansible-playbook playbooks/setup_nginx.yml --check --diff

# Step 3: Actually run it
ansible-playbook playbooks/setup_nginx.yml

# Run with more output (useful when debugging)
ansible-playbook playbooks/setup_nginx.yml -v     # a little more detail
ansible-playbook playbooks/setup_nginx.yml -vv    # even more detail
ansible-playbook playbooks/setup_nginx.yml -vvv   # SSH-level debugging
```

### Understanding the output

When you run a playbook, each task shows one of these statuses:

- `ok` — Task ran, nothing changed (already in the desired state)
- `changed` — Task ran and made a change
- `failed` — Task failed (play stops here by default)
- `skipped` — Task was skipped (due to a `when` condition)
- `unreachable` — Can't connect to the server

---

## 4. Tasks and Modules

### What are modules?

Every task uses a **module** — a pre-built tool that does one specific job. Ansible ships with over 3,000 modules covering almost everything you'd want to do to a server. You don't need to know them all; just look up the one you need.

Module names use a three-part format: `namespace.collection.module_name`

- `ansible.builtin.copy` — core module built into Ansible
- `amazon.aws.ec2_instance` — AWS module (from the Amazon collection)
- `community.mysql.mysql_db` — community-contributed MySQL module

💡 **Always use the full name.** Short names like just `copy` still work but are being phased out.

### The most important modules

---

#### `copy` — Copy a file to a server

```yaml
# Copy a local file to the server
- name: Copy app config
  ansible.builtin.copy:
    src: files/app.conf          # path on YOUR computer (control node)
    dest: /etc/myapp/app.conf    # path on the REMOTE server
    owner: myapp                 # who owns the file
    group: myapp
    mode: '0640'                 # file permissions (owner: read/write, group: read, others: none)
    backup: true                 # save a backup before overwriting

# Write content directly (no local file needed)
- name: Create a welcome message
  ansible.builtin.copy:
    content: |
      Welcome! This server is managed by Ansible.
      Unauthorized changes will be overwritten.
    dest: /etc/motd
    mode: '0644'
```

💡 **`copy` is idempotent.** It computes a checksum of the file. If the remote file already matches, it reports `ok` and does nothing. Only if they differ does it copy and report `changed`.

---

#### `template` — Copy a file and fill in variables

Like `copy`, but the file can contain `{{ variable }}` placeholders that get replaced before copying. This is the most powerful way to create config files.

```yaml
- name: Deploy Nginx config
  ansible.builtin.template:
    src: templates/nginx.conf.j2      # the .j2 extension means it's a template
    dest: /etc/nginx/nginx.conf
    owner: root
    mode: '0644'
    validate: /usr/sbin/nginx -t -c %s   # test the config BEFORE putting it in place
  notify: Reload Nginx

# The template file (nginx.conf.j2) might look like:
# worker_processes {{ nginx_workers | default(2) }};
# listen {{ nginx_port }};
# server_name {{ inventory_hostname }};
```

The `validate` option is very useful — it runs a command to check the file is valid before placing it. If the check fails, the file is NOT deployed. This prevents broken configs from reaching production.

---

#### `package` — Install or remove software

```yaml
# Install a single package
- name: Install nginx
  ansible.builtin.package:
    name: nginx
    state: present    # "present" = install it

# Install multiple packages at once
- name: Install essential tools
  ansible.builtin.package:
    name:
      - curl
      - git
      - htop
      - unzip
    state: present

# Remove a package
- name: Remove telnet (security risk)
  ansible.builtin.package:
    name: telnet
    state: absent     # "absent" = remove it

# Install the latest version
- name: Keep OpenSSL updated
  ansible.builtin.package:
    name: openssl
    state: latest
```

💡 **`package` works on any Linux distro.** Ansible figures out whether to use `apt`, `yum`, or `dnf` automatically. If you need distro-specific options, use `apt` or `dnf` directly.

---

#### `service` — Start, stop, restart services

```yaml
- name: Make sure nginx is running and starts on boot
  ansible.builtin.service:
    name: nginx
    state: started    # started / stopped / restarted / reloaded
    enabled: true     # automatically start on boot

# Restart a service
- name: Restart the database
  ansible.builtin.service:
    name: postgresql
    state: restarted

# Reload (less disruptive than restart — no downtime for nginx)
- name: Reload nginx config
  ansible.builtin.service:
    name: nginx
    state: reloaded
```

---

#### `file` — Create folders, symlinks, set permissions

```yaml
# Create a directory
- name: Create app directory
  ansible.builtin.file:
    path: /opt/myapp
    state: directory
    owner: myapp
    group: myapp
    mode: '0750'

# Create multiple directories with a loop
- name: Create all needed directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: myapp
    mode: '0750'
  loop:
    - /opt/myapp/config
    - /opt/myapp/logs
    - /opt/myapp/data

# Delete a file
- name: Remove temporary file
  ansible.builtin.file:
    path: /tmp/old_install.sh
    state: absent

# Create a symlink
- name: Point "current" to the new release
  ansible.builtin.file:
    src: /opt/myapp/releases/v2.1.0
    dest: /opt/myapp/current
    state: link
    force: true
```

---

#### `user` — Create and manage user accounts

```yaml
# Create a service account (for running an app)
- name: Create app user
  ansible.builtin.user:
    name: myapp
    comment: "MyApp Service Account"
    system: true           # system account (low UID, no home dir by default)
    shell: /sbin/nologin   # can't log in interactively
    create_home: false

# Create a developer user
- name: Create developer account
  ansible.builtin.user:
    name: alice
    groups:
      - sudo
      - docker
    append: true           # ADD to groups, don't replace existing groups
    shell: /bin/bash

# Delete an old account
- name: Remove departed employee
  ansible.builtin.user:
    name: jdoe
    state: absent
    remove: true           # also delete their home directory
```

---

#### `command` and `shell` — Run a command

```yaml
# command: runs a single program safely (no shell interpretation)
- name: Run database migration
  ansible.builtin.command:
    cmd: /opt/myapp/bin/migrate --env production
    chdir: /opt/myapp/current    # run from this directory
    creates: /opt/myapp/.migrated # skip if this file already exists (idempotency trick)

# shell: runs through the shell (allows pipes, redirects, &&, ||)
- name: Clean up old logs
  ansible.builtin.shell:
    cmd: find /var/log/myapp -name "*.log" -mtime +7 | xargs gzip
  changed_when: false    # this is maintenance, not a config change

# Capture the output of a command
- name: Get app version
  ansible.builtin.command: /opt/myapp/bin/myapp --version
  register: version_output      # save the output to a variable
  changed_when: false           # reading a version doesn't change state

- name: Show the version
  ansible.builtin.debug:
    msg: "Running version: {{ version_output.stdout }}"
```

💡 **Prefer specific modules over `command`/`shell`.** Use `package` to install things, `service` for services, `file` for files. Only use `command` or `shell` when no proper module exists. `shell` is a security risk with user-provided input.

---

#### `debug` — Print messages during a run

```yaml
# Print a variable's value
- name: Show which OS we're on
  ansible.builtin.debug:
    var: ansible_distribution      # prints the value of this variable

# Print a custom message
- name: Show deployment info
  ansible.builtin.debug:
    msg: "Deploying {{ app_name }} version {{ app_version }} to {{ inventory_hostname }}"
```

### Saving task results with `register`

Any task can save its output using `register`. You can then use that data in later tasks.

```yaml
- name: Check if config file exists
  ansible.builtin.stat:
    path: /etc/myapp/app.conf
  register: config_file            # save the result

- name: Create config if it's missing
  ansible.builtin.copy:
    src: files/app.conf.default
    dest: /etc/myapp/app.conf
  when: not config_file.stat.exists   # only run if the file doesn't exist
```

Common attributes on registered results:
- `result.changed` — did something change?
- `result.failed` — did it fail?
- `result.stdout` — text output from a command
- `result.stderr` — error output from a command
- `result.rc` — exit code (0 = success)
- `result.stat.exists` — does the file exist? (from the `stat` module)

---

## 5. Variables and Facts

### Why use variables?

Variables let you write one playbook that works in multiple environments. Instead of hardcoding `nginx_port: 80` in ten places, you define it once as a variable and reference it everywhere as `{{ nginx_port }}`.

### Defining variables in a playbook

```yaml
- name: Deploy application
  hosts: webservers
  vars:
    app_name: myapp
    app_version: "2.1.0"
    app_port: 8080
    # A dictionary variable
    database:
      host: db01.example.com
      port: 5432
      name: myapp_db
    # A list variable
    supported_envs:
      - staging
      - production

  tasks:
    - name: Show deployment info
      ansible.builtin.debug:
        msg: "Deploying {{ app_name }} v{{ app_version }} on port {{ app_port }}"

    # Access dictionary values with a dot
    - name: Show database host
      ansible.builtin.debug:
        msg: "DB: {{ database.host }}:{{ database.port }}/{{ database.name }}"
```

### Group and host variables — different values per group

Create a `group_vars/` folder next to your inventory and Ansible will automatically load variables for each group.

```
inventory/
├── hosts.yml
├── group_vars/
│   ├── all.yml           # applies to ALL hosts
│   ├── webservers.yml    # applies to the "webservers" group only
│   └── databases.yml
└── host_vars/
    └── web01.yml         # applies to web01 only
```

```yaml
# group_vars/all.yml — applies everywhere
ansible_python_interpreter: /usr/bin/python3
timezone: UTC

# group_vars/webservers.yml
nginx_port: 80
nginx_workers: 4

# group_vars/staging.yml (if you have a staging group)
app_version: "2.2.0-rc1"
log_level: debug

# group_vars/production.yml
app_version: "2.1.0"
log_level: warning
```

This means when you run on staging, `app_version` is `2.2.0-rc1`. On production it's `2.1.0`. Same playbook, different behavior.

### Variable precedence — who wins when there's a conflict?

From lowest priority to highest (higher wins):

1. Role defaults (`roles/myrole/defaults/main.yml`) — easiest to override
2. Inventory group variables
3. Inventory host variables
4. Playbook `vars:`
5. Task `vars:`
6. `set_fact` / `register`
7. Command-line `-e` flag — always wins

💡 **Rule of thumb:** Put defaults in `defaults/main.yml`, environment-specific values in `group_vars/`, and sensitive values in Vault (see Section 10).

### Creating variables on the fly with `set_fact`

```yaml
- name: Decide which deployment slot to use
  ansible.builtin.set_fact:
    deployment_slot: "{{ 'blue' if current_slot == 'green' else 'green' }}"

- name: Show which slot we're deploying to
  ansible.builtin.debug:
    msg: "Deploying to the {{ deployment_slot }} slot"
```

### Facts — information Ansible collects automatically

When Ansible connects to a server, it automatically collects information about it: the OS, IP address, amount of RAM, CPU count, etc. These are called **facts** and they're available as variables in your playbook.

```yaml
# Some commonly used facts:
ansible_hostname                # "web01"
ansible_distribution            # "Ubuntu"
ansible_distribution_version   # "22.04"
ansible_os_family               # "Debian" (covers Ubuntu too)
ansible_default_ipv4.address   # "10.0.1.15"
ansible_memtotal_mb             # 7982  (total RAM in MB)
ansible_processor_vcpus         # 4     (number of CPU cores)
ansible_kernel                  # "5.15.0-aws"
```

See all facts for a specific server:

```bash
ansible web01 -m setup
```

**Using facts in playbooks:**

```yaml
# Install the right package name depending on the OS family
- name: Install SSL dev library
  ansible.builtin.package:
    name: "{{ 'libssl-dev' if ansible_os_family == 'Debian' else 'openssl-devel' }}"
    state: present

# Set memory settings based on how much RAM the server has
- name: Set swappiness (use swap less on high-memory servers)
  ansible.builtin.sysctl:
    name: vm.swappiness
    value: "{{ '10' if ansible_memtotal_mb > 8192 else '60' }}"
    state: present
```

### Skipping fact gathering for speed

Fact gathering takes 2–5 seconds per server. If you don't need facts, skip it:

```yaml
- name: Quick connectivity check
  hosts: all
  gather_facts: false    # skip fact gathering
  tasks:
    - name: Check uptime
      ansible.builtin.command: uptime
      changed_when: false
```

---

## 6. Control Flow

### `when` — Run a task only if a condition is true

```yaml
# Only run on Ubuntu/Debian systems
- name: Install apache2
  ansible.builtin.package:
    name: apache2
    state: present
  when: ansible_os_family == "Debian"

# Multiple conditions — ALL must be true (AND logic)
- name: Configure production database
  ansible.builtin.template:
    src: db.conf.j2
    dest: /etc/myapp/db.conf
  when:
    - env == "production"
    - ansible_memtotal_mb >= 4096     # only on servers with 4GB+ RAM

# OR logic
- name: Install ufw firewall
  ansible.builtin.package:
    name: ufw
    state: present
  when: ansible_distribution == "Ubuntu" or ansible_distribution == "Debian"

# Only run if a variable is defined
- name: Use optional setting
  ansible.builtin.debug:
    msg: "Custom port is {{ custom_port }}"
  when: custom_port is defined

# Use the result of a previous task
- name: Check if config exists
  ansible.builtin.stat:
    path: /etc/myapp/app.conf
  register: config_file

- name: Create config only if missing
  ansible.builtin.copy:
    src: files/app.conf.default
    dest: /etc/myapp/app.conf
  when: not config_file.stat.exists
```

### `loop` — Repeat a task for multiple items

Instead of writing the same task five times with different values, use a loop.

```yaml
# Simple loop over a list
- name: Create required users
  ansible.builtin.user:
    name: "{{ item }}"
    system: true
    shell: /sbin/nologin
  loop:
    - myapp
    - myapp-worker
    - myapp-scheduler

# Loop over a list of dictionaries
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

### `until` — Keep retrying until something is ready

Useful when you start a service and need to wait for it to respond.

```yaml
- name: Wait for the app to be ready
  ansible.builtin.uri:
    url: "http://localhost:{{ app_port }}/health"
    status_code: 200
  register: health_check
  until: health_check.status == 200
  retries: 12          # try up to 12 times
  delay: 10            # wait 10 seconds between attempts
```

### `block`, `rescue`, `always` — Try/catch/finally

This is Ansible's equivalent of try/catch/finally from programming. Use it when you want to handle errors gracefully.

```yaml
- name: Deploy app with automatic rollback on failure
  block:
    # These tasks run normally
    - name: Stop old app version
      ansible.builtin.service:
        name: myapp
        state: stopped

    - name: Deploy new version
      ansible.builtin.unarchive:
        src: "{{ artifact_url }}"
        dest: /opt/myapp/releases/
        remote_src: true

    - name: Start new version
      ansible.builtin.service:
        name: myapp
        state: started

    - name: Verify new version works
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200

  rescue:
    # These tasks run if ANY task in the block above FAILS
    - name: ROLLBACK — restart old version
      ansible.builtin.service:
        name: myapp
        state: restarted

    - name: Log the failure
      ansible.builtin.debug:
        msg: "Deployment failed on {{ inventory_hostname }} — rolled back to previous version"

  always:
    # These tasks ALWAYS run — whether the block succeeded or failed
    - name: Remove deployment lock file
      ansible.builtin.file:
        path: /var/lock/myapp-deploy.lock
        state: absent
```

### `include_tasks` vs `import_tasks` — splitting big playbooks into files

When your task list gets long, split it into separate files.

```yaml
# tasks/main.yml
- name: Import setup tasks (always included, processed at load time)
  ansible.builtin.import_tasks: setup.yml

- name: Include OS-specific tasks (loaded at runtime, based on the OS fact)
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}_tasks.yml"
```

| | `import_tasks` | `include_tasks` |
|---|---|---|
| When | Loaded before run starts | Loaded during run |
| Supports loops | No | Yes |
| Best for | Static task files | Dynamic/conditional task files |

### Tags — run only part of a playbook

Tags let you run just a specific section of a large playbook.

```yaml
tasks:
  - name: Install packages
    ansible.builtin.package:
      name: nginx
      state: present
    tags: packages          # this task has the "packages" tag

  - name: Deploy config
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    tags:
      - config
      - deploy
```

```bash
# Run only tasks tagged "packages"
ansible-playbook site.yml --tags packages

# Skip tasks tagged "deploy"
ansible-playbook site.yml --skip-tags deploy

# See what tags exist
ansible-playbook site.yml --list-tags
```

---

## 7. Handlers

### What are handlers?

Handlers are tasks that only run when something else changes — and they only run once, even if notified multiple times.

**The most common use case:** Restart a service when its config changes. If three config files change in one run, the service only restarts once (at the end), not three times.

```yaml
tasks:
  - name: Update main nginx config
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: Restart nginx         # signal the handler

  - name: Update SSL certificate
    ansible.builtin.copy:
      src: files/ssl.crt
      dest: /etc/ssl/certs/mysite.crt
    notify: Restart nginx         # still only restarts once

  - name: Update virtual host config
    ansible.builtin.template:
      src: vhost.conf.j2
      dest: /etc/nginx/sites-available/mysite.conf
    notify: Restart nginx         # nginx still restarts once, at the end

handlers:
  - name: Restart nginx
    ansible.builtin.service:
      name: nginx
      state: restarted
```

💡 **Handlers run at the end of the play, not immediately.** If you need a handler to run right now (before subsequent tasks), use `meta: flush_handlers`:

```yaml
- name: Deploy new config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: Reload nginx

# Force handlers to run RIGHT NOW before continuing
- ansible.builtin.meta: flush_handlers

- name: Verify nginx is working after reload
  ansible.builtin.uri:
    url: http://localhost/health
    status_code: 200
```

---

## 8. Roles

### What is a role?

A role is a way to package up a set of related tasks, variables, templates, and files into a reusable, shareable unit. Instead of copying your nginx setup into every project, you create an "nginx role" once and reuse it everywhere.

### The role folder structure

When you create a role called `nginx`, it looks like this:

```
roles/
└── nginx/
    ├── tasks/
    │   ├── main.yml          # Entry point — Ansible starts here
    │   ├── install.yml       # Installation tasks
    │   └── configure.yml     # Configuration tasks
    ├── handlers/
    │   └── main.yml          # Handlers (e.g., "Reload nginx")
    ├── templates/
    │   └── nginx.conf.j2     # Jinja2 template files
    ├── files/
    │   └── dhparams.pem      # Static files to copy
    ├── defaults/
    │   └── main.yml          # Default variable values (easily overridden)
    ├── vars/
    │   └── main.yml          # Internal variables (not meant to be changed)
    └── README.md
```

### Creating a role

```bash
# Create the skeleton structure automatically
ansible-galaxy role init roles/nginx
```

### A minimal nginx role

```yaml
# roles/nginx/defaults/main.yml — defaults users can override
nginx_port: 80
nginx_workers: auto
nginx_document_root: /var/www/html

# roles/nginx/tasks/main.yml — entry point
---
- name: Install Nginx
  ansible.builtin.import_tasks: install.yml

- name: Configure Nginx
  ansible.builtin.import_tasks: configure.yml

# roles/nginx/tasks/install.yml
---
- name: Install nginx package
  ansible.builtin.package:
    name: nginx
    state: present

- name: Create document root
  ansible.builtin.file:
    path: "{{ nginx_document_root }}"
    state: directory
    owner: www-data
    mode: '0755'

# roles/nginx/handlers/main.yml
---
- name: Reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded

- name: Restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted
```

### Using roles in a playbook

```yaml
# site.yml
- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - common                  # Apply the "common" role
    - role: nginx             # Apply the "nginx" role
      vars:                   # Override defaults just for this play
        nginx_port: 8080
    - role: myapp
      when: env == "production"   # Only apply on production
```

### Ansible Galaxy — downloading community roles

Ansible Galaxy is a free library of roles written by the community.

```bash
# Install a popular nginx role from Galaxy
ansible-galaxy role install geerlingguy.nginx

# Install a collection (a package of many modules/roles)
ansible-galaxy collection install amazon.aws

# Install from a requirements file (best practice for projects)
ansible-galaxy install -r requirements.yml
```

```yaml
# requirements.yml
roles:
  - name: geerlingguy.nginx
    version: "3.2.0"

collections:
  - name: amazon.aws
    version: ">=6.0.0"
  - name: community.general
```

---

## 9. Templates

### What is a template?

A template is a config file with placeholders that get filled in when Ansible deploys it. Ansible uses a templating language called **Jinja2** for this. Template files have a `.j2` extension.

### Basic Jinja2 syntax

```jinja2
{# This is a comment — it won't appear in the output #}

{# Variable substitution — double curly braces #}
server_name = {{ inventory_hostname }};
listen {{ nginx_port }};

{# Filters — transform a value (pipe character) #}
{{ app_name | upper }}              {# outputs: MYAPP #}
{{ description | default('N/A') }} {# use a fallback if variable is undefined #}
{{ items | join(', ') }}            {# join a list into a string #}
{{ hostname | replace('.', '-') }} {# replace characters #}

{# If/else condition #}
{% if nginx_ssl_enabled %}
listen 443 ssl;
{% else %}
listen 80;
{% endif %}

{# Loop — repeat for each item in a list #}
{% for server in backend_servers %}
server {{ server.host }}:{{ server.port }};
{% endfor %}
```

### A real-world nginx config template

```jinja2
{# templates/nginx.conf.j2 #}

worker_processes {{ nginx_workers | default('auto') }};

events {
    worker_connections {{ nginx_connections | default(1024) }};
}

http {
    server {
        listen {{ nginx_port | default(80) }};
        server_name {{ inventory_hostname }};

        {% if nginx_ssl_enabled | default(false) %}
        listen 443 ssl;
        ssl_certificate     {{ ssl_certificate_path }};
        ssl_certificate_key {{ ssl_key_path }};
        {% endif %}

        root {{ nginx_document_root }};

        {% for location in nginx_locations | default([]) %}
        location {{ location.path }} {
            proxy_pass http://{{ location.backend }};
        }
        {% endfor %}
    }
}
```

Deploy it like this:

```yaml
- name: Deploy nginx config
  ansible.builtin.template:
    src: templates/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    mode: '0644'
    validate: "/usr/sbin/nginx -t -c %s"   # validate BEFORE deploying
  notify: Reload nginx
```

### Protecting against missing variables

```jinja2
{# BAD — fails if db_port is not defined #}
port = {{ db_port }}

{# GOOD — use a default value #}
port = {{ db_port | default(5432) }}

{# STRICT — fail with a clear error message if undefined #}
database_url = {{ database_url | mandatory("database_url must be set in group_vars") }}
```

---

## 10. Vault

### The problem: secrets in version control

Never put passwords, API keys, or private keys directly in your playbooks or variable files — especially not in Git. Ansible Vault solves this by encrypting sensitive values.

### Encrypting a single value

```bash
# Encrypt a password — paste the output into your vars file
ansible-vault encrypt_string 'MySuperSecretPassword!' --name 'db_password'
```

Output (paste this directly into your vars file):
```yaml
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  6238323865373839343832303966...
```

The variable name (`db_password`) is visible in the file, but the value is encrypted. This is the recommended approach — it makes reviewing diffs easier.

### Encrypting an entire file

```bash
# Encrypt a whole file (good for SSL private keys)
ansible-vault encrypt vars/secrets.yml

# View an encrypted file
ansible-vault view vars/secrets.yml

# Edit an encrypted file (opens in your default editor)
ansible-vault edit vars/secrets.yml

# Decrypt a file (careful — creates plaintext!)
ansible-vault decrypt vars/secrets.yml
```

### Using vault-encrypted variables in playbooks

```yaml
# playbook.yml
- name: Configure database
  hosts: dbservers
  vars_files:
    - vars/common.yml
    - vars/secrets.yml       # this file is vault-encrypted

  tasks:
    - name: Create database user
      community.mysql.mysql_user:
        name: myapp
        password: "{{ db_password }}"   # comes from the encrypted file
        state: present
      no_log: true                       # don't print the password in logs!
```

### Running a playbook that uses vault

```bash
# Method 1: type the vault password at runtime
ansible-playbook site.yml --ask-vault-pass

# Method 2: read from a password file (for CI/CD)
ansible-playbook site.yml --vault-password-file ~/.vault_pass
```

### Best practices for vault

```bash
# NEVER commit the vault password file to git
echo ".vault_pass" >> .gitignore

# For CI/CD (GitHub Actions example):
# Store the password in your CI secrets, then:
echo "$ANSIBLE_VAULT_PASSWORD" > /tmp/vault_pass
ansible-playbook site.yml --vault-password-file /tmp/vault_pass
rm /tmp/vault_pass     # clean up immediately after
```

---

## 11. Error Handling

### The default behavior

By default, if any task fails on a host, Ansible stops running tasks on that host and marks it as failed. Other hosts in the same play continue.

### `ignore_errors` — continue despite failure

```yaml
- name: Check for optional tool
  ansible.builtin.command: /opt/optional-tool/status
  register: tool_status
  ignore_errors: true      # continue even if this fails

- name: Warn if tool missing
  ansible.builtin.debug:
    msg: "Optional tool not installed — some features unavailable"
  when: tool_status is failed
```

💡 **Use `ignore_errors` sparingly.** It hides real problems. The next option is usually better.

### `failed_when` — define exactly what counts as failure

```yaml
# A script that returns exit code 3 when "nothing to do" — that's OK
- name: Run maintenance script
  ansible.builtin.command: /opt/scripts/maintenance.sh
  register: result
  failed_when:
    - result.rc != 0
    - result.rc != 3     # exit code 3 means "nothing to do" — not a failure

# Fail based on output content, not exit code
- name: Check SSL certificate
  ansible.builtin.command: openssl x509 -in /etc/ssl/cert.pem -noout -enddate
  register: cert_info
  changed_when: false
  failed_when: "'expired' in cert_info.stdout | lower"
```

### `changed_when` — control when a task reports "changed"

`command` and `shell` tasks always report `changed`, even for read-only operations. Fix this:

```yaml
# This reads a status — it doesn't change anything
- name: Get application status
  ansible.builtin.command: /opt/myapp/bin/status
  register: app_status
  changed_when: false          # tell Ansible this never causes a change

# Only report changed if the output says something actually changed
- name: Run idempotent migration script
  ansible.builtin.command: /opt/scripts/migrate.sh
  register: result
  changed_when: "'applied' in result.stdout"
```

### `any_errors_fatal` — stop everything on first failure

```yaml
- name: Critical pre-deployment check
  hosts: webservers
  any_errors_fatal: true     # if ANY server fails, stop ALL servers immediately
  tasks:
    - name: Check disk space
      ansible.builtin.command: df -BG /opt --output=avail
      register: disk
      changed_when: false
      failed_when: disk.stdout_lines[1] | trim | int < 5
```

### Debugging when things go wrong

```bash
# See verbose output
ansible-playbook site.yml -v         # basic
ansible-playbook site.yml -vv        # more detail
ansible-playbook site.yml -vvv       # SSH-level detail

# Step through tasks one by one (press Enter to proceed or Ctrl+C to stop)
ansible-playbook site.yml --step

# Start from a specific task (skip tasks before it)
ansible-playbook site.yml --start-at-task "Deploy application config"

# Check syntax without running
ansible-playbook site.yml --syntax-check

# Dry run — show what would change without doing it
ansible-playbook site.yml --check --diff
```

---

## 12. Advanced Topics

### Recommended project structure for real projects

```
my-ansible-project/
├── ansible.cfg                  # project settings
├── requirements.yml             # Galaxy roles and collections to install
├── site.yml                     # master playbook
├── inventory/
│   ├── staging/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   └── production/
│       ├── hosts.yml
│       ├── group_vars/
│       │   ├── all.yml
│       │   └── webservers.yml
│       └── host_vars/
│           └── web01.yml
├── playbooks/
│   ├── deploy.yml
│   ├── rollback.yml
│   └── maintenance.yml
├── roles/
│   ├── common/
│   ├── nginx/
│   └── myapp/
└── vars/
    ├── common.yml
    └── secrets.yml              # vault-encrypted
```

### Key production best practices

**1. Always use full module names (FQCN)**
```yaml
ansible.builtin.copy:    # correct
copy:                    # deprecated shorthand
```

**2. Never put secrets in plaintext**
```yaml
password: "{{ db_password }}"    # from vault — correct
password: "MyPassword123"        # NEVER do this
```

**3. Mark read-only commands as non-changing**
```yaml
- ansible.builtin.command: systemctl status nginx
  changed_when: false   # reading status changes nothing
```

**4. Suppress sensitive task output**
```yaml
- name: Set database password
  community.mysql.mysql_user:
    password: "{{ db_password }}"
  no_log: true          # prevents password from appearing in logs
```

**5. Rolling updates — never update all servers at once**
```yaml
- name: Deploy app
  hosts: webservers
  serial: "25%"             # update only 25% of servers at a time
  max_fail_percentage: 0    # stop if any server fails
```

**6. Always test before running in production**
```bash
ansible-playbook site.yml --check --diff   # dry run
ansible-playbook site.yml --limit staging  # run on staging first
```

### Security considerations

```yaml
# 1. Create a dedicated service account for Ansible on all servers
- name: Create Ansible service account
  ansible.builtin.user:
    name: ansible_svc
    system: true
    shell: /bin/bash

# 2. Use 'command' instead of 'shell' when possible (no injection risk)
# Bad:
- ansible.builtin.shell: "rm -rf {{ user_input }}"       # injection risk!
# Good:
- ansible.builtin.file:
    path: "{{ user_input }}"
    state: absent                                          # safe

# 3. Set explicit file permissions — never omit mode
- ansible.builtin.copy:
    dest: /etc/myapp/secrets.conf
    mode: '0600'    # owner read/write only — secure
    # Omitting mode means it inherits the umask and could be world-readable!
```

### Testing your Ansible code

**Syntax check before every run:**
```bash
ansible-playbook site.yml --syntax-check
```

**Lint your code with `ansible-lint`:**
```bash
pip install ansible-lint
ansible-lint site.yml
```

**Role testing with Molecule:**
```bash
pip install molecule molecule-docker
cd roles/nginx
molecule test    # spins up a container, runs your role, verifies it worked
```

---

## 13. Ad-hoc Commands

### What is an ad-hoc command?

Sometimes you just want to run one quick thing across your servers without writing a full playbook. Ad-hoc commands are one-liners for that.

**Format:**
```bash
ansible <who> -m <module> -a "<arguments>"
```

### Common examples

```bash
# Check if all servers are reachable
ansible all -m ping

# Run any command on all web servers
ansible webservers -m command -a "uptime"

# Check disk space everywhere
ansible all -m command -a "df -h"

# Check memory
ansible all -m command -a "free -m"

# Install a package (note --become for sudo)
ansible webservers -m package -a "name=nginx state=present" --become

# Remove a package
ansible webservers -m package -a "name=telnet state=absent" --become

# Copy a file
ansible webservers -m copy -a "src=/tmp/test.conf dest=/tmp/test.conf mode=0644"

# Restart a service
ansible webservers -m service -a "name=nginx state=restarted" --become

# Create a user
ansible all -m user -a "name=alice state=present shell=/bin/bash" --become

# Reboot all web servers
ansible webservers -m reboot --become

# See all facts about a server
ansible web01 -m setup
ansible web01 -m setup -a "filter=ansible_memory_mb"   # just memory info
```

### Useful flags for ad-hoc commands

```bash
-i inventory/hosts.yml     # specify inventory file
-u ec2-user                # SSH as this user
-b / --become              # use sudo
-K                         # ask for sudo password
-f 20                      # connect to 20 servers at once
--limit web01              # only run on this specific host
--check                    # dry run (don't make changes)
-v / -vv                   # more output
```

---

## 14. CLI Tools

Ansible comes with several command-line tools beyond `ansible` and `ansible-playbook`.

### `ansible-doc` — Look up module documentation

```bash
# Show all available modules
ansible-doc -l

# Search for modules about a topic
ansible-doc -l | grep user

# Full docs for a module
ansible-doc ansible.builtin.copy

# Show just the examples section
ansible-doc -e ansible.builtin.copy
```

### `ansible-config` — View your current configuration

```bash
# Show all config values
ansible-config dump

# Show only values that differ from the defaults
ansible-config dump --only-changed

# Show descriptions of all config options
ansible-config list
```

### `ansible-inventory` — Inspect your inventory

```bash
# List all hosts as JSON
ansible-inventory --list

# Show a visual tree of your inventory
ansible-inventory --graph

# Show the tree including all variables
ansible-inventory --graph --vars

# Show all variables for one specific host
ansible-inventory --host web01.example.com
```

### `ansible-console` — Interactive Ansible REPL

Like a shell, but you run Ansible modules interactively:

```bash
ansible-console webservers

# Inside the console:
# webservers$ ping
# webservers$ package name=curl state=present
# webservers$ setup filter=ansible_os_family
# webservers$ exit
```

### `ansible-playbook` — Key flags reference

```bash
# Targeting
ansible-playbook site.yml --limit webservers          # only run on webservers
ansible-playbook site.yml --limit "webservers:!web03" # exclude web03
ansible-playbook site.yml --tags deploy               # only tagged tasks
ansible-playbook site.yml --skip-tags debug           # skip debug tasks
ansible-playbook site.yml --start-at-task "Deploy config"  # resume mid-play

# Testing
ansible-playbook site.yml --check                     # dry run
ansible-playbook site.yml --diff                      # show file changes
ansible-playbook site.yml --syntax-check              # check for errors

# Authentication
ansible-playbook site.yml -u ec2-user                 # SSH as this user
ansible-playbook site.yml --ask-vault-pass            # prompt for vault password
ansible-playbook site.yml -e "env=staging version=2.1" # pass variables
```

---

## 15. Collections

### What is a collection?

A collection is a package that bundles together related modules, roles, and plugins. For example, `amazon.aws` is a collection that contains all the modules for managing AWS resources.

### Installing collections

```bash
# Install from Ansible Galaxy
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install community.mysql
ansible-galaxy collection install kubernetes.core

# Install from a requirements file (best practice)
ansible-galaxy collection install -r requirements.yml
```

```yaml
# requirements.yml
collections:
  - name: amazon.aws
    version: ">=6.0.0"
  - name: community.general
  - name: community.mysql
```

### Using collection modules

```yaml
# AWS modules
- name: Launch EC2 instance
  amazon.aws.ec2_instance:
    name: "web-server-01"
    instance_type: t3.medium
    image_id: ami-0f5ee92e2d63afc18
    state: running

# MySQL modules
- name: Create database
  community.mysql.mysql_db:
    name: myapp_production
    state: present
```

---

## 16. Magic Variables

Magic variables are special variables that Ansible creates automatically. You don't define them — they're always available.

### The most useful magic variables

```yaml
# inventory_hostname — the name of the current server as it appears in inventory
# Use in file names, configs, log messages
- name: Create per-server log file
  ansible.builtin.file:
    path: "/var/log/{{ inventory_hostname }}.log"
    state: touch

# groups — a dictionary of all your inventory groups
# groups['webservers'] → list of all webserver hostnames
- name: Show all web servers
  ansible.builtin.debug:
    msg: "Web servers: {{ groups['webservers'] | join(', ') }}"

# group_names — list of groups the current server belongs to
- name: Extra config for production servers only
  ansible.builtin.template:
    src: prod_extra.conf.j2
    dest: /etc/myapp/extra.conf
  when: "'production' in group_names"

# hostvars — variables for ANY host in your inventory
# Useful for getting the IP address of another server
- name: Configure app to connect to database
  ansible.builtin.template:
    src: app.conf.j2
    dest: /etc/myapp/app.conf
  vars:
    db_ip: "{{ hostvars['db01.example.com']['ansible_default_ipv4']['address'] }}"

# inventory_dir — path to your inventory directory
# ansible_play_hosts — list of all hosts currently in the play
# ansible_play_batch — the current batch of hosts (when using serial)
```

### Using `hostvars` in templates

This is extremely powerful — you can build configs that reference the IP addresses of other servers:

```jinja2
{# haproxy.cfg.j2 — build a load balancer config from all app servers #}
backend app_servers
    balance roundrobin
    {% for host in groups['appservers'] %}
    server {{ host }} {{ hostvars[host]['ansible_default_ipv4']['address'] }}:8080 check
    {% endfor %}
```

---

## 17. Lookup Plugins

Lookups let you pull data from external sources on your control node and use it as a variable. They run on YOUR computer (the control node), not on the remote servers.

### Common lookups

```yaml
# Read a local file's contents
- name: Deploy SSH public key from local file
  ansible.posix.authorized_key:
    user: deploy
    key: "{{ lookup('ansible.builtin.file', '~/.ssh/deploy_key.pub') }}"

# Read an environment variable
- name: Use CI pipeline version
  ansible.builtin.debug:
    msg: "Building: {{ lookup('ansible.builtin.env', 'BUILD_VERSION', default='dev') }}"

# Run a command locally and use its output
- name: Embed git SHA in deployment
  vars:
    git_sha: "{{ lookup('ansible.builtin.pipe', 'git rev-parse --short HEAD') }}"
  ansible.builtin.template:
    src: version.txt.j2
    dest: /opt/myapp/version.txt

# Fetch from a URL
- name: Get latest release version from GitHub API
  vars:
    release: "{{ lookup('ansible.builtin.url', 'https://api.github.com/repos/helm/helm/releases/latest', split_lines=false) | from_json }}"
  ansible.builtin.set_fact:
    helm_version: "{{ release.tag_name }}"

# Find all files matching a pattern
- name: Copy all config files
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: /etc/myapp/conf.d/
  loop: "{{ lookup('ansible.builtin.fileglob', 'files/conf.d/*.conf', wantlist=True) }}"
```

### Error handling with lookups

```yaml
# Provide a fallback if the variable doesn't exist
var: "{{ lookup('ansible.builtin.env', 'OPTIONAL_VAR') | default('fallback_value') }}"

# Fail with a helpful message if a required file is missing
- name: Load required key
  vars:
    secret: "{{ lookup('ansible.builtin.file', '/run/secrets/api_key', errors='strict') }}"
```

---

## 18. Delegation

### Running a task on a different server

By default, each task runs on the host in the `hosts:` list. `delegate_to` lets you run a task on a completely different host while still using the current host's variables.

**Real-world use case:** Before updating a web server, tell the load balancer to stop sending traffic to it.

```yaml
- name: Update web servers one at a time
  hosts: webservers
  serial: 1                         # one server at a time

  tasks:
    - name: Remove this server from load balancer
      ansible.builtin.uri:
        url: "http://lb01/api/drain/{{ inventory_hostname }}"
        method: POST
      delegate_to: lb01.example.com  # run THIS task on the load balancer

    - name: Update the app
      ansible.builtin.package:
        name: myapp
        state: latest

    - name: Add this server back to load balancer
      ansible.builtin.uri:
        url: "http://lb01/api/enable/{{ inventory_hostname }}"
        method: POST
      delegate_to: lb01.example.com

# Run on your control node (localhost) — great for cloud API calls
- name: Take database snapshot before migration
  amazon.aws.rds_snapshot:
    db_instance_identifier: prod-db
    state: present
  delegate_to: localhost
```

### `run_once` — only run on one server

```yaml
# Send one Slack notification for the whole deployment, not one per server
- name: Notify team of deployment
  ansible.builtin.uri:
    url: "https://hooks.slack.com/..."
    method: POST
    body_format: json
    body:
      text: "Deployment of v{{ app_version }} started"
  run_once: true
  delegate_to: localhost

# Run database migration once (on the first DB server only)
- name: Migrate database
  ansible.builtin.command: /opt/myapp/bin/migrate
  run_once: true
  delegate_to: "{{ groups['dbservers'][0] }}"
```

---

## 19. Async Tasks

### The problem with long-running tasks

By default, Ansible waits for each task to finish before moving on. If a task takes 20 minutes (like a large file download or database backup), Ansible just sits there. If the SSH connection drops, the task fails.

Async tasks solve this by launching the task and then optionally checking on it later.

### Starting a long task and checking its progress

```yaml
# Start a backup — allow up to 30 minutes, check every 30 seconds
- name: Run full database backup
  ansible.builtin.command: /opt/scripts/full-backup.sh
  async: 1800        # max time allowed (seconds) = 30 minutes
  poll: 30           # check every 30 seconds
```

### Fire-and-forget — launch all at once, then check later

```yaml
# Start deployment on ALL servers simultaneously, then check they all finished
- name: Start deployment on all servers
  ansible.builtin.command: /opt/scripts/deploy.sh
  async: 600         # max 10 minutes
  poll: 0            # 0 = don't wait, move on immediately
  register: deploy_jobs

# ... other tasks can happen here while all servers are deploying ...

- name: Check all deployments finished successfully
  ansible.builtin.async_status:
    jid: "{{ item.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 30
  delay: 20
  loop: "{{ deploy_jobs.results }}"
```

---

## 20. Strategy and Parallelism

### How Ansible processes servers

**Linear (default):** All servers finish Task 1, then all move to Task 2. Safe and predictable.

```yaml
- hosts: webservers
  strategy: linear    # this is the default
```

**Free:** Each server moves to the next task as soon as it's done with the current one, regardless of other servers. Faster for independent tasks.

```yaml
- hosts: all
  strategy: free      # each server races ahead independently
```

### `serial` — rolling updates (critical for production)

Never update all your servers at once — if the new version is broken, they all go down. Use `serial` to do a rolling update.

```yaml
- name: Rolling deploy
  hosts: webservers
  serial: "25%"             # update 25% of servers at a time
  max_fail_percentage: 0    # stop if any server fails

# Progressive rollout — cautious canary strategy
- hosts: webservers
  serial:
    - 1          # first: update just 1 server (canary)
    - "10%"      # then: update 10%
    - "50%"      # then: update 50%
    - "100%"     # finally: update everyone
```

### `throttle` — limit concurrency for rate-limited APIs

```yaml
# Even with 50 parallel connections, only 3 will hit this API at once
- name: Register servers with external service
  ansible.builtin.uri:
    url: "https://api.example.com/register/{{ inventory_hostname }}"
    method: POST
  throttle: 3
```

---

## 21. Privilege Escalation

### What is `become`?

Most configuration tasks require root (administrator) permissions on Linux. `become: true` tells Ansible to use `sudo` to escalate privileges.

```yaml
# Entire play runs with sudo
- hosts: webservers
  become: true          # all tasks use sudo
  become_user: root     # become this user (default: root)

# Only a specific task uses sudo
- name: Reload nginx (needs root)
  ansible.builtin.service:
    name: nginx
    state: reloaded
  become: true

# Become a non-root user (for running migrations as the app user)
- name: Run migration as app user
  ansible.builtin.command: /opt/myapp/bin/migrate
  become: true
  become_user: myapp
```

### Setting up sudo on managed servers

The Ansible user on your managed servers needs password-less sudo. Add this to `/etc/sudoers.d/ansible`:

```
ansible_svc ALL=(ALL) NOPASSWD: ALL
Defaults:ansible_svc !requiretty
```

---

## 22. Connection Plugins

Connection plugins define HOW Ansible connects to servers.

### SSH (default — for Linux/macOS servers)

```ini
# ansible.cfg
[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=300s
pipelining = True     # reuses SSH connections — much faster
```

### Local (run on your own computer)

```yaml
# For tasks that provision cloud resources from your control node
- name: Manage AWS resources
  hosts: localhost
  connection: local    # no SSH, runs locally
  tasks:
    - amazon.aws.s3_bucket:
        name: my-artifacts
        state: present
```

### Docker (for containers)

```yaml
# inventory
my_container:
  ansible_connection: docker

- hosts: my_container
  tasks:
    - ansible.builtin.package:
        name: curl
        state: present
```

### WinRM (for Windows servers)

```yaml
# inventory
win-server-01:
  ansible_connection: winrm
  ansible_winrm_transport: ntlm
  ansible_port: 5986
```

---

## 23. More Useful Modules

### `fetch` — Download files from servers

```yaml
# Pull log files from all servers to your control node
- name: Collect app logs
  ansible.builtin.fetch:
    src: /var/log/myapp/app.log
    dest: ./collected_logs/     # creates a subfolder per server
    flat: false
    fail_on_missing: false

# Output: ./collected_logs/web01.example.com/var/log/myapp/app.log
#         ./collected_logs/web02.example.com/var/log/myapp/app.log
```

### `find` — Find files matching criteria

```yaml
- name: Find log files older than 30 days
  ansible.builtin.find:
    paths: /var/log/myapp
    patterns: "*.log"
    age: 30d
    recurse: true
  register: old_logs

- name: Delete old log files
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: absent
  loop: "{{ old_logs.files }}"
```

### `replace` — Find and replace text in a file

```yaml
- name: Update max_connections setting
  ansible.builtin.replace:
    path: /etc/myapp/app.conf
    regexp: '^max_connections\s*=\s*\d+'    # regex pattern to find
    replace: 'max_connections = {{ max_connections }}'
    backup: true                             # save a backup first
```

### `lineinfile` — Add/modify/remove a single line in a file

```yaml
# Make sure a line exists
- name: Add memory limit to config
  ansible.builtin.lineinfile:
    path: /etc/myapp/app.conf
    line: 'max_memory = 2048'
    state: present

# Remove a deprecated line
- name: Remove old config option
  ansible.builtin.lineinfile:
    path: /etc/myapp/app.conf
    regexp: '^old_setting\s*='
    state: absent
```

### `wait_for` — Wait for something to be ready

```yaml
# Wait for a port to open (app started)
- ansible.builtin.wait_for:
    host: localhost
    port: 8080
    state: started
    delay: 5        # start checking after 5 seconds
    timeout: 60     # give up after 60 seconds

# Wait for a string to appear in a log file
- ansible.builtin.wait_for:
    path: /var/log/myapp/startup.log
    search_regex: "Server started on port {{ app_port }}"
    timeout: 120

# Wait for SSH after a reboot
- name: Trigger reboot
  ansible.builtin.shell: "sleep 5 && reboot"
  async: 1
  poll: 0

- name: Wait for server to come back
  ansible.builtin.wait_for_connection:
    delay: 30
    timeout: 300
```

### `cron` — Manage scheduled tasks

```yaml
# Add a cron job
- name: Schedule daily log rotation
  ansible.builtin.cron:
    name: "rotate app logs"     # a unique name for this cron entry
    minute: "0"
    hour: "2"                   # run at 2:00 AM
    job: "/opt/scripts/rotate_logs.sh > /dev/null 2>&1"
    user: myapp
    state: present

# Remove a cron job
- name: Remove old backup job
  ansible.builtin.cron:
    name: "old backup job"
    state: absent
```

### `git` — Clone and update repositories

```yaml
- name: Deploy application code
  ansible.builtin.git:
    repo: https://github.com/myorg/myapp.git
    dest: /opt/myapp/src
    version: "{{ app_version }}"   # tag, branch, or commit SHA
    depth: 1                       # shallow clone (faster)
```

### `reboot` — Reboot and wait for the server to come back

```yaml
- name: Reboot after kernel update
  ansible.builtin.reboot:
    msg: "Rebooting for kernel update"
    reboot_timeout: 600            # wait up to 10 minutes for it to come back
    post_reboot_delay: 30          # wait 30 seconds after SSH reconnects
    test_command: "uname -r"       # run this to verify it's back
```

### `pause` — Pause execution

```yaml
# Wait for human confirmation
- name: Pause for manual verification
  ansible.builtin.pause:
    prompt: "Check http://{{ inventory_hostname }}/health then press Enter to continue"

# Automatic timed pause
- name: Wait 30 seconds for cache to warm up
  ansible.builtin.pause:
    seconds: 30
```

### Database modules

```yaml
# PostgreSQL
- name: Create PostgreSQL database
  community.postgresql.postgresql_db:
    name: myapp_production
    encoding: UTF8
    state: present
  become_user: postgres

- name: Create PostgreSQL user
  community.postgresql.postgresql_user:
    name: myapp
    password: "{{ db_password }}"
    db: myapp_production
    priv: ALL
  become_user: postgres

# MySQL
- name: Create MySQL database
  community.mysql.mysql_db:
    name: myapp_production
    state: present
    login_user: root
    login_password: "{{ mysql_root_password }}"
```

### AWS modules

```yaml
# Launch a server
- name: Create EC2 instance
  amazon.aws.ec2_instance:
    name: "web-01"
    instance_type: t3.medium
    image_id: ami-0f5ee92e2d63afc18
    key_name: my-keypair
    security_groups: [web-sg]
    state: running
    wait: true

# Create an S3 bucket
- name: Create artifact bucket
  amazon.aws.s3_bucket:
    name: "myapp-artifacts"
    region: us-east-1
    versioning: true
    encryption: AES256
    state: present
```

### Docker modules

```yaml
- name: Pull and run container
  community.docker.docker_container:
    name: myapp
    image: "myorg/myapp:{{ app_version }}"
    state: started
    restart_policy: unless-stopped
    ports:
      - "{{ app_port }}:8080"
    env:
      DATABASE_URL: "postgresql://myapp:{{ db_password }}@{{ db_host }}/myapp"
    volumes:
      - /opt/myapp/data:/app/data
```

---

## 24. Advanced Jinja2 Filters

Filters transform variables. You've seen `| default()` and `| upper`. Here are more powerful ones.

### Filtering lists and dictionaries

```yaml
vars:
  users:
    - { name: alice, active: true,  role: admin }
    - { name: bob,   active: false, role: user }
    - { name: carol, active: true,  role: user }

tasks:
  # Get only active users
  - debug:
      msg: "{{ users | selectattr('active') | map(attribute='name') | list }}"
      # → ["alice", "carol"]

  # Get inactive users
  - debug:
      msg: "{{ users | rejectattr('active') | map(attribute='name') | list }}"
      # → ["bob"]

  # Get active admins
  - debug:
      msg: "{{ users | selectattr('active') | selectattr('role', 'equalto', 'admin') | map(attribute='name') | list }}"
      # → ["alice"]
```

### Essential filter reference

```jinja2
{# Defaults and required values #}
{{ var | default('fallback') }}          # use fallback if undefined
{{ var | mandatory('must be set') }}     # fail with message if undefined

{# Lists #}
{{ list | join(', ') }}                  # ["a","b","c"] → "a, b, c"
{{ list | length }}                      # number of items
{{ list | first }}                       # first item
{{ list | last }}                        # last item
{{ list | unique }}                      # remove duplicates
{{ list | sort }}                        # sort alphabetically

{# Strings #}
{{ string | upper }}                     # "hello" → "HELLO"
{{ string | lower }}                     # "HELLO" → "hello"
{{ string | trim }}                      # remove leading/trailing spaces
{{ string | replace('old', 'new') }}    # replace text

{# Numbers #}
{{ value | int }}                        # convert to integer
{{ value | string }}                     # convert to string

{# Encoding #}
{{ value | b64encode }}                  # base64 encode
{{ value | b64decode }}                  # base64 decode
{{ value | hash('sha256') }}             # SHA-256 hash
{{ value | to_json }}                    # convert to JSON string
{{ value | from_json }}                  # parse JSON string

{# File paths #}
{{ '/etc/myapp/app.conf' | basename }}   # → "app.conf"
{{ '/etc/myapp/app.conf' | dirname }}    # → "/etc/myapp"

{# Security #}
{{ password | password_hash('sha512') }} # hash a password for /etc/shadow
{{ value | quote }}                      # safely quote for shell commands
```

### Jinja2 tests (used in `when` conditions)

```yaml
when: myvar is defined           # variable exists
when: myvar is string            # value is a string
when: myvar is number            # value is a number
when: result is failed           # task result failed
when: result is changed          # task result changed something
when: myvar is match('^web')     # string matches regex from start
when: myvar is search('nginx')   # string contains this pattern
when: version is version('2.0', '>=')  # version comparison
```

---

## 25. Dynamic Inventory

### The problem with static inventory

When you use cloud services (AWS, Azure, GCP), servers come and go constantly. Maintaining a static `hosts.yml` file by hand becomes impossible.

Dynamic inventory plugins automatically discover your servers from the cloud provider.

### AWS dynamic inventory

```yaml
# inventory/aws_ec2.yml
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
  - ap-south-1
filters:
  instance-state-name: running
  tag:Environment: production

# Group servers automatically by their AWS tags
keyed_groups:
  - key: tags.Role
    prefix: role              # role_webserver, role_database, etc.
  - key: placement.region
    prefix: region
```

```bash
# Test it
ansible-inventory -i inventory/aws_ec2.yml --list
ansible-inventory -i inventory/aws_ec2.yml --graph
```

### Adding hosts dynamically during a play

```yaml
# Launch a new server and immediately configure it
- name: Provision and configure new server
  hosts: localhost
  connection: local
  tasks:
    - name: Launch EC2 instance
      amazon.aws.ec2_instance:
        name: new-web-server
        state: running
        wait: true
      register: new_server

    - name: Add to in-memory inventory
      ansible.builtin.add_host:
        name: "{{ new_server.instances[0].private_ip_address }}"
        groups: [newly_provisioned, webservers]
        ansible_user: ec2-user

    - name: Wait for SSH to be ready
      ansible.builtin.wait_for:
        host: "{{ new_server.instances[0].private_ip_address }}"
        port: 22
        timeout: 120

- name: Configure the new server
  hosts: newly_provisioned
  become: true
  roles: [common, nginx, myapp]
```

### Grouping by facts at runtime

```yaml
- name: Group hosts by OS family
  hosts: all
  tasks:
    - ansible.builtin.group_by:
        key: "os_{{ ansible_os_family | lower }}"

- name: Configure Debian hosts
  hosts: os_debian
  tasks:
    - ansible.builtin.apt:
        name: apt-transport-https
        state: present
```

---

## 26. Fact Caching

Gathering facts (section 5) takes 2–5 seconds per server. For 100 servers, that's up to 8 minutes just for fact collection. Fact caching stores the results so Ansible doesn't re-gather them every run.

### Setting up file-based caching

```ini
# ansible.cfg
[defaults]
gathering             = smart        # use cache if available, gather if not cached
fact_caching          = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout  = 86400        # cache for 24 hours (seconds)
```

```bash
# Force a fresh fact gather (ignore cache)
ansible-playbook site.yml --flush-cache
```

### Redis cache (better for teams, production)

```ini
# ansible.cfg
[defaults]
fact_caching          = redis
fact_caching_connection = redis://localhost:6379/0
fact_caching_timeout  = 3600         # cache for 1 hour
```

---

## 27. Execution Environments

An Execution Environment (EE) is a container image that packages Ansible, all required collections, and Python libraries together. This means the same Ansible run will produce identical results regardless of where it runs — on your laptop, in CI, or in Ansible Tower.

### Why use EEs?

Without EEs: "It works on my machine but not in CI" (because different Python/collection versions).
With EEs: Everyone uses the same container image. No more "works on my machine" problems.

### Building an EE

```yaml
# execution-environment.yml
version: 3

images:
  base_image:
    name: ghcr.io/ansible/community-ansible-dev-tools:latest

dependencies:
  galaxy: requirements.yml         # Ansible collections to include
  python: requirements-python.txt  # Python packages to include
  system: bindep.txt               # system packages to include
```

```bash
pip install ansible-builder

# Build the container image
ansible-builder build --tag myorg/my-ee:1.0.0

# Push to container registry
docker push myorg/my-ee:1.0.0
```

### Running playbooks inside an EE

```bash
pip install ansible-navigator

# Run playbook inside the EE container
ansible-navigator run site.yml -i inventory/production/

# Interactive UI
ansible-navigator run site.yml --mode interactive
```

---

## 28. Multi-Play Playbooks

### One file, multiple plays

A single playbook file can contain multiple plays targeting different groups. This lets you orchestrate a full deployment in one command.

```yaml
# site.yml — the master playbook
---

# Play 1: Configure all servers with base settings
- name: Base configuration
  hosts: all
  become: true
  roles: [common, security]

# Play 2: Configure load balancers
- name: Configure load balancers
  hosts: loadbalancers
  become: true
  roles: [haproxy]

# Play 3: Deploy app to web servers (rolling update)
- name: Deploy application
  hosts: appservers
  become: true
  serial: "25%"             # 25% at a time
  roles: [nginx, myapp]

# Play 4: Configure databases
- name: Configure databases
  hosts: dbservers
  become: true
  roles: [postgresql]
```

### `import_playbook` — include other playbook files

```yaml
# site.yml — master orchestrator
---
- name: Apply base config
  ansible.builtin.import_playbook: playbooks/base.yml

- name: Configure load balancers
  ansible.builtin.import_playbook: playbooks/loadbalancers.yml

- name: Deploy application
  ansible.builtin.import_playbook: playbooks/deploy.yml

- name: Run smoke tests
  ansible.builtin.import_playbook: playbooks/smoketests.yml
```

```bash
# Run the full site deployment
ansible-playbook site.yml

# Run just the deployment step
ansible-playbook playbooks/deploy.yml

# Do a dry run of the deployment
ansible-playbook playbooks/deploy.yml --check --diff
```

---

## 29. Windows Management

Ansible can manage Windows servers too, but it connects differently — it uses **WinRM** (Windows Remote Management) instead of SSH.

### Setting up Windows in inventory

```yaml
# inventory/hosts.yml
windows_servers:
  hosts:
    win-web-01:
      ansible_host: 192.168.1.100
      ansible_connection: winrm
      ansible_winrm_transport: ntlm
      ansible_user: Administrator
      ansible_password: "{{ win_password }}"
      ansible_port: 5986                      # HTTPS WinRM port
      ansible_winrm_server_cert_validation: validate
```

### Windows modules

Windows modules start with `ansible.windows.win_` or `chocolatey.chocolatey.win_`:

```yaml
# Copy a file to Windows
- ansible.windows.win_copy:
    src: files/app.exe
    dest: C:\Program Files\MyApp\app.exe

# Install a Windows feature (like IIS)
- ansible.windows.win_feature:
    name: Web-Server
    state: present

# Install software with Chocolatey (Windows package manager)
- chocolatey.chocolatey.win_chocolatey:
    name: googlechrome
    state: present

# Manage Windows services
- ansible.windows.win_service:
    name: MyApp
    state: started
    start_mode: auto

# Run PowerShell commands
- ansible.windows.win_powershell:
    script: |
      $apps = Get-InstalledApps
      Write-Output $apps.Count
  register: ps_result

# Windows registry
- ansible.windows.win_regedit:
    path: HKLM:\Software\MyApp
    name: MaxConnections
    data: 100
    type: dword

# Install Windows Updates
- ansible.windows.win_updates:
    category_names:
      - SecurityUpdates
      - CriticalUpdates
    reboot: true
```

---

## 30. Network Automation

Ansible can configure network devices like Cisco routers and switches, Juniper equipment, and Palo Alto firewalls. This avoids manually logging into each device.

### Cisco IOS example

```yaml
# inventory/network.yml
network_devices:
  hosts:
    core-router-01:
      ansible_host: 192.168.1.1
      ansible_network_os: cisco.ios.ios
      ansible_connection: network_cli
      ansible_user: admin
      ansible_password: "{{ router_password }}"
      ansible_become_method: enable
      ansible_become_password: "{{ enable_password }}"
```

```yaml
# playbook: configure Cisco IOS
- name: Configure Cisco switches
  hosts: network_devices

  tasks:
    - name: Backup config before any changes
      cisco.ios.ios_config:
        backup: true
        backup_options:
          filename: "{{ inventory_hostname }}_{{ ansible_date_time.date }}.cfg"
          dir_path: ./backups/

    - name: Run show commands
      cisco.ios.ios_command:
        commands:
          - show version
          - show interfaces status
      register: ios_output
      changed_when: false           # read-only commands don't change anything

    - name: Configure VLANs
      cisco.ios.ios_vlans:
        config:
          - name: MGMT
            vlan_id: 100
          - name: APP
            vlan_id: 200
        state: merged

    - name: Configure interface
      cisco.ios.ios_interfaces:
        config:
          - name: GigabitEthernet0/1
            description: "Uplink to Core"
            enabled: true
        state: merged

    - name: Verify OSPF neighbors are up
      cisco.ios.ios_command:
        commands: show ip ospf neighbor
      register: ospf_state
      failed_when: "'FULL' not in ospf_state.stdout[0]"
      changed_when: false
```

### Best practices for network automation

```bash
# ALWAYS dry run on network devices first — mistakes can take down networks
ansible-playbook network.yml --check --diff

# Test on one device first
ansible-playbook network.yml --limit core-router-01

# Use tags for specific change windows
ansible-playbook network.yml --tags vlan_changes
```

---

## 31. Quick Reference Cheat Sheet

### Most-used commands

```bash
# Run a playbook
ansible-playbook site.yml

# Dry run
ansible-playbook site.yml --check --diff

# Run on one host only
ansible-playbook site.yml --limit web01

# Use sudo
ansible-playbook site.yml --become

# Pass variables
ansible-playbook site.yml -e "env=staging app_version=2.1"

# Quick one-liner (ad-hoc)
ansible all -m ping
ansible webservers -m command -a "uptime"
ansible webservers -m package -a "name=nginx state=present" --become

# Check inventory
ansible-inventory --graph
ansible-inventory --host web01

# Look up module docs
ansible-doc ansible.builtin.copy

# Install a collection
ansible-galaxy collection install amazon.aws
```

### Most-used modules quick lookup

| What you want to do | Module |
|---|---|
| Install software | `ansible.builtin.package` |
| Copy a file | `ansible.builtin.copy` |
| Deploy a template | `ansible.builtin.template` |
| Start/stop a service | `ansible.builtin.service` |
| Create a user | `ansible.builtin.user` |
| Create a directory | `ansible.builtin.file` |
| Run a command | `ansible.builtin.command` |
| Run a shell command (pipes) | `ansible.builtin.shell` |
| Check if file exists | `ansible.builtin.stat` |
| Edit a line in a file | `ansible.builtin.lineinfile` |
| Find and replace text | `ansible.builtin.replace` |
| Make an HTTP request | `ansible.builtin.uri` |
| Download a file | `ansible.builtin.get_url` |
| Wait for port/file/string | `ansible.builtin.wait_for` |
| Print a message | `ansible.builtin.debug` |
| Set a variable | `ansible.builtin.set_fact` |
| Add a cron job | `ansible.builtin.cron` |
| Reboot a server | `ansible.builtin.reboot` |
| Collect server facts | `ansible.builtin.setup` |

### Jinja2 filters quick lookup

```jinja2
{{ var | default('fallback') }}     # use fallback if undefined
{{ list | join(', ') }}             # list → comma-separated string
{{ list | length }}                 # count items
{{ list | unique }}                 # remove duplicates
{{ list | sort }}                   # sort
{{ string | upper / lower }}        # change case
{{ string | trim }}                 # remove whitespace
{{ string | replace('a', 'b') }}   # replace text
{{ value | int / string }}          # type conversion
{{ value | b64encode }}             # base64 encode
{{ value | to_json }}               # convert to JSON
{{ value | to_yaml }}               # convert to YAML
```

### Common `when` patterns

```yaml
when: ansible_os_family == "Debian"
when: env == "production"
when: ansible_memtotal_mb > 4096
when: myvar is defined
when: not myvar is defined
when: result is failed
when: result is changed
when: "'webserver' in group_names"
when: myvar is match('^web')
```

### Environment variables reference

```bash
ANSIBLE_INVENTORY=/path/to/inventory
ANSIBLE_REMOTE_USER=ubuntu
ANSIBLE_BECOME=true
ANSIBLE_BECOME_METHOD=sudo
ANSIBLE_FORKS=20
ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
ANSIBLE_GATHERING=smart
ANSIBLE_STDOUT_CALLBACK=yaml
```

---

*This guide covers ansible-core 2.14 and later. Always run `--check --diff` before applying changes to production. Start simple, and add complexity only when you need it.*
