# 🤖 Ansible — A Beginner's Friendly Guide

> **No prior automation experience needed.**  
> Every section starts with a plain-English explanation before any code.

---

## Table of Contents

1. [What is Ansible?](#1-what-is-ansible)
2. [Installation and Setup](#2-installation-and-setup)
3. [Inventory — Your Server List](#3-inventory--your-server-list)
4. [Playbooks — Your Automation Recipe](#4-playbooks--your-automation-recipe)
5. [Tasks & Modules](#5-tasks--modules)
6. [Variables](#6-variables)
7. [Control Flow — Conditions & Loops](#7-control-flow--conditions--loops)
8. [Handlers](#8-handlers)
9. [Roles — Organising Your Playbooks](#9-roles--organising-your-playbooks)
10. [Templates](#10-templates)
11. [Vault — Keeping Secrets Safe](#11-vault--keeping-secrets-safe)
12. [Debugging & Troubleshooting](#12-debugging--troubleshooting)
13. [Quick Reference](#13-quick-reference)

---

## 1. What is Ansible?

> 💡 **In plain English**  
> Ansible is a tool that lets you automate tasks on many computers at once.  
> Instead of logging into 50 servers one by one to install software or change a config file,  
> you write a simple text file describing what you want — and Ansible does it for you.

### Why would you use Ansible?

Imagine you manage 20 web servers. Without Ansible, to install Nginx on all of them you'd need to SSH into each server individually, run the install command, and hope you didn't make a typo on server #14.

With Ansible, you write this **once**:

```yaml
- name: Install nginx on all web servers
  hosts: webservers
  tasks:
    - name: Install nginx
      ansible.builtin.package:
        name: nginx
        state: present    # "present" = install if missing
```

...and all 20 servers are done. ✅

### Key ideas — don't skip these!

#### 🔑 Agentless — nothing to install on the other machines

Ansible connects to your servers over regular SSH (the same way you'd log in manually).  
You don't need to install any special software on the servers you're managing.  
**Only your control machine** (where you run Ansible) needs Ansible installed.

#### 🔑 Idempotent — safe to run again and again

"Idempotent" means: running the same task 10 times gives the same result as running it once.

- If nginx is **already installed** → Ansible says `ok` (no change)
- If nginx is **missing** → Ansible installs it and says `changed`

It never installs it twice. ✅

### Ansible vs. a shell script — which to use?

| Situation | Best Choice |
|-----------|-------------|
| Quick one-time task on one server | Shell script |
| Same task on many servers | **Ansible** |
| Need to be safe to re-run anytime | **Ansible** |
| Managing config files consistently | **Ansible** |
| Storing automation in Git for the team | **Ansible** |

---

## 2. Installation and Setup

> ⚡ **What you need before starting**
> - **Control machine:** your laptop or a Linux/macOS machine (Windows needs WSL)
> - **Target machines:** any Linux server you can SSH into — nothing extra needed on them
> - **Python 3:** must be installed on your control machine

### Installing Ansible (Ubuntu / Debian)

```bash
# The easiest way — using pip (Python's package manager)
pip3 install ansible

# Confirm it worked
ansible --version
```

### Installing Ansible (macOS)

```bash
brew install ansible

# Or with pip:
pip3 install ansible
```

### Testing your first connection

```bash
# Replace 192.168.1.10 with your server's IP
ansible all -i "192.168.1.10," -m ping

# You should see:
# 192.168.1.10 | SUCCESS => { "ping": "pong" }
```

> 🎉 **If you see "pong" — Ansible is working!**  
> If you see an error, the most common cause is SSH access.  
> Make sure you can SSH manually first: `ssh user@192.168.1.10`

### Basic ansible.cfg settings

Create a file called `ansible.cfg` in your project folder:

```ini
# ansible.cfg
[defaults]
inventory      = ./hosts.ini   # where your server list lives
remote_user    = ubuntu        # default SSH user
host_key_checking = False      # ok for learning (use True in production)
```

---

## 3. Inventory — Your Server List

> 💡 **In plain English**  
> The inventory is simply a text file that lists all the servers Ansible can talk to.  
> You can group servers (e.g. "web servers", "database servers") and give each group its own settings.

### A simple inventory file (hosts.ini)

```ini
# hosts.ini — list your servers here

[webservers]
192.168.1.10
192.168.1.11

[databases]
192.168.1.20

# One server with a custom SSH user
[staging]
192.168.1.50  ansible_user=ubuntu
```

> 📌 **How groups work**  
> Anything in `[ ]` is a group name. You can target a group by name in your playbooks.  
> - `"webservers"` — runs only on 192.168.1.10 and .11  
> - `"all"` — special keyword that means **every** server in your inventory

### Quick commands to check your inventory

```bash
# See all hosts Ansible knows about
ansible all -i hosts.ini --list-hosts

# Ping all web servers
ansible webservers -i hosts.ini -m ping

# Ping just the databases group
ansible databases -i hosts.ini -m ping
```

### Setting variables per group (group_vars)

Instead of putting variables in the inventory file, create a `group_vars/` folder:

```
group_vars/
  webservers.yml     ← variables for ALL web servers
  databases.yml      ← variables for ALL database servers
```

```yaml
# group_vars/webservers.yml
http_port: 80
app_name: mywebsite
```

---

## 4. Playbooks — Your Automation Recipe

> 💡 **In plain English**  
> A playbook is a YAML file that describes **WHAT** you want Ansible to do and **ON WHICH** servers.  
> Think of it like a recipe: the ingredients are your servers, and the steps are your tasks.

### Your first playbook

```yaml
# install_nginx.yml
---
- name: Set up a web server       # human-friendly description
  hosts: webservers               # which group from your inventory
  become: true                    # use sudo (needed to install software)

  tasks:
    - name: Install nginx
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Make sure nginx is running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true             # start automatically on reboot
```

### Running a playbook

```bash
# Basic run
ansible-playbook install_nginx.yml

# Dry run — see what WOULD happen without actually doing it
ansible-playbook install_nginx.yml --check

# Verbose — shows more detail about what's happening
ansible-playbook install_nginx.yml -v
```

### Understanding the output

| Output word | What it means |
|-------------|---------------|
| `ok` (green) | Task ran — nothing needed to change |
| `changed` (yellow) | Task ran — something was changed |
| `failed` (red) | Something went wrong |
| `skipped` (blue) | Task was skipped (condition not met) |
| `unreachable` (red) | Couldn't connect to the server |

---

## 5. Tasks & Modules

> 💡 **In plain English**  
> A **task** is one single step in your playbook (e.g. "install nginx", "copy a file").  
> A **module** is the tool Ansible uses to perform that step.  
> Ansible has 3,000+ modules — you rarely need to write your own.

### `package` — Install or remove software

```yaml
- name: Install git
  ansible.builtin.package:
    name: git
    state: present   # use "absent" to remove it
```

### `copy` — Copy a file to the server

```yaml
- name: Copy my config file
  ansible.builtin.copy:
    src: my_config.txt        # file on your control machine
    dest: /etc/my_config.txt  # where to put it on the server
    mode: '0644'
```

### `file` — Create folders or change permissions

```yaml
- name: Create a logs directory
  ansible.builtin.file:
    path: /var/log/myapp
    state: directory   # use "absent" to delete it
    mode: '0755'
```

### `service` — Start/stop system services

```yaml
- name: Start and enable nginx
  ansible.builtin.service:
    name: nginx
    state: started      # started / stopped / restarted / reloaded
    enabled: true       # start on boot
```

### `command` — Run a command on the server

```yaml
- name: Check disk space
  ansible.builtin.command: df -h
  register: disk_output       # save the output into a variable
  changed_when: false         # this is read-only, don't report "changed"

- name: Show the result
  ansible.builtin.debug:
    var: disk_output.stdout
```

### `user` — Create or remove a user account

```yaml
- name: Create a deploy user
  ansible.builtin.user:
    name: deploy
    shell: /bin/bash
    state: present
```

### `debug` — Print a message (great for testing!)

```yaml
- name: Print hello
  ansible.builtin.debug:
    msg: "Hello from {{ inventory_hostname }}"
```

> 📌 **The "register" trick**  
> Capture the output of any task into a variable using `register`, then use it later.  
> Common attributes: `result.stdout`, `result.rc`, `result.changed`, `result.stat.exists`

---

## 6. Variables

> 💡 **In plain English**  
> Variables let you avoid repeating yourself. Set a value once, use it everywhere.  
> If it changes, update it in one place only.

### Defining variables in a playbook

```yaml
- name: Deploy my app
  hosts: webservers
  vars:
    app_name: myapp       # ← define it here
    app_port: 8080

  tasks:
    - name: Print the port
      ansible.builtin.debug:
        msg: "{{ app_name }} runs on port {{ app_port }}"
        #     ↑ use {{ double curly braces }} to reference a variable
```

### Variables from a separate file

```yaml
# vars/settings.yml
app_name: myapp
app_port: 8080
db_host: localhost
```

```yaml
# In your playbook, load the file:
- name: Deploy my app
  hosts: webservers
  vars_files:
    - vars/settings.yml
```

### Ansible Facts — automatic variables

> 🔑 **Key Concept**  
> When Ansible connects to a server, it automatically collects information about it (OS, IP, RAM...).  
> This information is called **"facts"** and becomes available as variables automatically.  
> **No code needed — Ansible gathers these for you!**

```yaml
# Facts you can use right away:
{{ ansible_hostname }}              # e.g. "web01"
{{ ansible_os_family }}             # "Debian" or "RedHat"
{{ ansible_distribution }}          # "Ubuntu", "CentOS", etc.
{{ ansible_default_ipv4.address }}  # the server's IP address
{{ ansible_memtotal_mb }}           # total RAM in MB
```

### Passing variables on the command line

```bash
# Use -e to pass a variable when running the playbook
# This is the highest priority — overrides everything else
ansible-playbook deploy.yml -e "app_version=2.0.0"
```

### Variable priority (simplified)

| Priority | Where the variable is defined |
|----------|-------------------------------|
| Lowest | Role defaults (`roles/myrole/defaults/main.yml`) |
| Medium | group_vars, host_vars, playbook `vars:` |
| Highest | Command line `-e` flag |

---

## 7. Control Flow — Conditions & Loops

### 7.1 Conditions with `when`

> 💡 **In plain English**  
> `when` lets you run a task only if a condition is true — like an "if statement" in coding.

```yaml
# Only install apache2 on Debian/Ubuntu systems
- name: Install web server
  ansible.builtin.package:
    name: apache2
    state: present
  when: ansible_os_family == "Debian"
```

```yaml
# Multiple conditions — ALL must be true (AND logic)
- name: Run only in production with enough RAM
  ansible.builtin.debug:
    msg: "Running!"
  when:
    - env == "production"
    - ansible_memtotal_mb >= 2048
```

```yaml
# Check if a variable is defined
- name: Show custom port if set
  ansible.builtin.debug:
    msg: "Port is {{ my_port }}"
  when: my_port is defined
```

### 7.2 Loops

> 💡 **In plain English**  
> `loop` lets you repeat a task for each item in a list.  
> Use `{{ item }}` inside the task to refer to the current list item.

```yaml
# Install multiple packages at once
- name: Install dev tools
  ansible.builtin.package:
    name: "{{ item }}"
    state: present
  loop:
    - git
    - curl
    - vim
```

```yaml
# Create multiple directories
- name: Create folders
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
  loop:
    - /opt/myapp/logs
    - /opt/myapp/config
    - /opt/myapp/data
```

### 7.3 Wait until something is ready

```yaml
# Keep checking every 10 seconds until the server is up
# (try up to 6 times = 1 minute total)
- name: Wait for web server to respond
  ansible.builtin.uri:
    url: "http://localhost:80/"
    status_code: 200
  register: result
  until: result.status == 200
  retries: 6
  delay: 10
```

### 7.4 Block / Rescue / Always — try/catch

> 💡 **In plain English**  
> `block` groups tasks together. If any task in the block fails, `rescue` runs.  
> `always` always runs, whether things succeeded or failed — like a cleanup step.

```yaml
- name: Try to deploy, clean up if it fails
  block:
    - name: Deploy the app
      ansible.builtin.command: /opt/myapp/deploy.sh

  rescue:
    - name: Something went wrong — alert the team
      ansible.builtin.debug:
        msg: "Deployment failed on {{ inventory_hostname }}"

  always:
    - name: Remove the deploy lock file (always do this)
      ansible.builtin.file:
        path: /tmp/deploy.lock
        state: absent
```

---

## 8. Handlers

> 💡 **In plain English**  
> A handler is a task that only runs when it is "notified" by another task.  
> The most common use: **restart a service when its config file changes.**
>
> Handlers are smart — even if 5 tasks all notify the same handler,  
> **the handler only runs ONCE** at the end of the play.

### A simple example

```yaml
---
- name: Configure nginx
  hosts: webservers
  become: true

  tasks:
    - name: Copy nginx config
      ansible.builtin.copy:
        src: nginx.conf
        dest: /etc/nginx/nginx.conf
      notify: Restart nginx       # ← tells the handler to run

  handlers:
    - name: Restart nginx         # ← this name must match exactly
      ansible.builtin.service:
        name: nginx
        state: restarted
```

> 📌 **What happens step by step:**  
> 1. Ansible copies nginx.conf — it changed, so it sends a "notify"  
> 2. All the other tasks in the play run...  
> 3. After **ALL** tasks are done, Ansible runs the handler once  
> 4. nginx restarts  
>
> If the config file did **NOT** change (already identical), the handler is **never** triggered.

---

## 9. Roles — Organising Your Playbooks

> 💡 **In plain English**  
> As your playbooks grow, one big file gets messy.  
> A role is a neat folder structure that groups related tasks, variables, and templates together.  
> Think of it like splitting a long document into chapters.

### The role folder structure

```
roles/
  nginx/
    tasks/
      main.yml       ← all the tasks go here
    handlers/
      main.yml       ← handlers go here
    defaults/
      main.yml       ← default variable values (easy to override)
    templates/
      nginx.conf.j2  ← template config files
    files/
      logo.png       ← static files to copy
```

### Creating a role automatically

```bash
# This command creates all the folders for you
ansible-galaxy role init roles/nginx
```

### A simple role example

```yaml
# roles/nginx/defaults/main.yml — default settings
nginx_port: 80
```

```yaml
# roles/nginx/tasks/main.yml — the actual tasks
---
- name: Install nginx
  ansible.builtin.package:
    name: nginx
    state: present

- name: Start nginx
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: true
```

```yaml
# playbook.yml — using the role
---
- name: Set up web servers
  hosts: webservers
  become: true
  roles:
    - nginx              # just name the role
```

> ✅ **Why use roles?**  
> - **Reusable** — use the same "nginx" role in multiple projects  
> - **Shareable** — publish it on Ansible Galaxy for others to use  
> - **Readable** — each role has a clear, single responsibility

### Getting roles from the internet (Ansible Galaxy)

```bash
# Install a community role (no need to write it yourself!)
ansible-galaxy role install geerlingguy.nginx

# Use it in your playbook just like any other role
roles:
  - geerlingguy.nginx
```

---

## 10. Templates

> 💡 **In plain English**  
> A template is a config file with placeholders (variables) inside it.  
> Ansible fills in the placeholders before copying the file to the server.
>
> One template can generate **different config files** for each server —  
> with the correct IP address, port, and hostname filled in automatically.

### A simple template (motd.j2)

Template files use the `.j2` extension (Jinja2 is the template language):

```jinja2
# templates/motd.j2  (Message of the Day)
Welcome to {{ ansible_hostname }}!
This server runs {{ ansible_distribution }} {{ ansible_distribution_version }}.
IP Address: {{ ansible_default_ipv4.address }}

# {{ variable_name }} is replaced with the actual value when deployed
```

```yaml
# In your playbook, use the "template" module:
- name: Deploy the message of the day
  ansible.builtin.template:
    src: templates/motd.j2      # template on your machine
    dest: /etc/motd             # where to put it on the server
    mode: '0644'
```

### Using if/for in templates

```jinja2
# templates/app.conf.j2
[server]
port = {{ app_port }}

# Conditional — only add this if ssl_enabled is true
{% if ssl_enabled %}
ssl = yes
cert = /etc/ssl/myapp.crt
{% endif %}

# Loop — generate one line per item in a list
[allowed_hosts]
{% for host in allowed_hosts %}
  - {{ host }}
{% endfor %}
```

> 📌 **Safe defaults in templates**  
> Use the `default` filter to provide a fallback value if a variable isn't set:  
> ```
> port = {{ app_port | default(8080) }}
> ```
> If `app_port` is not defined, Ansible uses `8080` instead of crashing.

---

## 11. Vault — Keeping Secrets Safe

> 💡 **In plain English**  
> Ansible Vault lets you encrypt sensitive data (passwords, API keys, certificates)  
> so you can safely store it in Git without anyone being able to read it.
>
> - **Without Vault:** secrets sit in plain text files — dangerous!  
> - **With Vault:** secrets are encrypted — safe to commit to version control.

### Encrypting a string (most common use)

```bash
# Encrypt a single secret value
ansible-vault encrypt_string 'MySecretPassword!' --name 'db_password'

# Output — paste this into your vars file:
# db_password: !vault |
#   $ANSIBLE_VAULT;1.1;AES256
#   6238323865373839...
```

### Encrypting / editing a whole file

```bash
# Encrypt an entire file
ansible-vault encrypt vars/secrets.yml

# Edit an encrypted file (opens your editor)
ansible-vault edit vars/secrets.yml

# View an encrypted file without editing
ansible-vault view vars/secrets.yml
```

### Running a playbook that uses vault

```bash
# Ansible will prompt you for the vault password
ansible-playbook deploy.yml --ask-vault-pass

# Or store the password in a file (easier for automation)
ansible-playbook deploy.yml --vault-password-file ~/.vault_pass
```

> 🔒 **Golden rules for vault**  
> ✅ Always vault: passwords, API keys, SSH private keys  
> ✅ Add `.vault_pass` to your `.gitignore` (never commit it!)  
> ✅ Keep the vault password somewhere secure (password manager)  
> ❌ Never paste plain-text secrets into a playbook

---

## 12. Debugging & Troubleshooting

### Essential commands for troubleshooting

| Command | What it does |
|---------|--------------|
| `ansible-playbook play.yml --syntax-check` | Check for YAML typos before running |
| `ansible-playbook play.yml --check` | Dry run — no actual changes |
| `ansible-playbook play.yml --check --diff` | Dry run + show what files would change |
| `ansible-playbook play.yml -v` | More detail in output |
| `ansible-playbook play.yml -vv` | Even more detail |
| `ansible-playbook play.yml --limit myserver` | Run on just one server |
| `ansible-playbook play.yml --start-at-task "Name"` | Skip to a specific task |
| `ansible all -m ping` | Check all servers are reachable |

### Using debug to inspect variables

```yaml
# Print any variable to see its value
- name: What OS is this?
  ansible.builtin.debug:
    var: ansible_distribution

# Print a custom message
- name: Show the hostname
  ansible.builtin.debug:
    msg: "Running on {{ inventory_hostname }}"
```

### Common errors and fixes

| Error message | What to do |
|---------------|------------|
| `UNREACHABLE! Failed to connect via ssh` | Check SSH access. Can you `ssh` manually? |
| `sudo: a password is required` | Add `become: true` and run with `-K`, or set up passwordless sudo |
| `undefined variable` | Check spelling. Use `\| default('fallback')` |
| `MODULE FAILURE: non-JSON response` | Python may be missing on the target server |
| `Timeout waiting for privilege escalation` | Check `/etc/sudoers` — `requiretty` may be set |

> 💡 **The golden debugging workflow**  
> 1. Run with `--syntax-check` first (catch typos)  
> 2. Run with `--check --diff` (preview changes safely)  
> 3. Run on **ONE** server first: `--limit myserver`  
> 4. Add `-v` for more output if something looks wrong  
> 5. Use `ansible.builtin.debug` to print variables and inspect state

---

## 13. Quick Reference

### Most useful modules at a glance

| Module | What it does |
|--------|--------------|
| `ansible.builtin.package` | Install / remove packages |
| `ansible.builtin.copy` | Copy a file from your machine to the server |
| `ansible.builtin.template` | Copy a Jinja2 template (variables filled in) |
| `ansible.builtin.file` | Create / delete files, dirs, symlinks |
| `ansible.builtin.service` | Start / stop / restart a service |
| `ansible.builtin.user` | Create or remove a user account |
| `ansible.builtin.command` | Run a command (no shell features) |
| `ansible.builtin.shell` | Run a shell command (supports pipes etc.) |
| `ansible.builtin.debug` | Print a message or variable |
| `ansible.builtin.stat` | Check if a file/dir exists |
| `ansible.builtin.uri` | Make an HTTP request |
| `ansible.builtin.lineinfile` | Add/change a line in a file |
| `ansible.builtin.cron` | Manage crontab entries |
| `ansible.builtin.git` | Clone or update a Git repository |
| `ansible.builtin.get_url` | Download a file from a URL |
| `ansible.builtin.set_fact` | Create a variable dynamically at runtime |
| `ansible.builtin.assert` | Fail with a clear message if a condition isn't met |

### Jinja2 filter quick reference

| Filter | Example |
|--------|---------|
| `default()` | `{{ port \| default(8080) }}` ← fallback value |
| `upper` / `lower` | `{{ name \| upper }}` → `"JOHN"` |
| `length` | `{{ mylist \| length }}` → `3` |
| `join()` | `{{ items \| join(', ') }}` → `"a, b, c"` |
| `int` / `string` | `{{ "42" \| int + 1 }}` → `43` |
| `trim` | `{{ " hello " \| trim }}` → `"hello"` |
| `bool` | `{{ "true" \| bool }}` → `True` |

### Common CLI flags cheat sheet

| Flag | Purpose |
|------|---------|
| `-i inventory/` | Specify inventory file or folder |
| `--limit hostname` | Run on a specific host or group |
| `--check` | Dry run (no changes made) |
| `--diff` | Show file differences |
| `-v / -vv / -vvv` | Increase output verbosity |
| `-e "var=value"` | Pass extra variables (highest priority) |
| `--tags tagname` | Only run tasks with this tag |
| `--skip-tags tagname` | Skip tasks with this tag |
| `--ask-become-pass (-K)` | Prompt for sudo password |
| `--ask-vault-pass` | Prompt for vault password |
| `--syntax-check` | Check YAML syntax without running |
| `--list-tasks` | List all tasks without running them |
| `--step` | Prompt before each task (interactive) |

---

## 🚀 Where to go next

- **Official Ansible docs:** https://docs.ansible.com
- **Free community roles:** https://galaxy.ansible.com
- **Try Ansible locally (no server needed):**
  ```bash
  ansible all -i "localhost," -c local -m ping
  ```

---

*Ansible Beginner's Guide — Covers ansible-core ≥ 2.14. Always test in a safe environment before applying to production.*
